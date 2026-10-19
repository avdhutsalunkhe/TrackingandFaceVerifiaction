import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../constants/api_constants.dart';

class ServerTimeService {
  static final ServerTimeService _instance = ServerTimeService._internal();
  factory ServerTimeService() => _instance;
  ServerTimeService._internal();

  final ApiClient _apiClient = ApiClient();

  int _serverOffsetMs = 0;
  bool _isSynchronized = false;
  Timer? _oneSecTicker;
  Timer? _syncTimer;

  // Monotonic reference for offline server time estimation
  final Stopwatch _monotonicStopwatch = Stopwatch();
  DateTime? _lastSyncServerTime;
  DateTime? _lastSyncWallTime;
  DateTime? _lastSyncSuccessTime;

  final ValueNotifier<DateTime> timeNotifier = ValueNotifier<DateTime>(DateTime.now());
  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);

  bool get isSynchronized => _isSynchronized;
  bool get isOnline => isOnlineNotifier.value;
  DateTime? get lastSyncSuccessTime => _lastSyncSuccessTime;
  int get serverOffsetMs => _serverOffsetMs;

  Duration get syncAge {
    if (_lastSyncSuccessTime == null) return const Duration(days: 999);
    if (_monotonicStopwatch.isRunning) {
      return _monotonicStopwatch.elapsed;
    }
    return DateTime.now().difference(_lastSyncSuccessTime!);
  }

  /// Authoritative monotonic estimated server time
  /// Calculation: last_server_time + monotonic_elapsed_time_since_last_sync
  /// Never trusts device wall clock changes directly.
  DateTime get estimatedCurrentServerTime {
    if (_lastSyncServerTime != null && _monotonicStopwatch.isRunning) {
      return _lastSyncServerTime!.add(_monotonicStopwatch.elapsed);
    }
    if (_isSynchronized) {
      return DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch + _serverOffsetMs,
      );
    }
    return DateTime.now();
  }

  /// Backward compatible alias
  DateTime get currentServerTime => estimatedCurrentServerTime;

  String get formattedDate {
    return DateFormat('dd MMM yyyy').format(estimatedCurrentServerTime);
  }

  String get formattedTime {
    return DateFormat('hh:mm:ss a').format(estimatedCurrentServerTime);
  }

  /// Detects if employee changed phone wall clock during operation
  bool get isWallClockTampered {
    if (_lastSyncWallTime == null || !_monotonicStopwatch.isRunning) return false;
    final wallElapsed = DateTime.now().difference(_lastSyncWallTime!).inMilliseconds;
    final monoElapsed = _monotonicStopwatch.elapsedMilliseconds;
    // Discrepancy > 60 seconds indicates manual device clock manipulation
    return (wallElapsed - monoElapsed).abs() > 60000;
  }

  void init() {
    _loadPersistedSyncData();

    if (_oneSecTicker != null) return; // Already running

    // 1-second ticker to update UI seamlessly
    _oneSecTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      timeNotifier.value = estimatedCurrentServerTime;
    });

    // Initial sync
    syncServerTime();

    // 3-second synchronization ticker with authoritative backend
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      syncServerTime();
    });
  }

  Future<void> _loadPersistedSyncData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastServerMs = prefs.getInt('last_server_time');
      final lastSuccessMs = prefs.getInt('last_sync_success_time');
      final offsetMs = prefs.getInt('server_time_offset');
      final lastWallMs = prefs.getInt('last_server_sync_wall_time');

      if (lastServerMs != null && offsetMs != null) {
        _serverOffsetMs = offsetMs;
        if (_lastSyncServerTime == null) {
          _lastSyncServerTime = DateTime.fromMillisecondsSinceEpoch(lastServerMs);
          _lastSyncWallTime = lastWallMs != null ? DateTime.fromMillisecondsSinceEpoch(lastWallMs) : null;
          _lastSyncSuccessTime = lastSuccessMs != null ? DateTime.fromMillisecondsSinceEpoch(lastSuccessMs) : null;
          if (!_monotonicStopwatch.isRunning) {
            _monotonicStopwatch.start();
          }
          _isSynchronized = true;
          timeNotifier.value = estimatedCurrentServerTime;
        }
      }
    } catch (e) {
      debugPrint('[ServerTimeService] Error loading persisted sync: $e');
    }
  }

  Future<void> _persistSyncData({
    required int lastServerTimeMs,
    required int lastWallTimeMs,
    required int offsetMs,
    required int lastSuccessMs,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_server_time', lastServerTimeMs);
      await prefs.setInt('last_server_sync_wall_time', lastWallTimeMs);
      await prefs.setInt('server_time_offset', offsetMs);
      await prefs.setInt('last_sync_success_time', lastSuccessMs);
    } catch (e) {
      debugPrint('[ServerTimeService] Error saving sync: $e');
    }
  }

  Future<bool> syncServerTime() async {
    try {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      final res = await _apiClient.get(ApiConstants.serverTime);
      final endTime = DateTime.now().millisecondsSinceEpoch;
      final roundTripHalf = ((endTime - startTime) / 2).round();

      if (res is Map && res.containsKey('epoch_ms')) {
        final serverEpochMs = (res['epoch_ms'] as num).toInt();
        final trueServerMs = serverEpochMs + roundTripHalf;
        _serverOffsetMs = trueServerMs - endTime;
        _isSynchronized = true;

        // Reset and start monotonic stopwatch from the authoritative server moment
        _lastSyncServerTime = DateTime.fromMillisecondsSinceEpoch(trueServerMs);
        _lastSyncWallTime = DateTime.now();
        _lastSyncSuccessTime = DateTime.now();

        _monotonicStopwatch.reset();
        _monotonicStopwatch.start();

        isOnlineNotifier.value = true;
        timeNotifier.value = estimatedCurrentServerTime;

        // Persist locally for offline fallback
        await _persistSyncData(
          lastServerTimeMs: trueServerMs,
          lastWallTimeMs: _lastSyncWallTime!.millisecondsSinceEpoch,
          offsetMs: _serverOffsetMs,
          lastSuccessMs: _lastSyncSuccessTime!.millisecondsSinceEpoch,
        );

        return true;
      }
    } catch (e) {
      debugPrint('[ServerTimeService] Sync error (offline?): $e');
      isOnlineNotifier.value = false;
    }
    return false;
  }

  void dispose() {
    _oneSecTicker?.cancel();
    _oneSecTicker = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _monotonicStopwatch.stop();
  }
}
