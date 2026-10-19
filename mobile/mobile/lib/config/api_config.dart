import 'package:flutter/foundation.dart';

class ApiConfig {
  // Centralized backend API URLs (Port 8084)
  // LAN (fastest in office): http://192.168.1.91:8084
  // Main public IP:          http://182.66.233.66:8084
  // Secondary public IP:     http://115.244.240.22:8084
  static const String lanApiUrl       = 'http://192.168.1.91:8084';
  static const String primaryApiUrl   = 'http://182.66.233.66:8084';   // Main public
  static const String secondaryApiUrl = 'http://115.244.240.22:8084';  // Secondary

  // Candidate URLs in strict priority order for ping probing
  static const List<String> serverCandidates = [
    lanApiUrl,        // 1st: http://192.168.1.91:8084 (Office LAN)
    primaryApiUrl,    // 2nd: http://182.66.233.66:8084 (Main Public)
    secondaryApiUrl,  // 3rd: http://115.244.240.22:8084 (Secondary Public)
  ];

  static List<String> get effectiveCandidates {
    if (kIsWeb && Uri.base.scheme == 'https') {
      return [Uri.base.origin];
    }
    if (kIsWeb && (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1')) {
      return ['http://127.0.0.1:8084', ...serverCandidates];
    }
    return serverCandidates;
  }

  // Request & Probe timeouts
  static const Duration requestTimeout = Duration(seconds: 5);
  static const Duration healthCheckTimeout = Duration(seconds: 2);

  // Recovery testing settings
  static const Duration recoveryCheckInterval = Duration(seconds: 15);
  static const int requiredRecoverySuccesses = 3;

  // Existing lightweight health endpoint
  static const String healthEndpoint = '/api/health';

  // User-facing generic error messages (No technical details/URLs/IPs exposed)
  static const String serviceUnavailableMessage =
      'Attendance service is temporarily unavailable. Please try again.';
  static const String connectingMessage =
      'Connecting to attendance service...';
}
