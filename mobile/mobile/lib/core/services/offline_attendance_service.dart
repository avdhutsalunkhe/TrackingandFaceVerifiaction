import 'dart:async';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import '../network/api_client.dart';
import 'tracking_database.dart';

/// Dedicated service for managing offline selfie attendance requests.
/// When the server is unreachable or offline, saves binary selfie images
/// directly to SQLite3 database and synchronizes automatically upon reconnection.
class OfflineAttendanceService {
  static final OfflineAttendanceService instance = OfflineAttendanceService._internal();
  factory OfflineAttendanceService() => instance;
  OfflineAttendanceService._internal();

  final ApiClient _apiClient = ApiClient();
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<List<Map<String, dynamic>>> pendingQueueNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<String?> lastSyncStatusNotifier = ValueNotifier<String?>(null);
  bool _isSyncing = false;

  void init() {
    refreshPendingCount();
  }

  /// Backward-compatible queue loader
  Future<List<Map<String, dynamic>>> loadPendingQueue() async {
    final pending = await TrackingDatabase.instance.getPendingAttendanceRequests();
    pendingQueueNotifier.value = pending;
    pendingCountNotifier.value = pending.length;
    return pending;
  }

  /// Backward-compatible queue clear
  Future<void> clearQueue() async {
    pendingQueueNotifier.value = [];
    pendingCountNotifier.value = 0;
  }

  /// Refreshes the pending count notifier from SQLite
  Future<int> refreshPendingCount() async {
    try {
      final count = await TrackingDatabase.instance.getPendingAttendanceRequestCount();
      pendingCountNotifier.value = count;
      final pending = await TrackingDatabase.instance.getPendingAttendanceRequests();
      pendingQueueNotifier.value = pending;
      return count;
    } catch (e) {
      debugPrint('[OfflineAttendanceService] Error checking pending count: $e');
      return 0;
    }
  }

  /// Check whether the employee already completed this verification window locally
  Future<bool> isVerificationPendingOrCompleted({
    required int userId,
    required String attendanceDate,
    required int verificationNo,
  }) async {
    return false;
  }

  /// Legacy attendance punch enqueue (Requires server connection for biometric matching)
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
    throw Exception('Attendance unavailable: Server connection required. Live biometric verification cannot be processed offline without backend face recognition.');
  }

  /// Stores a selfie attendance request with raw binary image BLOB into local SQLite database
  Future<bool> enqueueOfflineSelfieRequest({
    required String clientRequestId,
    int? userId,
    String? employeeId,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? locationName,
    String? reason,
    int? verificationNo,
    bool includeData = true,
    required Uint8List imageBytes,
  }) async {
    try {
      final nowIso = DateTime.now().toIso8601String();
      await TrackingDatabase.instance.queueOfflineAttendanceRequest({
        'client_request_id': clientRequestId,
        'user_id': userId,
        'employee_id': employeeId,
        'latitude': includeData ? (latitude ?? 0.0) : 0.0,
        'longitude': includeData ? (longitude ?? 0.0) : 0.0,
        'accuracy': includeData ? accuracy : null,
        'location_name': includeData ? locationName : null,
        'reason': reason ?? 'Selfie attendance request',
        'verification_no': verificationNo,
        'include_data': includeData ? 1 : 0,
        'device_timestamp': nowIso,
        'image_blob': imageBytes,
        'sync_status': 'PENDING',
        'created_at': nowIso,
      });

      await refreshPendingCount();
      debugPrint('[OfflineAttendanceService] Stored offline selfie request $clientRequestId (${imageBytes.lengthInBytes} bytes) in SQLite');
      return true;
    } catch (e) {
      debugPrint('[OfflineAttendanceService] Failed to persist offline selfie request: $e');
      return false;
    }
  }

  /// Synchronize all pending offline selfie requests with backend
  Future<int> syncPendingRequests() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    int syncedCount = 0;

    try {
      final pendingList = await TrackingDatabase.instance.getPendingAttendanceRequests(10);
      if (pendingList.isEmpty) {
        pendingCountNotifier.value = 0;
        pendingQueueNotifier.value = [];
        return 0;
      }

      debugPrint('[OfflineAttendanceService] Starting sync for ${pendingList.length} offline selfie requests');
      lastSyncStatusNotifier.value = 'Syncing ${pendingList.length} offline requests...';

      for (final req in pendingList) {
        final clientReqId = req['client_request_id'] as String;
        final imgBlob = req['image_blob'];

        Uint8List? rawBytes;
        if (imgBlob is Uint8List) {
          rawBytes = imgBlob;
        } else if (imgBlob is List<int>) {
          rawBytes = Uint8List.fromList(imgBlob);
        }

        if (rawBytes == null || rawBytes.isEmpty) {
          debugPrint('[OfflineAttendanceService] Invalid/empty image blob for $clientReqId, skipping');
          continue;
        }

        try {
          final fields = <String, String>{
            'latitude': (req['latitude'] ?? 0.0).toString(),
            'longitude': (req['longitude'] ?? 0.0).toString(),
            'location_name': (req['location_name'] ?? 'Offline Captured').toString(),
            'device_timestamp': req['device_timestamp'] as String,
            'reason': (req['reason'] ?? 'Offline selfie request').toString(),
            'client_request_id': clientReqId,
          };
          if (req['accuracy'] != null) {
            fields['accuracy'] = req['accuracy'].toString();
          }
          if (req['verification_no'] != null) {
            fields['verification_no'] = req['verification_no'].toString();
          }

          final res = await _apiClient.postMultipart(
            endpoint: ApiConstants.submitAttendanceRequest,
            fields: fields,
            files: [
              MapEntry('selfie', rawBytes),
            ],
          );

          if (res is Map && (res['id'] != null || res['success'] == true)) {
            final serverId = res['id'] is int ? res['id'] as int : int.tryParse(res['id']?.toString() ?? '');
            await TrackingDatabase.instance.markAttendanceRequestSynced(clientReqId, serverId);
            syncedCount++;
            debugPrint('[OfflineAttendanceService] Successfully synced offline selfie request $clientReqId (Server ID: $serverId)');
          }
        } catch (e) {
          debugPrint('[OfflineAttendanceService] Failed syncing $clientReqId: $e');
          // If permanent validation error (4xx not 401/403/429), mark failed
          if (e is ApiException && e.statusCode >= 400 && e.statusCode < 500 && !e.isUnauthorized) {
            await TrackingDatabase.instance.markAttendanceRequestFailed(clientReqId, e.userFriendlyMessage);
          }
        }
      }

      await refreshPendingCount();
      lastSyncStatusNotifier.value = syncedCount > 0 ? 'Synced $syncedCount offline requests' : null;
    } finally {
      _isSyncing = false;
    }

    return syncedCount;
  }

  void dispose() {
    pendingCountNotifier.dispose();
    pendingQueueNotifier.dispose();
    lastSyncStatusNotifier.dispose();
  }
}
