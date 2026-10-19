import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../network/api_client.dart';
import 'tracking_database.dart';
import 'notification_service.dart';
import 'gps_distance_calculator.dart';

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
    final prefs = await SharedPreferences.getInstance();
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

    // 9. Save Point #1 locally if start coordinates exist and no points are recorded yet
    if (startLat != null && startLng != null && _sequenceNumber == 1) {
      final pointId = '${sessionUuid}_pt_1_${startTimeUtc.millisecondsSinceEpoch}';
      final pointData = {
        'session_uuid': sessionUuid,
        'client_point_id': pointId,
        'sequence_number': 1,
        'latitude': startLat,
        'longitude': startLng,
        'accuracy_meters': initialFix?.accuracy ?? 10.0,
        'altitude_meters': initialFix?.altitude ?? 0.0,
        'speed_mps': (initialFix?.speed != null && initialFix!.speed >= 0) ? initialFix.speed : 0.0,
        'bearing_degrees': (initialFix?.heading != null && initialFix!.heading >= 0) ? initialFix.heading : 0.0,
        'recorded_at': startTimeUtc.toIso8601String(),
        'is_gap': 0,
        'sync_status': 'PENDING',
      };
      await _db.insertPoint(pointData);
      _pointStreamController.add(pointData);
      _sequenceNumber = 2;
      debugPrint('[GPS-PIPE][STAGE 4] Initial Point #1 persisted: $pointId');
    }

    // 10. Persistent Foreground Notification
    await NotificationService.instance.showNotification(
      id: 9991,
      title: 'Journey Tracking Active',
      body: 'Recording attendance travel route in background.',
      category: 'TRACKING',
    );

    // 11. Start GPS Stream, Live Poller, and Sync Timer
    _startLocationStream();
    _startLiveLocationPolling();

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) => syncPendingPoints());

    // Trigger immediate background sync
    syncPendingPoints();

    return true;
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

    // Standardized, collision-proof Point ID format: {sessionUuid}_pt_{seq}_{timestampMs}
    final pointSeq = _sequenceNumber++;
    final pointId = '${_activeSessionUuid}_pt_${pointSeq}_${timestamp.millisecondsSinceEpoch}';
    final pointData = {
      'session_uuid': _activeSessionUuid,
      'client_point_id': pointId,
      'sequence_number': pointSeq,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracy_meters': pos.accuracy,
      'altitude_meters': pos.altitude,
      'speed_mps': pos.speed >= 0 ? pos.speed : null,
      'bearing_degrees': pos.heading >= 0 ? pos.heading : null,
      'recorded_at': timestamp.toIso8601String(),
      'is_gap': filterResult.isGap ? 1 : 0,
      'sync_status': 'PENDING',
    };

    // Store in local SQLite first (guaranteed offline safety)
    await _db.insertPoint(pointData);
    debugPrint('[GPS-PIPE][STAGE 4] Persisted to SQLite: pointId=$pointId, seq=$pointSeq');

    _pointStreamController.add(pointData);
    debugPrint('[GPS-PIPE][STAGE 5] Emitted to pointStream: seq=$pointSeq');
  }

  /// Pause current tracking session
  Future<void> pauseTracking() async {
    if (!isActive || _activeSessionUuid == null) return;

    _status = TrackingStatus.paused;
    notifyListeners();

    _positionSub?.cancel();
    _positionSub = null;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;

    final sessionUuid = _activeSessionUuid!;

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

    final sessionUuid = _activeSessionUuid!;
    final totalDist = _totalDistanceMeters;
    final endTime = DateTime.now().toUtc();

    _status = TrackingStatus.stopped;
    _activeSessionUuid = null;
    notifyListeners();

    _positionSub?.cancel();
    _positionSub = null;
    _streamRecoveryTimer?.cancel();
    _streamRecoveryTimer = null;
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;

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

    if (sessionUuid != null && savedDate != null) {
      final todayStr = DateTime.now().toIso8601String().split('T').first;
      if (savedDate == todayStr) {
        debugPrint('[TrackingService] Restoring active tracking session from crash: $sessionUuid');
        _activeSessionUuid = sessionUuid;
        _activeUserId = prefs.getInt('active_tracking_user_id');
        _totalDistanceMeters = prefs.getDouble('active_tracking_distance') ?? 0.0;

        // Restore highest sequence number to prevent collisions
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

        _status = TrackingStatus.active;
        _isResumedAfterPause = true; // Mark resumption so distance doesn't bridge crash interval
        notifyListeners();

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
      }
    }
  }
}
