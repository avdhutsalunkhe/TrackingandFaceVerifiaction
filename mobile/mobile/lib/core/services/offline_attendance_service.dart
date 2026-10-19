import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineAttendanceService {
  static final OfflineAttendanceService _instance = OfflineAttendanceService._internal();
  factory OfflineAttendanceService() => _instance;
  OfflineAttendanceService._internal();

  static const String _queueKey = 'offline_attendance_queue_v2';

  final ValueNotifier<List<Map<String, dynamic>>> pendingQueueNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<String?> lastSyncStatusNotifier = ValueNotifier<String?>(null);

  void init() {
    clearQueue();
  }

  /// Wipe any local offline queue from device storage
  Future<void> clearQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_queueKey);
      pendingQueueNotifier.value = [];
    } catch (e) {
      debugPrint('[OfflineAttendanceService] Error clearing queue: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadPendingQueue() async {
    await clearQueue();
    return [];
  }

  /// Check whether the employee already completed this verification window locally
  Future<bool> isVerificationPendingOrCompleted({
    required int userId,
    required String attendanceDate,
    required int verificationNo,
  }) async {
    return false;
  }

  /// Enqueues a new offline attendance event (Disabled: Live online server connection required)
  Future<Map<String, dynamic>> enqueueOfflineAttendance({
    required int userId,
    required String attendanceDate,
    required int verificationNo,
    required String verificationWindow,
    required double latitude,
    required double longitude,
    required double? accuracy,
    required double geofenceDistance,
    required String faceResult,
    required String livenessResult,
    required double verificationScore,
    Uint8List? imageBytes,
  }) async {
    throw Exception('Attendance unavailable: Server connection required. Offline local verification and pending sync are disabled.');
  }

  /// Synchronize pending offline items (Disabled: Offline queuing deactivated)
  Future<void> triggerSync() async {
    await clearQueue();
  }

  void dispose() {}
}
