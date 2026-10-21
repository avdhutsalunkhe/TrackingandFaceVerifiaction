import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/coordinate_point_model.dart';
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

enum TrackingState {
  scheduled,
  active,
  degraded,
  interrupted,
  recovering,
  completed,
  incomplete,
}

class TrackingService with ChangeNotifier {
  static final TrackingService instance = TrackingService._internal();
  TrackingService._internal();

  final ApiClient _apiClient = ApiClient();
  final TrackingDatabase _db = TrackingDatabase.instance;
  final GpsDistanceCalculator _distanceCalculator = GpsDistanceCalculator();
  final KalmanLatLongFilter _kalmanFilter = KalmanLatLongFilter(qMetersPerSecond: 3.0);

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Map<String, dynamic>>? _nativeEventSub;
  Timer? _syncTimer;
  Timer? _liveLocationTimer;
  Timer? _streamRecoveryTimer;
  Timer? _heartbeatTimer;

  TrackingStatus _status = TrackingStatus.idle;
  TrackingStatus get status => _status;

  TrackingState _trackingState = TrackingState.scheduled;
  TrackingState get trackingState => _trackingState;

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

  /// Transparently initialize and start/schedule automatic background GPS tracking
  /// without requiring manual confirmation dialogs or button clicks from the employee.
  Future<void> initializeAutomaticDailyTracking({
    required int userId,
    required String employeeId,
    bool is24x7 = true,
    String startTime = '08:00',
    String endTime = '18:00',
    String timezone = 'Asia/Kolkata',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final travelMapEnabled = prefs.getBool('travel_map_enabled') ?? true;
    if (!travelMapEnabled) {
      debugPrint('[TrackingService] travel_map_enabled is false. Automatic tracking disabled.');
      return;
    }

    await prefs.setInt('user_id', userId);
    await prefs.setString('employee_id', employeeId);
    await prefs.setBool('tracking_mode_24x7', is24x7);
    await prefs.setString('tracking_schedule_start', startTime);
    await prefs.setString('tracking_schedule_end', endTime);
    await prefs.setString('tracking_timezone', timezone);

    // Request permissions and battery optimizations transparently in background
    await _verifyLocationPrerequisites();
    await NativeBackgroundTracking.requestBatteryOptimizationExemption();

    // Configure native Android scheduler (evaluates schedule & starts service if in window)
    await NativeBackgroundTracking.scheduleTracking(
      userId: userId,
      is24x7: is24x7,
      startTime: startTime,
      endTime: endTime,
      timezone: timezone,
    );

    // Start background sync timer for offline SQLite points
    _listenToNativeEvents();
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) => syncPendingPoints());
    syncPendingPoints();
  }

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

    // 3. Resolve session UUID with canonical deterministic format
    final savedUuid = prefs.getString('active_tracking_session_uuid');
    final savedDate = prefs.getString('active_tracking_date');

    String sessionUuid;
    if (savedUuid != null && savedDate == todayStr) {
      sessionUuid = savedUuid;
    } else {
      final shiftPart = shiftId != null ? 'SHIFT_$shiftId' : 'PUNCH_$punchId';
      sessionUuid = 'TRACK_${userId}_${shiftPart}_$todayStr';
    }

    _activeSessionUuid = sessionUuid;
    _activeUserId = userId;
    _trackingState = TrackingState.active;

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
      _kalmanFilter.reset(
        _lastRecordedPosition!.latitude,
        _lastRecordedPosition!.longitude,
        10.0,
        _lastRecordedTime?.millisecondsSinceEpoch,
      );
    } else if (startLat != null && startLng != null) {
      _startPosition = LatLng(startLat, startLng);
      _lastRecordedPosition = _startPosition;
      _lastRecordedTime = initialFix?.timestamp.toUtc() ?? DateTime.now().toUtc();
      _distanceCalculator.restoreReference(_startPosition, _lastRecordedTime);
      _kalmanFilter.reset(
        startLat,
        startLng,
        initialFix?.accuracy ?? 10.0,
        _lastRecordedTime?.millisecondsSinceEpoch,
      );
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

    // 11. Start GPS Stream, Live Poller, Sync Timer, and Heartbeat
    _startLocationStream();
    _startLiveLocationPolling();
    _startHeartbeatTimer();

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
      (data) async {
        if (data.containsKey('event_type')) {
          final eventType = data['event_type'] as String;
          final details = data['details']?.toString();
          debugPrint('[GPS-PIPE][NATIVE-EVENT] $eventType: $details');
          if (eventType == 'GPS_DISABLED') {
            _gpsError = 'Location services disabled on device.';
            await recordInterruption(
              reasonCode: 'LOCATION_SERVICES_DISABLED',
              description: 'User or OS disabled location services.',
              severity: 'CRITICAL',
            );
          } else if (eventType == 'GPS_RESTORED') {
            _gpsError = null;
            await recordRecovery(
              reasonCode: 'LOCATION_SERVICES_DISABLED',
              outcome: 'RESOLVED',
              notes: 'Location services restored by user or OS.',
            );
          } else if (eventType == 'SERVICE_STARTED' || eventType == 'SERVICE_RESTARTED') {
            await recordRecovery(
              reasonCode: 'BACKGROUND_SERVICE_STOPPED',
              outcome: 'RESOLVED',
              notes: 'Foreground service resumed/restarted.',
            );
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

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await sendHeartbeat();
    });
  }

  Future<void> sendHeartbeat() async {
    if (!isActive || _activeSessionUuid == null) return;
    try {
      final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      final isFgRunning = await NativeBackgroundTracking.isServiceRunning();

      final res = await _apiClient.post(
        '/api/tracking/heartbeat',
        body: {
          'session_uuid': _activeSessionUuid,
          'battery_level': null,
          'is_charging': null,
          'network_type': 'ONLINE',
          'location_services_enabled': isGpsEnabled,
          'permission_status': perm.name,
          'is_foreground_service_running': isFgRunning,
          'last_point_timestamp': _lastRecordedTime?.toIso8601String(),
        },
      );
      if (res is Map && res['should_stop'] == true) {
        debugPrint('[TrackingService] Backend requested tracking stop (shift concluded)');
        await stopTrackingForPunchOut();
      }
    } catch (e) {
      debugPrint('[TrackingService] Heartbeat deferred (offline): $e');
    }
  }

  Future<void> recordInterruption({
    required String reasonCode,
    String? description,
    String severity = 'WARNING',
    Map<String, dynamic>? diagnostics,
    bool isConfirmed = true,
  }) async {
    if (_activeSessionUuid == null) return;
    final now = DateTime.now().toUtc();
    final eventUuid = 'INT_${_activeSessionUuid}_${reasonCode}_${now.millisecondsSinceEpoch}';

    if (reasonCode == 'POOR_ACCURACY') {
      _trackingState = TrackingState.degraded;
    } else {
      _trackingState = TrackingState.interrupted;
    }
    _gpsError = description ?? reasonCode;
    notifyListeners();

    // 1. Record to local SQLite (offline-first durability)
    await _db.recordInterruptionEvent(
      eventUuid: eventUuid,
      sessionUuid: _activeSessionUuid!,
      userId: _activeUserId ?? 0,
      reasonCode: reasonCode,
      description: description ?? 'Tracking interrupted: $reasonCode',
      detectedAt: now,
      lastKnownFixAt: _lastRecordedTime,
      severity: severity,
      diagnostics: diagnostics,
      isConfirmed: isConfirmed,
    );

    // 2. Post immediately if online
    try {
      final res = await _apiClient.post(
        '/api/tracking/interruption',
        body: {
          'session_uuid': _activeSessionUuid,
          'event_uuid': eventUuid,
          'reason_code': reasonCode,
          'description': description,
          'detected_at': now.toIso8601String(),
          'last_known_location_time': _lastRecordedTime?.toIso8601String(),
          'severity': severity,
          'diagnostic_details': diagnostics,
          'is_confirmed': isConfirmed,
        },
      );
      if (res is Map && res['success'] == true) {
        await _db.markInterruptionEventsSynced([eventUuid]);
      }
    } catch (e) {
      debugPrint('[TrackingService] Interruption event queued offline: $e');
    }
  }

  Future<void> recordRecovery({
    String? reasonCode,
    String outcome = 'RESOLVED',
    String? notes,
  }) async {
    if (_activeSessionUuid == null) return;
    final now = DateTime.now().toUtc();

    _trackingState = TrackingState.recovering;
    notifyListeners();

    // 1. Close event in SQLite
    final closedEventUuid = await _db.closeInterruptionEvent(
      sessionUuid: _activeSessionUuid!,
      reasonCode: reasonCode,
      recoveredAt: now,
      outcome: outcome,
    );

    _gpsError = null;
    _trackingState = TrackingState.active;
    notifyListeners();

    // 2. Post recovery to backend
    try {
      final res = await _apiClient.post(
        '/api/tracking/recovery',
        body: {
          'session_uuid': _activeSessionUuid,
          'event_uuid': closedEventUuid,
          'reason_code': reasonCode,
          'recovered_at': now.toIso8601String(),
          'recovery_outcome': outcome,
          'notes': notes,
        },
      );
      if (res is Map && res['success'] == true && closedEventUuid != null) {
        await _db.markInterruptionEventsSynced([closedEventUuid]);
      }
    } catch (e) {
      debugPrint('[TrackingService] Recovery queued offline: $e');
    }
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

    // 1. 2D Kalman Filtering: eliminate raw sensor noise and coordinate jitter
    final filtered = _kalmanFilter.process(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      timestampMs: timestamp.millisecondsSinceEpoch,
      altitude: pos.altitude != 0 ? pos.altitude : null,
      speed: pos.speed >= 0 ? pos.speed : null,
    );

    final safeFilteredAccuracy = filtered.accuracy ?? pos.accuracy;

    // 2. Multi-Stage Anomaly Filtering (5-stage gate)
    final filterResult = _distanceCalculator.processFix(
      latitude: filtered.latitude,
      longitude: filtered.longitude,
      accuracyMeters: safeFilteredAccuracy,
      timestamp: timestamp,
      speedMps: pos.speed >= 0 ? pos.speed : null,
      isResumedAfterPause: _isResumedAfterPause,
    );

    if (_isResumedAfterPause) {
      _isResumedAfterPause = false;
    }

    if (!filterResult.isAccepted) {
      debugPrint('[GPS-PIPE][STAGE 3] Fix rejected: ${filterResult.rejectionReason}');
      final reason = filterResult.rejectionReason ?? '';
      if (reason.contains('Accuracy too low')) {
        await recordInterruption(
          reasonCode: 'POOR_ACCURACY',
          description: reason,
          severity: 'WARNING',
          diagnostics: {
            'accuracy_meters': safeFilteredAccuracy,
            'max_allowed': _distanceCalculator.maxAllowedAccuracyMeters,
          },
        );
      } else if (reason.contains('Implied speed excessive')) {
        await recordInterruption(
          reasonCode: 'GPS_GLITCH_UNSTABLE',
          description: reason,
          severity: 'WARNING',
          diagnostics: {
            'implied_speed': reason,
          },
        );
      }
      return;
    }

    // Fix accepted: if we were degraded due to POOR_ACCURACY or GPS_GLITCH_UNSTABLE, recover
    if (_activeSessionUuid != null) {
      final activeInt = await _db.getActiveInterruption(_activeSessionUuid!);
      if (activeInt != null) {
        final code = activeInt['reason_code'] as String?;
        if (code == 'POOR_ACCURACY' || code == 'GPS_GLITCH_UNSTABLE') {
          await recordRecovery(
            reasonCode: code,
            outcome: 'RESOLVED',
            notes: 'High-quality GPS coordinates restored (accuracy: ${safeFilteredAccuracy.toStringAsFixed(1)}m).',
          );
        }
      }
    }

    debugPrint('[GPS-PIPE][STAGE 3] Fix accepted: +${filterResult.distanceAddedMeters.toStringAsFixed(1)}m, gap=${filterResult.isGap}');

    _gpsError = null;
    _currentAccuracy = safeFilteredAccuracy;
    _lastRecordedPosition = LatLng(filtered.latitude, filtered.longitude);
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
      latitude: filtered.latitude,
      longitude: filtered.longitude,
      timestamp: timestamp,
      speedMps: pos.speed >= 0 ? pos.speed : null,
      bearingDegrees: pos.heading >= 0 ? pos.heading : null,
      isGap: filterResult.isGap,
    );

    final seq = _sequenceNumber++;
    final vertex = RouteVertex(
      latitude: filtered.latitude,
      longitude: filtered.longitude,
      timestamp: timestamp,
      accuracyMeters: safeFilteredAccuracy,
      speedMps: pos.speed >= 0 ? pos.speed : null,
      bearingDegrees: pos.heading >= 0 ? pos.heading : null,
      isGap: filterResult.isGap,
    );

    // Persist every valid raw GPS point into local database as authoritative source of truth
    final clientPointId = '${_activeSessionUuid}_pt_${seq}_${timestamp.millisecondsSinceEpoch}';
    try {
      await _db.insertPoint({
        'session_uuid': _activeSessionUuid!,
        'client_point_id': clientPointId,
        'sequence_number': seq,
        'latitude': filtered.latitude,
        'longitude': filtered.longitude,
        'accuracy_meters': safeFilteredAccuracy,
        'altitude_meters': pos.altitude != 0 ? pos.altitude : null,
        'speed_mps': pos.speed >= 0 ? pos.speed : null,
        'bearing_degrees': pos.heading >= 0 ? pos.heading : null,
        'recorded_at': timestamp.toUtc().toIso8601String(),
        'is_gap': filterResult.isGap ? 1 : 0,
        'sync_status': 'PENDING',
      });
    } catch (e) {
      debugPrint('[TrackingService] Error caching raw point to SQLite: $e');
    }

    // Always emit to live map stream so user sees their immediate position
    _pointStreamController.add(vertex.toMap(sessionUuid: _activeSessionUuid!, sequenceNumber: seq));

    // Send real-time live GPS ping to backend for OpenStreetMap live marker & smart reverse geocoding
    await _maybeSendLivePing(pos);

    if (shouldRetain) {
      _candidateVertices.add(vertex);
      debugPrint('[GPS-PIPE][STAGE 4] Retained candidate vertex #${_candidateVertices.length} (seq=$seq, spd=${pos.speed}m/s)');
      await _flushChunkIfNeeded(force: false);
    } else {
      // Periodic trigger for raw points sync when candidate is stationary/heartbeat
      syncPendingPoints();
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _trackingState = TrackingState.completed;

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

    // 4. Sync pending interruption events
    try {
      final pendingEvents = await _db.getPendingInterruptionEvents();
      if (pendingEvents.isNotEmpty) {
        final eventsPayload = pendingEvents.map((e) {
          return {
            'event_uuid': e['event_uuid'],
            'session_uuid': e['session_uuid'],
            'reason_code': e['reason_code'],
            'description': e['description'],
            'detected_at': e['detected_at'],
            'last_known_location_time': e['last_known_location_time'],
            'recovered_at': e['recovered_at'],
            'duration_seconds': e['duration_seconds'],
            'severity': e['severity'],
            'diagnostic_details': e['diagnostic_details'] != null ? jsonDecode(e['diagnostic_details'] as String) : null,
            'recovery_outcome': e['recovery_outcome'],
            'is_confirmed': (e['is_confirmed'] ?? 1) == 1,
          };
        }).toList();

        debugPrint('[TrackingService] Syncing ${eventsPayload.length} interruption events to /api/tracking/sync-offline-events');
        final res = await _apiClient.post(
          '/api/tracking/sync-offline-events',
          body: {'events': eventsPayload},
        );
        if (res is Map && res['success'] == true) {
          final syncedIds = (res['synced_event_ids'] as List?)?.map((e) => e.toString()).toList() ??
              pendingEvents.map((e) => e['event_uuid'] as String).toList();
          await _db.markInterruptionEventsSynced(syncedIds);
          debugPrint('[TrackingService] Interruption events synced: ${syncedIds.length}');
        }
      }
    } catch (e) {
      debugPrint('[TrackingService] Interruption sync deferred (offline): $e');
    }
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
