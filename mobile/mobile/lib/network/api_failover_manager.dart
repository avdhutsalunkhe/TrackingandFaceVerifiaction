import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

enum ActiveBackend {
  primary,
  secondary,
}

class ApiFailoverManager {
  static final ApiFailoverManager _instance = ApiFailoverManager._internal();
  factory ApiFailoverManager() => _instance;
  ApiFailoverManager._internal();

  String _activeUrl = ApiConfig.primaryApiUrl;

  String get activeUrl => _activeUrl;
  String get primaryUrl => ApiConfig.primaryApiUrl;
  String get secondaryUrl => ApiConfig.secondaryApiUrl;

  ActiveBackend get activeBackend =>
      _activeUrl == ApiConfig.primaryApiUrl ? ActiveBackend.primary : ActiveBackend.secondary;

  // Optional HTTP client injection for testing
  http.Client? httpClient;
  http.Client get _client => httpClient ?? http.Client();

  // Concurrency lock for failover
  bool _isFailoverInProgress = false;
  Completer<String>? _failoverCompleter;

  // Primary recovery tracking (prevents rapid switching/flapping)
  int _consecutivePrimarySuccesses = 0;
  Timer? _recoveryTimer;

  int get consecutivePrimarySuccesses => _consecutivePrimarySuccesses;

  /// Startup logic:
  /// Concurrently ping all candidate servers (Primary, Secondary, LAN, Local).
  /// Automatically selects the first healthy responsive server.
  Future<void> init({bool checkReachable = true}) async {
    // Clear any obsolete custom base URL so ApiConfig is strictly authoritative
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('custom_base_url');
    } catch (_) {}

    if (!checkReachable) return;

    // In an HTTPS web browser (e.g. Netlify), browser security sandbox blocks direct HTTP calls.
    // Use same-origin HTTPS proxy:
    if (kIsWeb && Uri.base.scheme == 'https') {
      _activeUrl = Uri.base.origin;
      debugPrint('[ApiFailoverManager] HTTPS Web environment (${Uri.base.origin}). Using HTTPS same-origin reverse proxy.');
      return;
    }
    try {
      final liveServer = await pingAndDiscoverServer();
      if (liveServer != null) {
        _activeUrl = liveServer;
        if (_activeUrl == ApiConfig.primaryApiUrl) {
          stopRecoveryChecker();
        } else {
          startRecoveryChecker();
        }
        debugPrint('[ApiFailoverManager] Startup ping success: Connected to $_activeUrl');
      } else {
        // None answered ping, default to primary and keep application running
        _activeUrl = ApiConfig.primaryApiUrl;
        debugPrint('[ApiFailoverManager] Startup: No server answered ping. Defaulting to primary.');
      }
    } catch (e) {
      debugPrint('[ApiFailoverManager] Startup ping error: $e');
      _activeUrl = ApiConfig.primaryApiUrl;
    }
  }

  /// Concurrently ping candidate servers with a fast timeout and return the first responding URL
  Future<String?> pingAndDiscoverServer({List<String>? candidates}) async {
    final candidateList = candidates ?? ApiConfig.effectiveCandidates;
    debugPrint('[ApiFailoverManager] Probing candidate servers: $candidateList');

    final futures = candidateList.map((cand) async {
      final ok = await probeHealth(cand, timeout: ApiConfig.healthCheckTimeout);
      return MapEntry(cand, ok);
    }).toList();

    final results = await Future.wait(futures);

    // Pick first responsive candidate according to priority order
    for (final cand in candidateList) {
      final entry = results.firstWhere((r) => r.key == cand, orElse: () => MapEntry(cand, false));
      if (entry.value) {
        debugPrint('[ApiFailoverManager] Active responding server found via ping: $cand');
        return cand;
      }
    }

    return null;
  }

  /// Lightweight probe to check if a backend URL is responsive
  Future<bool> probeHealth(String baseUrl, {Duration? timeout}) async {
    final cleanUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final effectiveTimeout = timeout ?? ApiConfig.healthCheckTimeout;
    try {
      final res = await _client
          .get(Uri.parse('$cleanUrl${ApiConfig.healthEndpoint}'))
          .timeout(effectiveTimeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Concurrency-safe failover trigger:
  /// When active URL fails, concurrently pings all other candidate servers
  /// and automatically switches to the first responding healthy server.
  Future<String> triggerFailover({required String failedUrl}) async {
    // If another request is currently performing failover, wait for it
    if (_isFailoverInProgress && _failoverCompleter != null) {
      return await _failoverCompleter!.future;
    }

    // If activeUrl has already changed away from failedUrl, failover was already completed
    if (_activeUrl != failedUrl) {
      return _activeUrl;
    }

    _isFailoverInProgress = true;
    final completer = Completer<String>();
    _failoverCompleter = completer;

    try {
      debugPrint('[ApiFailoverManager] Server $failedUrl not responding. Pinging other candidates...');
      final remaining = ApiConfig.effectiveCandidates.where((c) => c != failedUrl).toList();

      final nextAlive = await pingAndDiscoverServer(candidates: remaining);

      if (nextAlive != null) {
        _activeUrl = nextAlive;
        debugPrint('[ApiFailoverManager] Failover: Switched from $failedUrl to active server $_activeUrl');
      } else {
        // Fallback toggle between primary and secondary if ping didn't resolve
        if (failedUrl == ApiConfig.primaryApiUrl) {
          _activeUrl = ApiConfig.secondaryApiUrl;
        } else {
          _activeUrl = ApiConfig.primaryApiUrl;
        }
        debugPrint('[ApiFailoverManager] Failover: Alternate server fallback to $_activeUrl');
      }

      if (_activeUrl == ApiConfig.primaryApiUrl) {
        stopRecoveryChecker();
      } else {
        startRecoveryChecker();
      }

      completer.complete(_activeUrl);
      return _activeUrl;
    } catch (e) {
      completer.complete(_activeUrl);
      return _activeUrl;
    } finally {
      _isFailoverInProgress = false;
      _failoverCompleter = null;
    }
  }

  /// Start background periodic recovery checker when not on primary backend
  void startRecoveryChecker() {
    stopRecoveryChecker();
    _consecutivePrimarySuccesses = 0;
    _recoveryTimer = Timer.periodic(ApiConfig.recoveryCheckInterval, (_) {
      checkPrimaryRecovery();
    });
  }

  /// Stop recovery checker
  void stopRecoveryChecker() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _consecutivePrimarySuccesses = 0;
  }

  /// Test primary backend recovery using existing lightweight health endpoint.
  /// Requires consecutive successful checks before switching back to prevent flapping.
  Future<bool> checkPrimaryRecovery() async {
    if (_activeUrl == ApiConfig.primaryApiUrl) {
      stopRecoveryChecker();
      return false;
    }

    final isAlive = await probeHealth(
      ApiConfig.primaryApiUrl,
      timeout: ApiConfig.healthCheckTimeout,
    );

    if (isAlive) {
      _consecutivePrimarySuccesses++;
      debugPrint(
          '[ApiFailoverManager] Primary recovery check succeeded ($_consecutivePrimarySuccesses/${ApiConfig.requiredRecoverySuccesses})');

      if (_consecutivePrimarySuccesses >= ApiConfig.requiredRecoverySuccesses) {
        _activeUrl = ApiConfig.primaryApiUrl;
        stopRecoveryChecker();
        debugPrint(
            '[ApiFailoverManager] Primary backend restored and stable. Switched back to PRIMARY (${ApiConfig.primaryApiUrl}).');
        return true;
      }
    } else {
      _consecutivePrimarySuccesses = 0;
    }

    return false;
  }

  /// Determines whether an error or status code is a network / infrastructure failure
  static bool isInfrastructureFailure(dynamic error, [int? statusCode]) {
    if (statusCode != null) {
      if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
        return true;
      }
    }

    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return true;
    }

    final str = error.toString().toLowerCase();
    if (str.contains('socketexception') ||
        str.contains('connection refused') ||
        str.contains('network is unreachable') ||
        str.contains('failed host lookup') ||
        str.contains('connection reset') ||
        str.contains('software caused connection abort') ||
        str.contains('handshakeexception') ||
        str.contains('timeoutexception') ||
        str.contains('timed out') ||
        str.contains('connection closed') ||
        str.contains('clientexception') ||
        str.contains('failed to fetch')) {
      return true;
    }

    return false;
  }

  /// Update active backend directly
  void setActiveBackend(ActiveBackend backend) {
    _activeUrl = backend == ActiveBackend.primary
        ? ApiConfig.primaryApiUrl
        : ApiConfig.secondaryApiUrl;
    if (backend == ActiveBackend.primary) {
      stopRecoveryChecker();
    } else {
      startRecoveryChecker();
    }
  }

  /// Set active URL directly
  void setActiveUrl(String url) {
    _activeUrl = url.replaceAll(RegExp(r'/+$'), '');
    if (_activeUrl == ApiConfig.primaryApiUrl) {
      stopRecoveryChecker();
    } else {
      startRecoveryChecker();
    }
  }

  /// Reset state for testing or re-initialization
  void resetForTesting({ActiveBackend initial = ActiveBackend.primary}) {
    stopRecoveryChecker();
    _activeUrl = initial == ActiveBackend.primary
        ? ApiConfig.primaryApiUrl
        : ApiConfig.secondaryApiUrl;
    _isFailoverInProgress = false;
    _failoverCompleter = null;
    _consecutivePrimarySuccesses = 0;
  }
}
