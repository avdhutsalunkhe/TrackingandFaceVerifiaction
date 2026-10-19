import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../network/api_client.dart';
import 'tracking_database.dart';
import 'notification_service.dart';
import 'gps_distance_calculator.dart';
import 'route_simplifier.dart';
import 'native_background_tracking.dart';

enum TrackingStatus {
  idle,
  active,
  paused,
  stopped,
  error,
}

class TrackingService with ChangeNotifier {
  static final TrackingService instance = TrackingService._internal();
  TrackingService._internal();

  final ApiClient _apiClient = ApiClient();
  final TrackingDatabase _db = TrackingDatabase.instance;
  final GpsDistanceCalculator _distanceCalculator = GpsDistanceCalculator();

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Map<String, dynamic>>? _nativeEventSub;
  Timer? _syncTimer;
  Timer? _liveLocationTimer;
  Timer? _streamRecoveryTimer;

  TrackingStatus _status = TrackingStatus.idle;
  TrackingStatus get status => _status;

  bool get isTracking => _status == TrackingStatus.active || _status == TrackingStatus.paused;
  bool get isPaused => _status == TrackingStatus.paused;
  bool get isActive => _status == TrackingStatus.active;

  String? _activeSessionUuid;
  String? get activeSessionUuid => _activeSessionUuid;

  int? _activeUserId;
  int? get activeUserId => _activeUserId;

  int _sequenceNumber = 1;
  int get sequenceNumber => _sequenceNumber;

  // Storage-efficient compressed route chunk buffering
  final List<RouteVertex> _candidateVertices = [];
  int _chunkSequence = 1;
  int _retainedPointCount = 0;
  int get retainedPointCount => _retainedPointCount;
  DateTime? _lastChunkFlushTime;

  double _totalDistanceMeters = 0.0;
  double get totalDistanceMeters => _totalDistanceMeters;

  DateTime? _lastRecordedTime;
  DateTime? get lastRecordedTime => _lastRecordedTime;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  LatLng? _lastRecordedPosition;
  LatLng? get lastRecordedPosition => _lastRecordedPosition;

  LatLng? _startPosition;
  LatLng? get startPosition => _startPosition;

  double? _currentAccuracy;
  double? get currentAccuracy => _currentAccuracy;

  String? _gpsError;
  String? get gpsError => _gpsError;

  bool _isResumedAfterPause = false;

  final StreamController<double> _distanceStreamController = StreamController<double>.broadcast();
  Stream<double> get distanceStream => _distanceStreamController.stream;

  final StreamController<Map<String, dynamic>> _pointStreamController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get pointStream => _pointStreamController.stream;

  DateTime? _lastLivePingTime;
  Position? _lastLivePingPosition;
  Map<String, dynamic>? _currentResolvedAddress;
  Map<String, dynamic>? get currentResolvedAddress => _currentResolvedAddress;

  final StreamController<Map<String, dynamic>> _addressStreamController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get addressStream => _addressStreamController.stream;

  /// Start automatic tracking right after login upon user confirmation
  Future<void> startTrackingForLogin({
    required int userId,
    required String employeeId,
    double? startLat,
    double? startLng,
  }) async {
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final sessionId = DateTime.now().millisecondsSinceEpoch;
    await startTrackingForPunchIn(
      userId: userId,
      employeeId: employeeId,
      attendanceDate: todayStr,
      attendanceId: sessionId,
      startLat: startLat,
      startLng: startLng,
    );
  }

  /// Start automatic tracking upon successful Punch-In #1 or duty resume
  Future<bool> startTrackingForPunchIn({
    required int userId,
    String? employeeId,
    String? attendanceDate,
    int? attendanceId,
    int? shiftId,
    double? startLat,
    double? startLng,
  }) async {
    if (isTracking) return true;

    _gpsError = null;

    // 0. Verify if Travel Map feature toggle is enabled for this user
    final prefs = await SharedPreferences.getInstance();
    final travelMapEnabled = prefs.getBool('travel_map_enabled') ?? true;
    if (!travelMapEnabled) {
      debugPrint('[TrackingService] Travel Map feature toggle is disabled. Skipping GPS tracking start.');
      return false;
    }

    // 1. Verify Location Permissions & Hardware Availability
    final hasPermission = await _verifyLocationPrerequisites();
    if (!hasPermission) {
      _status = TrackingStatus.error;
      notifyListeners();
      return false;
    }

    final todayStr = attendanceDate ?? DateTime.now().toIso8601String().split('T')[0];
    final punchId = attendanceId ?? DateTime.now().millisecondsSinceEpoch;

    // 2. Acquire initial high-accuracy location if not provided
    Position? initialFix;
    if (startLat == null || startLng == null) {
      try {
        initialFix = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
        startLat = initialFix.latitude;
        startLng = initialFix.longitude;
      } catch (e) {
        try {
          initialFix = await Geolocator.getLastKnownPosition();
          if (initialFix != null) {
            startLat = initialFix.latitude;
            startLng = initialFix.longitude;
          }
        } catch (_) {}
      }
    }

    // 3. Resolve session UUID
    final savedUuid = prefs.getString('active_tracking_session_uuid');
    final savedDate = prefs.getString('active_tracking_date');

    String sessionUuid;
    if (savedUuid != null && savedDate == todayStr) {
      sessionUuid = savedUuid;
    } else {
      sessionUuid = 'TRACK_${userId}_${todayStr}_PUNCH_$punchId';
    }

    _activeSessionUuid = sessionUuid;
    _activeUserId = userId;

    // 4. Restore or initialize sequence number from SQLite to prevent collisions
    final maxSeq = await _db.getMaxSequenceNumber(sessionUuid);
    _sequenceNumber = maxSeq > 0 ? maxSeq + 1 : 1;

    // 5. Restore or initialize distance and reference point
    _totalDistanceMeters = prefs.getDouble('active_tracking_distance') ?? 0.0;
    final lastPt = await _db.getLastPoint(sessionUuid);
    if (lastPt != null) {
      _lastRecordedPosition = LatLng(
        (lastPt['latitude'] as num).toDouble(),
        (lastPt['longitude'] as num).toDouble(),
      );
      _lastRecordedTime = DateTime.parse(lastPt['recorded_at'] as String);
      _distanceCalculator.restoreReference(_lastRecordedPosition, _lastRecordedTime);
    } else if (startLat != null && startLng != null) {
      _startPosition = LatLng(startLat, startLng);
      _lastRecordedPosition = _startPosition;
      _lastRecordedTime = initialFix?.timestamp.toUtc() ?? DateTime.now().toUtc();
      _distanceCalculator.restoreReference(_startPosition, _lastRecordedTime);
    }

    _currentAccuracy = initialFix?.accuracy ?? (startLat != null ? 10.0 : null);
    _status = TrackingStatus.active;
    notifyListeners();

    // 6. Persist active state to SharedPreferences
    await prefs.setString('active_tracking_session_uuid', sessionUuid);
    await prefs.setInt('active_tracking_user_id', userId);
    await prefs.setInt('active_tracking_attendance_id', punchId);
    await prefs.setString('active_tracking_date', todayStr);

    // 7. Queue session in local SQLite (guaranteed offline durability)
    final startTimeUtc = initialFix?.timestamp.toUtc() ?? DateTime.now().toUtc();
    final localSessionData = {
      'session_uuid': sessionUuid,
      'user_id': userId,
      'attendance_id': punchId,
      'shift_id': shiftId,
      'work_date': todayStr,
      'start_time': startTimeUtc.toIso8601String(),
      'status': 'RECORDING',
      'start_latitude': startLat,
      'start_longitude': startLng,
      'start_accuracy': initialFix?.accuracy ?? 10.0,
      'total_distance_meters': _totalDistanceMeters,
      'total_duration_seconds': 0,
      'sync_status': 'PENDING',
      'stop_sync_status': 'NONE',
    };
    await _db.queueOfflineSession(localSessionData);

    // 8. Try registering session with backend immediately
    try {
      final res = await _apiClient.post(
        '/api/tracking/start',
        body: {
          'session_uuid': sessionUuid,
          'attendance_id': punchId,
          if (shiftId != null) 'shift_id': shiftId,
          if (startLat != null) 'start_latitude': startLat,
          if (startLng != null) 'start_longitude': startLng,
          'start_time': startTimeUtc.toIso8601String(),
          if (initialFix != null) 'start_accuracy_meters': initialFix.accuracy,
          if (initialFix != null) 'start_altitude_meters': initialFix.altitude,
          if (initialFix != null && initialFix.speed >= 0) 'start_speed_mps': initialFix.speed,
          if (initialFix != null && initialFix.heading >= 0) 'start_bearing_degrees': initialFix.heading,
        },
      );
      if (res is Map) {
        if (res['session_uuid'] != null && res['session_uuid'] != sessionUuid) {
          final oldUuid = sessionUuid;
          sessionUuid = res['session_uuid'] as String;
          _activeSessionUuid = sessionUuid;
          await prefs.setString('active_tracking_session_uuid', sessionUuid);
          await _db.rekeySessionUuid(oldUuid, sessionUuid);
          debugPrint('[GPS-PIPE][STAGE 8] Re-keyed local session from $oldUuid to canonical server UUID $sessionUuid');
        }
        await _db.markSessionSynced(sessionUuid);
        _lastSyncTime = DateTime.now();
      }
    } catch (e) {
      debugPrint('[GPS-PIPE][STAGE 8] Offline start; session queued locally in SQLite: $e');
    }

    // 9. Initialize route chunk buffering & save initial vertex
    _candidateVertices.clear();
    _chunkSequence = await _db.getMaxChunkSequence(sessionUuid) + 1;
    _retainedPointCount = await _db.getPointCount(sessionUuid);
    _lastChunkFlushTime = DateTime.now().toUtc();

    if (startLat != null && startLng != null) {
      final initialVertex = RouteVertex(
        latitude: startLat,
        longitude: startLng,
        timestamp: startTimeUtc,
        accuracyMeters: initialFix?.accuracy ?? 10.0,
        speedMps: (initialFix?.speed != null && initialFix!.speed >= 0) ? initialFix.speed : 0.0,
        bearingDegrees: (initialFix?.heading != null && initialFix!.heading >= 0) ? initialFix.heading : 0.0,
        isGap: false,
      );
      _candidateVertices.add(initialVertex);
      final pointData = initialVertex.toMap(sessionUuid: sessionUuid, sequenceNumber: 1);
      _pointStreamController.add(pointData);
      _sequenceNumber = 2;
      debugPrint('[GPS-PIPE][STAGE 4] Initial Point #1 buffered as starting vertex');
    }

    // 10. Start Dedicated Native Android Location Foreground Service
    try {
      await NativeBackgroundTracking.startService(
        sessionUuid: sessionUuid,
        userId: userId,
        attendanceId: punchId,
        date: todayStr,
      );
      _listenToNativeEvents();
    } catch (e) {
      debugPrint('[GPS-PIPE] Native background service start error: $e');
    }

    // 11. Start GPS Stream, Live Poller, and Sync Timer
    _startLocationStream();
    _startLiveLocationPolling();

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) => syncPendingPoints());

    // Trigger immediate background sync
    syncPendingPoints();

    return true;
  }

  void _listenToNativeEvents() {
    _nativeEventSub?.cancel();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    _nativeEventSub = NativeBackgroundTracking.eventStream.listen(
      (data) {
        if (data.containsKey('event_type')) {
          final eventType = data['event_type'] as String;
          final details = data['details']?.toString();
          debugPrint('[GPS-PIPE][NATIVE-EVENT] $eventType: $details');
          if (eventType == 'GPS_DISABLED') {
            _gpsError = 'Location services disabled on device.';
            notifyListeners();
          } else if (eventType == 'GPS_RESTORED') {
            _gpsError = null;
            notifyListeners();
          }
          if (_activeSessionUuid != null) {
            _apiClient.post(
              '/api/tracking/event',
              body: {
                'session_uuid': _activeSessionUuid,
                'event_type': eventType,
                'details': details,
                'timestamp': DateTime.now().toUtc().toIso8601String(),
              },
            ).catchError((_) {});
          }
          return;
        }

        // Native GPS point captured
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        final dist = (data['total_distance_meters'] as num?)?.toDouble();

        if (lat != null && lng != null) {
          _lastRecordedPosition = LatLng(lat, lng);
          _lastRecordedTime = DateTime.now().toUtc();
          _currentAccuracy = (data['accuracy_meters'] as num?)?.toDouble();
          if (dist != null && dist > _totalDistanceMeters) {
            _totalDistanceMeters = dist;
            _distanceStreamController.add(_totalDistanceMeters);
          }
          _pointStreamController.add(data);
          notifyListeners();
        }
      },
      onError: (e) {
        debugPrint('[GPS-PIPE] Native event stream error: $e');
      },
    );
  }

  Future<bool> _verifyLocationPrerequisites() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _gpsError = 'Location services (GPS) are disabled on your device.';
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _gpsError = 'Location permission was denied.';
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _gpsError = 'Location permission permanently denied. Enable in app settings.';
        return false;
      }

      return true;
    } catch (e) {
      _gpsError = 'Error checking location service: $e';
      return false;
    }
  }

  void _startLocationStream() {
    _positionSub?.cancel();
    _streamRecoveryTimer?.cancel();

    LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // Continuous stream: do not stall when stationary or moving slowly
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'FieldStaff Journey Tracking Active',
          notificationText: 'Tracking attendance route in background...',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (pos) => _handleIncomingPosition(pos),
      onError: (err) {
        _gpsError = 'GPS stream interrupted: $err';
        notifyListeners();
        debugPrint('[GPS-PIPE][STAGE 2] GPS stream error: $err; auto-reconnecting in 3s...');
        _scheduleLocationStreamRetry();
      },
      onDone: () {
        debugPrint('[GPS-PIPE][STAGE 2] GPS stream closed; reconnecting in 3s...');
        _scheduleLocationStreamRetry();
      },
    );
  }

  void _scheduleLocationStreamRetry() {
    _streamRecoveryTimer?.cancel();
    if (!isActive || _activeSessionUuid == null) return;
    _streamRecoveryTimer = Timer(const Duration(seconds: 3), () {
      if (isActive && _activeSessionUuid != null) {
        debugPrint('[GPS-PIPE][STAGE 2] Re-establishing GPS position stream...');
        _startLocationStream();
      }
    });
  }

  void _startLiveLocationPolling() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!isActive || _activeSessionUuid == null) return;

      final now = DateTime.now().toUtc();
      if (_lastRecordedTime == null || now.difference(_lastRecordedTime!).inSeconds >= 15) {
        try {
          Position? pos;
          try {
            pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 10),
            );
          } catch (e) {
            pos = await Geolocator.getLastKnownPosition();
          }
          if (pos != null) {
            await _handleIncomingPosition(pos, isLivePoll: true);
            await syncPendingPoints();
          }
        } catch (_) {}
      }
    });
  }

  Future<void> _handleIncomingPosition(Position pos, {bool isLivePoll = false}) async {
    if (!isActive || _activeSessionUuid == null) return;

    final timestamp = pos.timestamp.toUtc();
    debugPrint('[GPS-PIPE][STAGE 1] Location produced (poll=$isLivePoll): lat=${pos.latitude}, lng=${pos.longitude}, acc=${pos.accuracy}m, spd=${pos.speed}m/s');

    final filterResult = _distanceCalculator.processFix(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMeters: pos.accuracy,
      timestamp: timestamp,
      speedMps: pos.speed >= 0 ? pos.speed : null,
      isResumedAfterPause: _isResumedAfterPause,
    );

    if (_isResumedAfterPause) {
      _isResumedAfterPause = false;
    }

    if (!filterResult.isAccepted) {
      debugPrint('[GPS-PIPE][STAGE 3] Fix rejected: ${filterResult.rejectionReason}');
      return;
    }

    debugPrint('[GPS-PIPE][STAGE 3] Fix accepted: +${filterResult.distanceAddedMeters.toStringAsFixed(1)}m, gap=${filterResult.isGap}');

    _gpsError = null;
    _currentAccuracy = pos.accuracy;
    _lastRecordedPosition = LatLng(pos.latitude, pos.longitude);
    _lastRecordedTime = timestamp;

    if (filterResult.distanceAddedMeters > 0.0) {
      _totalDistanceMeters += filterResult.distanceAddedMeters;
      _distanceStreamController.add(_totalDistanceMeters);
      SharedPreferences.getInstance().then((prefs) {
        prefs.setDouble('active_tracking_distance', _totalDistanceMeters);
      }).catchError((_) {});
    }

    notifyListeners();

    // Storage-Efficient Route Geometry & Vertex Retention
    // Every 3s observation contributes to cumulative distance above,
    // but only geometrically meaningful vertices are retained into permanent route chunks.
    final shouldRetain = _distanceCalculator.shouldRetainCandidateVertex(
      latitude: pos.latitude,
      longitude: pos.longitude,
      timestamp: timestamp,
      speedMps: pos.speed >= 0 ? pos.speed : null,
      bearingDegrees: pos.heading >= 0 ? pos.heading : null,
      isGap: filterResult.isGap,
    );

    final seq = _sequenceNumber++;
    final vertex = RouteVertex(
      latitude: pos.latitude,
      longitude: pos.longitude,
      timestamp: timestamp,
      accuracyMeters: pos.accuracy,
      speedMps: pos.speed >= 0 ? pos.speed : null,
      bearingDegrees: pos.heading >= 0 ? pos.heading : null,
      isGap: filterResult.isGap,
    );

    // Always emit to live map stream so user sees their immediate position
    _pointStreamController.add(vertex.toMap(sessionUuid: _activeSessionUuid!, sequenceNumber: seq));

    // Send real-time live GPS ping to backend for OpenStreetMap live marker & smart reverse geocoding
    await _maybeSendLivePing(pos);

    if (shouldRetain) {
      _candidateVertices.add(vertex);
      debugPrint('[GPS-PIPE][STAGE 4] Retained candidate vertex #${_candidateVertices.length} (seq=$seq, spd=${pos.speed}m/s)');
      await _flushChunkIfNeeded(force: false);
    }
  }

  /// Flushes buffered candidate vertices into a compressed route chunk using Douglas-Peucker simplification.
  /// Minimizes permanent database records by over 95% while keeping turns and travelled path exact.

  /// Sends raw GPS coordinates to /api/tracking/live-ping on interval (15s) or movement (>= 25m)
  Future<void> _maybeSendLivePing(Position pos) async {
    if (!isActive) return;

    final now = DateTime.now().toUtc();
    bool shouldPing = false;

    if (_lastLivePingTime == null) {
      shouldPing = true;
    } else {
      final elapsedSec = now.difference(_lastLivePingTime!).inSeconds;
      if (elapsedSec >= 15) {
        shouldPing = true;
      } else if (_lastLivePingPosition != null) {
        final dist = Geolocator.distanceBetween(
          _lastLivePingPosition!.latitude,
          _lastLivePingPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (dist >= 25.0) {
          shouldPing = true;
        }
      }
    }

    if (!shouldPing) return;

    _lastLivePingTime = now;
    _lastLivePingPosition = pos;

    try {
      final body = {
        if (_activeSessionUuid != null) 'session_uuid': _activeSessionUuid,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy_meters': pos.accuracy,
        if (pos.speed >= 0) 'speed_mps': pos.speed,
        if (pos.heading >= 0) 'bearing_degrees': pos.heading,
        if (pos.altitude != 0) 'altitude_meters': pos.altitude,
        'recorded_at': pos.timestamp.toUtc().toIso8601String(),
      };

      final res = await _apiClient.post('/api/tracking/live-ping', body: body);
      if (res is Map && res['address'] != null) {
        _currentResolvedAddress = Map<String, dynamic>.from(res['address']);
        _addressStreamController.add(_currentResolvedAddress!);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[TrackingService] Live ping deferred (offline): $e');
    }
  }

  Future<void> _flushChunkIfNeeded({bool force = false}) async {
    if (_activeSessionUuid == null) return;
    final now = DateTime.now().toUtc();
    final elapsedSec = _lastChunkFlushTime != null ? now.difference(_lastChunkFlushTime!).inSeconds : 999;

    // Conditions: force flush on pause/stop, buffer reaches 15 vertices, or 30s elapsed with >= 2 vertices
    if (!force && _candidateVertices.length < 15 && !(_candidateVertices.length >= 2 && elapsedSec >= 30)) {
      return;
    }

    if (_candidateVertices.isEmpty) return;

    final sessionUuid = _activeSessionUuid!;
    final verticesToProcess = List<RouteVertex>.from(_candidateVertices);

    // Apply Douglas-Peucker simplification with corner/turn protection
    const simplifier = RouteSimplifier(epsilonMeters: 3.5, minTurnAngleDegrees: 12.0);
    final retainedVertices = simplifier.simplify(verticesToProcess);

    if (retainedVertices.isEmpty) return;

    final chunkSeq = _chunkSequence++;
    final chunkUuid = '${sessionUuid}_chk_${chunkSeq}_${now.millisecondsSinceEpoch}';
    final compactList = retainedVertices.map((v) => v.toCompactList()).toList();
    final encodedGeom = jsonEncode(compactList);

    final chunkData = {
      'chunk_uuid': chunkUuid,
      'session_uuid': sessionUuid,
      'chunk_sequence': chunkSeq,
      'point_count': retainedVertices.length,
      'encoded_geometry': encodedGeom,
      'start_time': retainedVertices.first.timestamp.toIso8601String(),
      'end_time': retainedVertices.last.timestamp.toIso8601String(),
      'distance_meters': _totalDistanceMeters,
      'sync_status': 'PENDING',
    };

    await _db.insertRouteChunk(chunkData);
    _retainedPointCount += retainedVertices.length;
    _lastChunkFlushTime = now;

    // Update session summary record in-place
    await _db.updateSessionSummary(sessionUuid, {
      'total_distance_meters': _totalDistanceMeters,
      'retained_point_count': _retainedPointCount,
      'last_accepted_latitude': retainedVertices.last.latitude,
      'last_accepted_longitude': retainedVertices.last.longitude,
      'last_accepted_time': retainedVertices.last.timestamp.toIso8601String(),
    });

    debugPrint('[GPS-PIPE][CHUNK] Saved Chunk #$chunkSeq with ${retainedVertices.length} retained vertices (raw input: ${verticesToProcess.length})');

    // Keep the last retained vertex as continuity anchor for subsequent chunk
    _candidateVertices.clear();
    _candidateVertices.add(retainedVertices.last);

    // Trigger asynchronous background sync
    syncPendingPoints();
  }

  /// Pause current tracking session
  Future<void> pauseTracking() async {
    if (!isActive || _activeSessionUuid == null) return;

    // Flush remaining buffered vertices into final chunk before pausing
    await _flushChunkIfNeeded(force: true);

    _status = TrackingStatus.paused;
    notifyListeners();

    _positionSub?.cancel();
    _positionSub = null;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;

    final sessionUuid = _activeSessionUuid!;

    await NativeBackgroundTracking.pauseService();

    await NotificationService.instance.showNotification(
      id: 9991,
      title: 'Journey Tracking Paused',
      body: 'Location tracking is paused. Tap Resume to continue recording.',
      category: 'TRACKING',
    );

    try {
      await _apiClient.post(
        '/api/tracking/pause',
        body: {'session_uuid': sessionUuid},
      );
    } catch (e) {
      debugPrint('[TrackingService] Offline pause queued: $e');
    }
  }

  /// Resume a paused tracking session
  Future<void> resumeTracking() async {
    if (!isPaused || _activeSessionUuid == null) return;

    final hasPerm = await _verifyLocationPrerequisites();
    if (!hasPerm) {
      _status = TrackingStatus.error;
      notifyListeners();
      return;
    }

    _status = TrackingStatus.active;
    _isResumedAfterPause = true;
    notifyListeners();

    final sessionUuid = _activeSessionUuid!;

    await NativeBackgroundTracking.resumeService();

    await NotificationService.instance.showNotification(
      id: 9991,
      title: 'Journey Tracking Active',
      body: 'Resumed recording attendance travel route.',
      category: 'TRACKING',
    );

    _startLocationStream();
    _startLiveLocationPolling();

    try {
      await _apiClient.post(
        '/api/tracking/resume',
        body: {'session_uuid': sessionUuid},
      );
    } catch (e) {
      debugPrint('[TrackingService] Offline resume queued: $e');
    }
  }

  /// Stop tracking upon Shift End or Punch-Out
  Future<void> stopTrackingForPunchOut({double? endLat, double? endLng}) async {
    if (!isTracking || _activeSessionUuid == null) return;

    // Flush any pending candidate vertices into final chunk before stopping
    await _flushChunkIfNeeded(force: true);

    final sessionUuid = _activeSessionUuid!;
    final totalDist = _totalDistanceMeters;
    final endTime = DateTime.now().toUtc();

    _status = TrackingStatus.stopped;
    _activeSessionUuid = null;
    notifyListeners();

    _positionSub?.cancel();
    _positionSub = null;
    _nativeEventSub?.cancel();
    _nativeEventSub = null;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;

    // Stop Native Android Foreground Service
    await NativeBackgroundTracking.stopService();

    // Queue session stop locally in SQLite
    await _db.queueSessionStop(
      sessionUuid,
      endLat: endLat,
      endLng: endLng,
      endTime: endTime,
      totalDistanceMeters: totalDist,
    );

    // Try telling backend session is completed
    try {
      await _apiClient.post(
        '/api/tracking/stop',
        body: {
          'session_uuid': sessionUuid,
          if (endLat != null) 'end_latitude': endLat,
          if (endLng != null) 'end_longitude': endLng,
          'end_time': endTime.toIso8601String(),
          'total_distance_meters': totalDist,
        },
      );
      await _db.markSessionStopSynced(sessionUuid);
    } catch (e) {
      debugPrint('[TrackingService] Stop signal queued offline: $e');
    }

    // Flush any remaining offline points
    await syncPendingPoints();

    // Clear state from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_tracking_session_uuid');
    await prefs.remove('active_tracking_user_id');
    await prefs.remove('active_tracking_attendance_id');
    await prefs.remove('active_tracking_date');
    await prefs.remove('active_tracking_distance');

    await NotificationService.instance.showNotification(
      id: 9992,
      title: 'Journey Tracking Ended',
      body: 'Travel tracking complete. Total distance: ${(totalDist / 1000).toStringAsFixed(2)} km.',
      category: 'TRACKING',
    );
  }

  /// Handles real-time feature configuration change from server.
  /// If Travel Map tracking is revoked while a session is active, terminates tracking immediately.
  Future<void> handleFeatureConfigurationChange({required bool travelMapEnabled}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('travel_map_enabled', travelMapEnabled);
    if (!travelMapEnabled && isTracking) {
      debugPrint('[TrackingService] travel_map_enabled turned OFF while active. Forcing immediate stop.');
      await stopTrackingForPunchOut();
    }
  }

  /// Synchronizes all queued local sessions, points, and stops with exponential backoff protection
  Future<void> syncPendingPoints() async {
    // 1. Sync pending offline session creations first
    try {
      final pendingSessions = await _db.getPendingSessions();
      for (final s in pendingSessions) {
        try {
          final res = await _apiClient.post(
            '/api/tracking/start',
            body: {
              'session_uuid': s['session_uuid'],
              'attendance_id': s['attendance_id'],
              if (s['shift_id'] != null) 'shift_id': s['shift_id'],
              if (s['start_latitude'] != null) 'start_latitude': s['start_latitude'],
              if (s['start_longitude'] != null) 'start_longitude': s['start_longitude'],
              'start_time': s['start_time'],
              if (s['start_accuracy'] != null) 'start_accuracy_meters': s['start_accuracy'],
            },
          );
          if (res is Map && res['success'] == true) {
            await _db.markSessionSynced(s['session_uuid'] as String);
          }
        } catch (_) {
          // Keep in queue for next sync cycle
        }
      }
    } catch (_) {}

    // 2. Sync pending compressed route chunks (Production storage-efficient protocol)
    try {
      final pendingChunks = await _db.getPendingRouteChunks();
      if (pendingChunks.isNotEmpty) {
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final c in pendingChunks) {
          final suuid = c['session_uuid'] as String;
          grouped.putIfAbsent(suuid, () => []).add(c);
        }

        for (final entry in grouped.entries) {
          final sessionUuid = entry.key;
          final chunksList = entry.value;

          final chunksPayload = chunksList.map((c) {
            return {
              'chunk_uuid': c['chunk_uuid'],
              'chunk_sequence': c['chunk_sequence'],
              'point_count': c['point_count'],
              'encoded_geometry': c['encoded_geometry'],
              'start_time': c['start_time'],
              'end_time': c['end_time'],
              'distance_meters': c['distance_meters'],
            };
          }).toList();

          debugPrint('[GPS-PIPE][STAGE 6] Syncing ${chunksPayload.length} route chunks for session $sessionUuid to /api/tracking/chunks');
          try {
            final res = await _apiClient.post(
              '/api/tracking/chunks',
              body: {
                'session_uuid': sessionUuid,
                'chunks': chunksPayload,
                'current_distance_meters': _totalDistanceMeters,
                'retained_point_count': _retainedPointCount,
              },
            );

            if (res is Map && res['success'] == true) {
              final syncedUuids = (res['synced_chunk_uuids'] as List?)?.map((e) => e.toString()).toList();
              if (syncedUuids != null && syncedUuids.isNotEmpty) {
                await _db.markChunksSynced(syncedUuids);
              } else {
                final allUuids = chunksList.map((c) => c['chunk_uuid'] as String).toList();
                await _db.markChunksSynced(allUuids);
              }
              debugPrint('[GPS-PIPE][STAGE 7] Chunks sync acknowledged: ${syncedUuids?.length ?? chunksPayload.length} chunks confirmed');
              _lastSyncTime = DateTime.now();
              notifyListeners();
            }
          } catch (e) {
            debugPrint('[GPS-PIPE][STAGE 6] Route chunks sync deferred (offline): $e');
          }
        }
      }
    } catch (_) {}

    // 2. Sync batches of recorded route coordinates
    try {
      final pending = await _db.getAllPendingPoints();
      if (pending.isNotEmpty) {
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final p in pending) {
          final suuid = p['session_uuid'] as String;
          grouped.putIfAbsent(suuid, () => []).add(p);
        }

        for (final entry in grouped.entries) {
          final sessionUuid = entry.key;
          final points = entry.value;

          final pointsPayload = points.map((p) {
            return {
              'client_point_id': p['client_point_id'],
              'sequence_number': p['sequence_number'],
              'latitude': p['latitude'],
              'longitude': p['longitude'],
              'accuracy_meters': p['accuracy_meters'],
              'altitude_meters': p['altitude_meters'],
              'speed_mps': p['speed_mps'],
              'bearing_degrees': p['bearing_degrees'],
              'recorded_at': p['recorded_at'],
              'is_gap': (p['is_gap'] ?? 0) == 1,
            };
          }).toList();

          debugPrint('[GPS-PIPE][STAGE 6] Syncing ${pointsPayload.length} points for session $sessionUuid to /api/tracking/points');
          final res = await _apiClient.post(
            '/api/tracking/points',
            body: {
              'session_uuid': sessionUuid,
              'points': pointsPayload,
              'current_distance_meters': _totalDistanceMeters,
            },
          );

          if (res is Map && res['success'] == true) {
            final syncedIds = (res['synced_point_ids'] as List?)?.map((e) => e.toString()).toList();
            if (syncedIds != null && syncedIds.isNotEmpty) {
              await _db.markPointsSynced(syncedIds);
            } else {
              // Backward compatibility fallback: mark batch synced
              final allIds = points.map((p) => p['client_point_id'] as String).toList();
              await _db.markPointsSynced(allIds);
            }

            final rejectedIds = (res['rejected_point_ids'] as List?)?.map((e) => e.toString()).toList();
            if (rejectedIds != null && rejectedIds.isNotEmpty) {
              await _db.markPointsRejected(rejectedIds);
            }

            debugPrint('[GPS-PIPE][STAGE 7] Sync acknowledged by backend: ${syncedIds?.length ?? pointsPayload.length} points confirmed');
            _lastSyncTime = DateTime.now();
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('[GPS-PIPE][STAGE 6] Sync pending points deferred (offline): $e');
    }

    // 3. Sync pending session completions
    try {
      final pendingStops = await _db.getPendingStopSessions();
      for (final s in pendingStops) {
        try {
          final res = await _apiClient.post(
            '/api/tracking/stop',
            body: {
              'session_uuid': s['session_uuid'],
              if (s['end_latitude'] != null) 'end_latitude': s['end_latitude'],
              if (s['end_longitude'] != null) 'end_longitude': s['end_longitude'],
              'end_time': s['end_time'] ?? DateTime.now().toUtc().toIso8601String(),
              'total_distance_meters': s['total_distance_meters'] ?? 0.0,
            },
          );
          if (res is Map && res['success'] == true) {
            await _db.markSessionStopSynced(s['session_uuid'] as String);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Reconciles tracking session upon app restart or process recovery
  Future<void> checkAndRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionUuid = prefs.getString('active_tracking_session_uuid');
    final savedDate = prefs.getString('active_tracking_date');

    // Check if native Android service is currently running in background
    final isNativeRunning = await NativeBackgroundTracking.isServiceRunning();

    if ((sessionUuid != null && savedDate != null) || isNativeRunning) {
      final todayStr = DateTime.now().toIso8601String().split('T').first;
      if (savedDate == todayStr || isNativeRunning) {
        debugPrint('[TrackingService] Restoring active tracking session from background/crash: $sessionUuid (nativeRunning=$isNativeRunning)');
        _activeSessionUuid = sessionUuid;
        _activeUserId = prefs.getInt('active_tracking_user_id');
        _totalDistanceMeters = prefs.getDouble('active_tracking_distance') ?? 0.0;

        // Restore highest sequence number to prevent collisions
        if (sessionUuid != null) {
          final maxSeq = await _db.getMaxSequenceNumber(sessionUuid);
          _sequenceNumber = maxSeq > 0 ? maxSeq + 1 : 1;

          // Restore last known coordinate
          final lastPt = await _db.getLastPoint(sessionUuid);
          if (lastPt != null) {
            _lastRecordedPosition = LatLng(
              (lastPt['latitude'] as num).toDouble(),
              (lastPt['longitude'] as num).toDouble(),
            );
            _lastRecordedTime = DateTime.parse(lastPt['recorded_at'] as String);
            _distanceCalculator.restoreReference(_lastRecordedPosition, _lastRecordedTime);
          }
        }

        _status = TrackingStatus.active;
        _isResumedAfterPause = true; // Mark resumption so distance doesn't bridge crash interval
        notifyListeners();

        // Attach listener to native events and start native service if not already running
        if (!isNativeRunning && sessionUuid != null && _activeUserId != null) {
          await NativeBackgroundTracking.startService(
            sessionUuid: sessionUuid,
            userId: _activeUserId!,
            date: todayStr,
          );
        }
        _listenToNativeEvents();

        await NotificationService.instance.showNotification(
          id: 9991,
          title: 'Journey Tracking Active',
          body: 'Resumed tracking attendance route.',
          category: 'TRACKING',
        );

        _startLocationStream();
        _startLiveLocationPolling();

        _syncTimer?.cancel();
        _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) => syncPendingPoints());
        syncPendingPoints();
      } else {
        // Expired from previous day, clear it
        await prefs.remove('active_tracking_session_uuid');
        await prefs.remove('active_tracking_distance');
        await prefs.remove('active_tracking_user_id');
        await prefs.remove('active_tracking_attendance_id');
        await prefs.remove('active_tracking_date');
        await NativeBackgroundTracking.stopService();
      }
    }
  }

  /// Comprehensive tracking health diagnostics
  Future<Map<String, dynamic>> getTrackingHealth() async {
    final nativeDiag = await NativeBackgroundTracking.getDiagnostics();
    final pendingCount = await _db.getPendingPointCount();
    final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    final isNativeRunning = await NativeBackgroundTracking.isServiceRunning();
    final isBatteryIgnored = await NativeBackgroundTracking.isBatteryOptimizationIgnored();

    String healthState;
    if (_status == TrackingStatus.stopped || _status == TrackingStatus.idle) {
      healthState = 'SESSION_COMPLETED';
    } else if (!isGpsEnabled || permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      healthState = 'PERMISSION_OR_GPS_DISABLED';
    } else if (_lastRecordedTime != null && DateTime.now().toUtc().difference(_lastRecordedTime!).inSeconds < 30) {
      healthState = 'ACTIVE_RECEIVING_FIXES';
    } else if (_status == TrackingStatus.active) {
      healthState = 'ACTIVE_WAITING_FIX';
    } else if (_status == TrackingStatus.paused) {
      healthState = 'PAUSED';
    } else {
      healthState = 'SERVICE_INTERRUPTED';
    }

    return {
      'status': _status.name,
      'health_state': healthState,
      'is_tracking_active': isActive,
      'is_native_service_running': isNativeRunning,
      'is_battery_optimization_ignored': isBatteryIgnored,
      'session_uuid': _activeSessionUuid,
      'user_id': _activeUserId,
      'total_distance_km': (_totalDistanceMeters / 1000.0),
      'last_fix_time': _lastRecordedTime?.toIso8601String(),
      'last_sync_time': _lastSyncTime?.toIso8601String(),
      'last_position': _lastRecordedPosition != null
          ? {'lat': _lastRecordedPosition!.latitude, 'lng': _lastRecordedPosition!.longitude}
          : null,
      'current_accuracy_meters': _currentAccuracy,
      'offline_pending_points': pendingCount,
      'gps_error': _gpsError,
      'native_diagnostics': nativeDiag,
    };
  }
}
