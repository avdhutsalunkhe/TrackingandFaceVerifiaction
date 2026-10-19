import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeBackgroundTracking {
  static const MethodChannel _methodChannel =
      MethodChannel('com.fieldstaff.attendance/background_tracking');
  static const EventChannel _eventChannel =
      EventChannel('com.fieldstaff.attendance/background_tracking_events');

  static Stream<Map<String, dynamic>>? _eventStream;

  /// Starts the native Android Location Foreground Service
  static Future<bool> startService({
    required String sessionUuid,
    required int userId,
    int? attendanceId,
    String? date,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res = await _methodChannel.invokeMethod<bool>('startService', {
        'session_uuid': sessionUuid,
        'user_id': userId,
        'attendance_id': attendanceId ?? 0,
        'date': date,
      });
      debugPrint('[NativeBackgroundTracking] startService returned: $res');
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeBackgroundTracking] startService error: $e');
      return false;
    }
  }

  /// Stops the native Android Location Foreground Service
  static Future<bool> stopService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopService');
      debugPrint('[NativeBackgroundTracking] stopService returned: $res');
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeBackgroundTracking] stopService error: $e');
      return false;
    }
  }

  /// Pauses location updates in the native foreground service
  static Future<bool> pauseService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res = await _methodChannel.invokeMethod<bool>('pauseService');
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeBackgroundTracking] pauseService error: $e');
      return false;
    }
  }

  /// Resumes location updates in the native foreground service
  static Future<bool> resumeService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res = await _methodChannel.invokeMethod<bool>('resumeService');
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeBackgroundTracking] resumeService error: $e');
      return false;
    }
  }

  /// Checks if the native Android Foreground Service is currently running
  static Future<bool> isServiceRunning() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('isServiceRunning');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Checks if battery optimization is disabled for this app
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res =
          await _methodChannel.invokeMethod<bool>('isBatteryOptimizationIgnored');
      return res ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Configures native daily schedule or 24*7 continuous tracking
  static Future<bool> scheduleTracking({
    required int userId,
    bool is24x7 = true,
    String startTime = '08:00',
    String endTime = '18:00',
    String timezone = 'Asia/Kolkata',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res = await _methodChannel.invokeMethod<bool>('scheduleTracking', {
        'user_id': userId,
        'is_24x7': is24x7,
        'start_time': startTime,
        'end_time': endTime,
        'timezone': timezone,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeBackgroundTracking] scheduleTracking error: $e');
      return false;
    }
  }

  /// Triggers immediate schedule evaluation (starts service if in window)
  static Future<bool> evaluateSchedule() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final res = await _methodChannel.invokeMethod<bool>('evaluateSchedule');
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeBackgroundTracking] evaluateSchedule error: $e');
      return false;
    }
  }

  /// Requests the user to disable battery optimization for continuous background tracking
  static Future<void> requestBatteryOptimizationExemption() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _methodChannel
          .invokeMethod('requestBatteryOptimizationExemption');
    } catch (e) {
      debugPrint('[NativeBackgroundTracking] requestBatteryOpt error: $e');
    }
  }

  /// Fetches system and service diagnostics
  static Future<Map<String, dynamic>> getDiagnostics() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return {'platform': 'web_or_non_android'};
    }
    try {
      final res = await _methodChannel.invokeMapMethod<String, dynamic>('getDiagnostics');
      return res ?? {};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Real-time stream of locations and health events emitted from the native service
  static Stream<Map<String, dynamic>> get eventStream {
    if (_eventStream != null) return _eventStream!;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Stream.empty();
    }
    _eventStream = _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _eventStream!;
  }
}
