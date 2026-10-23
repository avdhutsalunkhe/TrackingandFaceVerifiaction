import '../../core/services/tracking_service.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/notification_service.dart';
import '../../widgets/tracking_consent_dialog.dart';
import '../../widgets/location_permission_dialog.dart';
import '../common/notification_center_screen.dart';
import '../admin/employee_travel_map_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/server_time_service.dart';
import '../../core/services/offline_attendance_service.dart';
import '../../models/attendance_model.dart';
import '../../core/utils/responsive_util.dart';
import '../../core/localization/app_translations.dart';
import '../../core/localization/language_service.dart';
import '../../widgets/language_selector.dart';
import '../auth/login_screen.dart';
import 'verify_attendance_screen.dart';
import 'send_attendance_request_screen.dart';
import 'attendance_history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({Key? key}) : super(key: key);

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  final _apiClient = ApiClient();
  final _authService = AuthService();
  final _serverTimeService = ServerTimeService();
  final _offlineService = OfflineAttendanceService();

  bool _isLoading = true;
  bool _isCheckingLocation = false;
  Map<String, dynamic>? _config;
  Timer? _uiRefreshTimer;

  // Developer/Test Mode state (Hidden from normal employees)
  bool _isDeveloperMode = false;
  int _secretTapCount = 0;
  DateTime? _lastSecretTap;

  @override
  void initState() {
    super.initState();
    LanguageService.instance.localeNotifier.addListener(_onLanguageChanged);
    _serverTimeService.init();
    _offlineService.init();
    _loadConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateService.instance.checkForUpdates(context, showNoUpdateNotice: false);
    });

    // Re-evaluate countdown and dynamic availability every 1 second
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LanguageService.instance.localeNotifier.removeListener(_onLanguageChanged);
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final res = await _apiClient.get(ApiConstants.attendanceConfig);
      if (mounted) {
        setState(() {
          _config = res;
        });
      }
      if (res is Map<String, dynamic>) {
        final prefs = await SharedPreferences.getInstance();
        if (res['face_enabled'] != null) await prefs.setBool('face_enabled', res['face_enabled']);
        if (res['geofence_enabled'] != null) await prefs.setBool('geofence_enabled', res['geofence_enabled']);
        if (res['shift_enabled'] != null) await prefs.setBool('shift_enabled', res['shift_enabled']);
        if (res['travel_map_enabled'] != null) {
          final tme = res['travel_map_enabled'] == true;
          await prefs.setBool('travel_map_enabled', tme);
          await TrackingService.instance.handleFeatureConfigurationChange(travelMapEnabled: tme);
        }
        final rawUid = res['user_id'] ?? res['id'] ?? 0;
        final userId = rawUid is int ? rawUid : int.tryParse(rawUid.toString()) ?? 0;
        final empId = res['employee_id']?.toString() ?? '';
        if (userId > 0) {
          TrackingService.instance.initializeAutomaticDailyTracking(
            userId: userId,
            employeeId: empId,
          );
        }
      }
      // Synchronize authoritative server time
      await _serverTimeService.syncServerTime();
    } catch (e) {
      debugPrint('Error loading config: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Calculates the live list of shift punch periods
  List<VerificationWindowItem> _getWindowsWithLiveStatus() {
    final rawRules = _config?['punch_periods'] as List<dynamic>? ??
                     _config?['verification_rules'] as List<dynamic>? ??
                     _config?['verification_windows'] as List<dynamic>? ?? [];

    if (rawRules.isNotEmpty) {
      return rawRules.map((r) => VerificationWindowItem.fromJson(Map<String, dynamic>.from(r))).toList();
    }

    return [];
  }

  /// Helper to parse a time string (e.g. "08:30:00" or "08:30") into a DateTime on the server date
  DateTime? _parseTimeToDateTime(DateTime serverNow, String timeStr) {
    if (timeStr.isEmpty) return null;
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final second = parts.length > 2 ? int.parse(parts[2].split('.')[0]) : 0;
      return DateTime(serverNow.year, serverNow.month, serverNow.day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }

  /// Evaluates countdown notification model dynamically from synchronized server time
  Map<String, dynamic> _evaluateCountdownState(List<VerificationWindowItem> windows) {
    final isOnline = _serverTimeService.isOnline;
    if (!isOnline) {
      return {
        'state': 'SERVER_UNAVAILABLE',
        'title': AppTranslations.tr('server_unavailable_title'),
        'subtitle': AppTranslations.tr('server_unavailable_sub'),
        'icon': Icons.cloud_off_rounded,
        'bgColor': const Color(0xFFFEF2F2),
        'borderColor': const Color(0xFFFCA5A5),
        'textColor': const Color(0xFF991B1B),
        'iconColor': const Color(0xFFDC2626),
      };
    }

    final hasActiveShift = _config?['has_active_shift'] ?? (_config?['shift'] != null);
    if (hasActiveShift == false) {
      return {
        'state': 'NO_SHIFT',
        'title': AppTranslations.tr('no_shift_assigned'),
        'subtitle': AppTranslations.tr('no_shift_assigned_sub'),
        'icon': Icons.info_outline_rounded,
        'bgColor': const Color(0xFFF1F5F9),
        'borderColor': const Color(0xFFCBD5E1),
        'textColor': const Color(0xFF475569),
        'iconColor': const Color(0xFF64748B),
      };
    }

    if (windows.isEmpty) {
      return {
        'state': 'NO_SCHEDULE',
        'title': AppTranslations.tr('no_punch_schedule'),
        'subtitle': AppTranslations.tr('no_punch_schedule_sub'),
        'icon': Icons.calendar_today_rounded,
        'bgColor': const Color(0xFFF8FAFC),
        'borderColor': const Color(0xFFE2E8F0),
        'textColor': const Color(0xFF64748B),
        'iconColor': const Color(0xFF94A3B8),
      };
    }

    final serverNow = _serverTimeService.estimatedCurrentServerTime;

    // 1. Check if an active window is currently AVAILABLE
    final activeWindow = windows.firstWhere(
      (w) {
        if (w.status == 'AVAILABLE') return true;
        // Dynamically compute with synchronized server time
        final sDt = _parseTimeToDateTime(serverNow, w.start);
        final eDt = _parseTimeToDateTime(serverNow, w.end);
        if (sDt != null && eDt != null) {
          return !serverNow.isBefore(sDt) && serverNow.isBefore(eDt) && w.status != 'COMPLETED';
        }
        return false;
      },
      orElse: () => VerificationWindowItem(
        verificationNo: 0,
        start: '',
        end: '',
        label: '',
        status: 'NONE',
      ),
    );

    if (activeWindow.verificationNo > 0) {
      return {
        'state': 'OPEN_NOW',
        'title': AppTranslations.tr('window_open_title'),
        'subtitle': AppTranslations.tr('mark_now'),
        'icon': Icons.check_circle_rounded,
        'bgColor': const Color(0xFFECFDF5),
        'borderColor': const Color(0xFF10B981),
        'textColor': const Color(0xFF065F46),
        'iconColor': const Color(0xFF059669),
        'active_window': activeWindow,
      };
    }

    // 2. Check if all scheduled windows are completed
    final allDone = windows.every((w) => w.status == 'COMPLETED');
    if (allDone) {
      return {
        'state': 'ALL_RECORDED',
        'title': AppTranslations.tr('all_recorded_title'),
        'subtitle': AppTranslations.tr('all_recorded_sub'),
        'icon': Icons.check_circle_outline_rounded,
        'bgColor': const Color(0xFFEFF6FF),
        'borderColor': const Color(0xFF93C5FD),
        'textColor': const Color(0xFF1E40AF),
        'iconColor': const Color(0xFF2563EB),
      };
    }

    // 3. Find next upcoming period
    VerificationWindowItem? nextWindow;
    int minSecondsDiff = 99999999;

    for (final w in windows) {
      if (w.status == 'COMPLETED') continue;
      final sDt = _parseTimeToDateTime(serverNow, w.start);
      if (sDt != null && sDt.isAfter(serverNow)) {
        final diff = sDt.difference(serverNow).inSeconds;
        if (diff < minSecondsDiff) {
          minSecondsDiff = diff;
          nextWindow = w;
        }
      }
    }

    if (nextWindow != null && minSecondsDiff < 99999999) {
      final int diffMinutes = (minSecondsDiff / 60).ceil();
      final String titleText = diffMinutes <= 1
          ? AppTranslations.tr('starts_in_less_min')
          : AppTranslations.tr('starts_in_min', args: {'min': '$diffMinutes'});

      return {
        'state': 'COUNTDOWN',
        'title': titleText,
        'subtitle': AppTranslations.tr('get_ready'),
        'icon': Icons.notifications_active_rounded,
        'bgColor': const Color(0xFFFFFBEB),
        'borderColor': const Color(0xFFFCD34D),
        'textColor': const Color(0xFF92400E),
        'iconColor': const Color(0xFFD97706),
        'minutes_remaining': diffMinutes,
        'next_window': nextWindow,
      };
    }

    // 4. All punch periods have ended/closed
    return {
      'state': 'CLOSED',
      'title': AppTranslations.tr('window_closed_title'),
      'subtitle': AppTranslations.tr('window_closed_desc'),
      'icon': Icons.access_time_filled_rounded,
      'bgColor': const Color(0xFFF8FAFC),
      'borderColor': const Color(0xFFCBD5E1),
      'textColor': const Color(0xFF475569),
      'iconColor': const Color(0xFF64748B),
    };
  }

  /// Formats the shift time range dynamically from earliest punch period to latest punch period
  String _getShiftTimingRange(List<VerificationWindowItem> windows) {
    if (windows.isEmpty) return AppTranslations.tr('flexible_shift');

    try {
      final firstStart = windows.first.start;
      final lastEnd = windows.last.end;

      String formatTime(String tStr) {
        final parts = tStr.split(':').map(int.parse).toList();
        final h = parts[0];
        final m = parts[1];
        final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
        final ampm = h >= 12 ? 'PM' : 'AM';
        return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $ampm';
      }

      return '${formatTime(firstStart)} – ${formatTime(lastEnd)}';
    } catch (_) {
      return AppTranslations.tr('regular_shift_hours');
    }
  }

  String _formatLocalizedDate(DateTime dt) {
    if (LanguageService.instance.isMarathi) {
      final dayNames = ['सोमवार', 'मंगळवार', 'बुधवार', 'गुरुवार', 'शुक्रवार', 'शनिवार', 'रविवार'];
      final monthNames = ['जानेवारी', 'फेब्रुवारी', 'मार्च', 'एप्रिल', 'मे', 'जून', 'जुलै', 'ऑगस्ट', 'सप्टेंबर', 'ऑक्टोबर', 'नोव्हेंबर', 'डिसेंबर'];
      final dayName = dayNames[dt.weekday - 1];
      final monthName = monthNames[dt.month - 1];
      return '$dayName, ${dt.day} $monthName ${dt.year}';
    }
    return DateFormat('EEEE, d MMMM yyyy').format(dt);
  }

  /// Secret 7-tap gesture on the app title to toggle Developer Mode if user is authorized
  void _handleSecretTap() async {
    final now = DateTime.now();
    if (_lastSecretTap != null && now.difference(_lastSecretTap!) > const Duration(seconds: 2)) {
      _secretTapCount = 0;
    }
    _lastSecretTap = now;
    _secretTapCount++;

    if (_secretTapCount >= 7) {
      _secretTapCount = 0;
      final profile = await _authService.getUserProfile();
      final role = profile['role'] ?? 'USER';
      if (role == 'ADMIN' || role == 'DEVELOPER') {
        setState(() {
          _isDeveloperMode = !_isDeveloperMode;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isDeveloperMode ? 'Developer Mode Enabled (Admin)' : 'Developer Mode Disabled'),
            backgroundColor: _isDeveloperMode ? AppColors.secondary : AppColors.primary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _handleMarkAttendance(VerificationWindowItem activeWindow) async {
    if (!_serverTimeService.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance verification unavailable. Please check your connection and try again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final gf = _config?['geofence'];
    final locName = gf != null ? (gf['location_name'] ?? 'Assigned Location') : 'Assigned Location';
    final assignedLat = gf != null ? (gf['latitude'] as num).toDouble() : 0.0;
    final assignedLon = gf != null ? (gf['longitude'] as num).toDouble() : 0.0;
    final allowedRadius = gf != null ? (gf['radius_meters'] as num).toDouble() : 150.0;
    final userId = _config?['user_id'] ?? 0;

    setState(() => _isCheckingLocation = true);

    try {
      // 1. Acquire current GPS position
      var position = await LocationService.getCurrentPosition();
      setState(() => _isCheckingLocation = false);

      // If location is null (service off or permission denied), show Popup Dialog!
      if (position == null) {
        if (!mounted) return;
        final granted = await LocationPermissionDialog.show(context);
        if (granted) {
          setState(() => _isCheckingLocation = true);
          position = await LocationService.getCurrentPosition();
          setState(() => _isCheckingLocation = false);
        }
        if (position == null) {
          // User dismissed popup or decided not to enable location; clean return
          return;
        }
      }

      final validPosition = position;

      // 2. Launch Clean Face & Location Verification Screen
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyAttendanceScreen(
            currentLatitude: validPosition.latitude,
            currentLongitude: validPosition.longitude,
            gpsAccuracy: validPosition.accuracy,
            locationName: locName,
            assignedLatitude: assignedLat,
            assignedLongitude: assignedLon,
            allowedRadiusMeters: allowedRadius,
            userId: userId,
            activeVerificationNo: activeWindow.verificationNo,
            activeVerificationRuleId: activeWindow.id,
            activeWindowLabel: activeWindow.label,
            isDeveloperMode: _isDeveloperMode,
          ),
        ),
      ).then((_) {
        _loadConfig();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AppUpdateService.instance.checkForUpdates(context, showNoUpdateNotice: false);
        });
        _offlineService.loadPendingQueue();
      });
    } catch (e) {
      setState(() => _isCheckingLocation = false);
      if (!mounted) return;
      if (e is ApiException) {
        if (e.isUnauthorized) {
          ApiClient.onSessionExpired?.call();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.userFriendlyMessage),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      final errStr = e.toString().replaceFirst('Exception: ', '');
      if (errStr.contains('Permission')) {
        await LocationPermissionDialog.show(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errStr.isNotEmpty ? errStr : 'Unable to verify attendance. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _openAttendanceRequest(String? locName, [int? verificationNo]) {
    int? targetVNo = verificationNo;
    if (targetVNo == null) {
      final windows = _getWindowsWithLiveStatus();
      final serverNow = _serverTimeService.estimatedCurrentServerTime;
      for (final w in windows) {
        if (w.status == 'COMPLETED') continue;
        final sDt = _parseTimeToDateTime(serverNow, w.start);
        final eDt = _parseTimeToDateTime(serverNow, w.end);
        if (sDt != null && eDt != null && !serverNow.isBefore(sDt) && serverNow.isBefore(eDt)) {
          targetVNo = w.verificationNo;
          break;
        }
      }
      if (targetVNo == null) {
        final pending = windows.where((w) => w.status != 'COMPLETED').toList();
        if (pending.isNotEmpty) {
          targetVNo = pending.first.verificationNo;
        }
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SendAttendanceRequestScreen(
          initialLocationName: locName,
          verificationNo: targetVNo,
          reason: 'Attendance verification assistance / manual request',
        ),
      ),
    ).then((_) => _loadConfig());
  }

  void _handleLogout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }


  void _openTravelMap() {
    final userId = _config?['user_id'] ?? 0;
    final empCode = _config?['employee_id']?.toString();
    final empName = _config?['employee_name']?.toString() ?? _config?['name']?.toString();
    final tracking = TrackingService.instance;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeTravelMapScreen(
          initialEmployeeId: userId is int ? userId : int.tryParse(userId.toString()) ?? 0,
          initialEmployeeCode: empCode,
          initialEmployeeName: empName,
          initialSessionUuid: tracking.activeSessionUuid,
        ),
      ),
    );
  }

  Widget _buildTravelMapCard() {
    return ListenableBuilder(
      listenable: TrackingService.instance,
      builder: (context, _) {
        final tracking = TrackingService.instance;
        final isTracking = tracking.isTracking;
        final isPaused = tracking.isPaused;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withOpacity(0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.satellite_alt_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Travel Route & Satellite Map',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isTracking
                              ? (isPaused ? 'Tracking Paused' : 'Live Tracking Active')
                              : 'View Duty Route & Timeline',
                          style: TextStyle(
                            fontSize: 12,
                            color: isTracking
                                ? (isPaused ? const Color(0xFFD97706) : const Color(0xFF16A34A))
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isTracking)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPaused ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: isPaused ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isPaused ? 'PAUSED' : 'LIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isPaused ? const Color(0xFFB45309) : const Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'View your field travel route, GPS points, distance covered, and high-resolution Esri satellite imagery.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openTravelMap,
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: const Text(
                    '🛰️ Open Satellite Route Map',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E40AF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Employee-facing tracking UI removed per notification-only background tracking requirement
  Widget _buildTrackingStatusBanner() => const SizedBox.shrink();

  Widget _buildLegacyTrackingBanner() {
    return ListenableBuilder(
      listenable: TrackingService.instance,
      builder: (context, _) {
        final tracking = TrackingService.instance;
        final status = tracking.status;
        final isTracking = tracking.isTracking;
        final isPaused = tracking.isPaused;
        final userId = _config?['user_id'] ?? 0;
        final empId = _config?['employee_id']?.toString() ?? '';

        final travelMapEnabled = _config?['travel_map_enabled'] ?? true;
        if (!travelMapEnabled) {
          return const SizedBox.shrink();
        }

        if (!isTracking) {
          final hasError = status == TrackingStatus.error;
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hasError ? const Color(0xFFFEF2F2) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hasError ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hasError ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasError ? Icons.error_outline_rounded : Icons.navigation_outlined,
                    color: hasError ? AppColors.error : AppColors.textSecondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasError ? 'Tracking Error' : 'Duty GPS Tracking: Inactive',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: hasError ? AppColors.error : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasError
                            ? (tracking.gpsError ?? 'Location permissions or GPS unavailable')
                            : 'Record your travel route and calculate field distance',
                        style: TextStyle(
                          fontSize: 11,
                          color: hasError ? const Color(0xFF991B1B) : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                  label: Text(
                    hasError ? 'Retry' : 'Start',
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    await TrackingConsentDialog.showAndHandleConsent(
                      context,
                      userId: userId is int ? userId : int.tryParse(userId.toString()) ?? 0,
                      employeeId: empId,
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          );
        }

        final distKm = (tracking.totalDistanceMeters / 1000).toStringAsFixed(2);
        final accStr = tracking.currentAccuracy != null
            ? '±${tracking.currentAccuracy!.toStringAsFixed(1)}m'
            : '--';
        final lastSyncStr = tracking.lastSyncTime != null
            ? DateFormat('hh:mm a').format(tracking.lastSyncTime!.toLocal())
            : 'Pending';
        final lastFixStr = tracking.lastRecordedTime != null
            ? DateFormat('hh:mm a').format(tracking.lastRecordedTime!.toLocal())
            : '--';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isPaused ? const Color(0xFFFFFBEB) : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isPaused ? const Color(0xFFFDE68A) : const Color(0xFFBFDBFE)),
            boxShadow: [
              BoxShadow(
                color: (isPaused ? Colors.amber : Colors.blue).withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isPaused ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPaused ? 'Journey Tracking Paused' : 'Journey Tracking Active',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isPaused ? const Color(0xFF92400E) : const Color(0xFF1E40AF),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isPaused ? const Color(0xFFFCD34D) : const Color(0xFF93C5FD)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.route_rounded, size: 14, color: isPaused ? const Color(0xFFD97706) : const Color(0xFF2563EB)),
                        const SizedBox(width: 4),
                        Text(
                          '$distKm km',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isPaused ? const Color(0xFF78350F) : const Color(0xFF1E3A8A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Live Telemetry Row
              Row(
                children: [
                  const Icon(Icons.gps_fixed_rounded, size: 13, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text('GPS Acc: $accStr', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  const SizedBox(width: 12),
                  const Icon(Icons.access_time_rounded, size: 13, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text('Fix: $lastFixStr', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  const Spacer(),
                  const Icon(Icons.cloud_done_outlined, size: 13, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text('Sync: $lastSyncStr', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                ],
              ),
              const SizedBox(height: 12),
              // Action Buttons Row
              Row(
                children: [
                  // View My Route
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: const BorderSide(color: Color(0xFF3B82F6)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      icon: const Icon(Icons.map_rounded, size: 15, color: Color(0xFF1D4ED8)),
                      label: const Text('View Route', style: TextStyle(fontSize: 11, color: Color(0xFF1D4ED8), fontWeight: FontWeight.w600)),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EmployeeTravelMapScreen(
                              initialEmployeeId: userId is int ? userId : int.tryParse(userId.toString()) ?? 0,
                              initialSessionUuid: tracking.activeSessionUuid,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Pause / Resume Button
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: isPaused ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      icon: Icon(
                        isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        size: 15,
                        color: isPaused ? const Color(0xFF047857) : const Color(0xFFB45309),
                      ),
                      label: Text(
                        isPaused ? 'Resume' : 'Pause',
                        style: TextStyle(
                          fontSize: 11,
                          color: isPaused ? const Color(0xFF047857) : const Color(0xFFB45309),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () async {
                        if (isPaused) {
                          await tracking.resumeTracking();
                        } else {
                          await tracking.pauseTracking();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Stop Button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      icon: const Icon(Icons.stop_circle_outlined, size: 15, color: Colors.white),
                      label: const Text('Stop', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('End Shift & Stop Tracking?'),
                            content: const Text('This will complete your GPS journey recording for today.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Stop Tracking', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await tracking.stopTrackingForPunchOut();
                          if (mounted) setState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final windows = _getWindowsWithLiveStatus();
    final countdown = _evaluateCountdownState(windows);
    final serverNow = _serverTimeService.estimatedCurrentServerTime;

    // Greeting based on authoritative server time
    final hour = serverNow.hour;
    String greeting;
    if (hour < 12) {
      greeting = AppTranslations.tr('good_morning');
    } else if (hour < 17) {
      greeting = AppTranslations.tr('good_afternoon');
    } else {
      greeting = AppTranslations.tr('good_evening');
    }

    final empName = _config?['full_name'] ?? 'Employee';
    final formattedDate = _formatLocalizedDate(serverNow);

    final shiftName = _config?['shift']?['shift_name'] ?? AppTranslations.tr('general_shift');
    final shiftTiming = _getShiftTimingRange(windows);

    // Button states
    final isOpen = countdown['state'] == 'OPEN_NOW';
    final isCompleted = countdown['state'] == 'ALL_RECORDED';
    final isClosed = countdown['state'] == 'CLOSED';
    final isOnline = _serverTimeService.isOnline;

    String buttonLabel;
    String buttonSubtext;
    bool buttonEnabled;

    if (!isOnline) {
      buttonLabel = AppTranslations.tr('mark_attendance_btn');
      buttonSubtext = AppTranslations.tr('service_unavailable');
      buttonEnabled = false;
    } else if (isOpen) {
      buttonLabel = AppTranslations.tr('mark_attendance_btn');
      buttonSubtext = AppTranslations.tr('window_open_sub');
      buttonEnabled = true;
    } else if (isCompleted) {
      buttonLabel = AppTranslations.tr('attendance_recorded_btn');
      buttonSubtext = AppTranslations.tr('already_recorded_sub');
      buttonEnabled = false;
    } else if (isClosed) {
      buttonLabel = AppTranslations.tr('mark_attendance_btn');
      buttonSubtext = AppTranslations.tr('window_closed_sub');
      buttonEnabled = false;
    } else {
      // Countdown / not started yet
      buttonLabel = AppTranslations.tr('mark_attendance_btn');
      buttonSubtext = AppTranslations.tr('not_started_sub');
      buttonEnabled = false;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: GestureDetector(
          onTap: _handleSecretTap,
          child: Text(
            AppTranslations.tr('attendance_portal'),
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_rounded, color: AppColors.textPrimary),
            tooltip: 'Check for Updates',
            onPressed: () {
              AppUpdateService.instance.checkForUpdates(context, showNoUpdateNotice: true);
            },
          ),
          StreamBuilder<int>(
            stream: NotificationService.instance.unreadCountStream,
            initialData: 0,
            builder: (context, snapshot) {
              final unread = snapshot.data ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
                    tooltip: 'Notifications',
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
                      );
                      await NotificationService.instance.refreshUnreadCount();
                      if (mounted) setState(() {});
                    },
                  ),
                  if (unread > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.satellite_alt_rounded, color: Color(0xFF1E40AF)),
            tooltip: 'Satellite Travel Map',
            onPressed: _openTravelMap,
          ),
          const LanguageSelectorAction(),
          IconButton(
            icon: const Icon(Icons.history_rounded, color: AppColors.textPrimary),
            tooltip: AppTranslations.tr('attendance_history'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.textSecondary),
            tooltip: AppTranslations.tr('logout'),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: _isLoading && _config == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadConfig,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ResponsiveContainer(
                  maxWidth: 720,
                  padding: context.isSmallScreen
                      ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                      : const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Employee Header
                      _buildHeaderSection(greeting, empName, formattedDate),
                      const SizedBox(height: 16),

                      // 2. Prominent Attendance Countdown Notification Card
                      _buildCountdownNotificationCard(countdown),
                      const SizedBox(height: 16),

                      // 3. Today's Shift Card
                      _buildShiftCard(shiftName, shiftTiming),
                      const SizedBox(height: 16),

                      // 4. Assigned Work Location Card (No coordinates or meters)
                      _buildCleanLocationCard(),
                      const SizedBox(height: 16),

                      // 4b. Travel Route & Satellite Map Card
                      _buildTravelMapCard(),
                      const SizedBox(height: 20),

                      // 5. Main Attendance Action Button
                      _buildMainAttendanceButton(
                        label: buttonLabel,
                        subtext: buttonSubtext,
                        enabled: buttonEnabled,
                        isOpen: isOpen,
                        isCompleted: isCompleted,
                        activeWindow: countdown['active_window'] as VerificationWindowItem?,
                      ),
                      const SizedBox(height: 24),

                      // 6. Today's Schedule Card (Clean & Employee-Friendly)
                      if (windows.isNotEmpty) ...[
                        _buildScheduleCard(windows),
                        const SizedBox(height: 16),
                      ],

                      // 7. Secondary Option: Attendance Request
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            final gf = _config?['geofence'];
                            _openAttendanceRequest(gf != null ? gf['location_name'] : 'Work Site');
                          },
                          icon: const Icon(Icons.help_outline_rounded, size: 16, color: AppColors.textSecondary),
                          label: Text(
                            AppTranslations.tr('facing_issues'),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),

                      // 8. Developer Mode Panel (Only visible if Developer Mode is toggled by Admin)
                      if (_isDeveloperMode) ...[
                        const SizedBox(height: 20),
                        _buildDeveloperModePanel(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  /// Clean Header: "Good Morning, [Name]" and Current Date
  Widget _buildHeaderSection(String greeting, String empName, String formattedDate) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$greeting, $empName',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formattedDate,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Prominent Countdown Notification Card
  Widget _buildCountdownNotificationCard(Map<String, dynamic> countdown) {
    final title = countdown['title'] as String;
    final subtitle = countdown['subtitle'] as String;
    final icon = countdown['icon'] as IconData;
    final bgColor = countdown['bgColor'] as Color;
    final borderColor = countdown['borderColor'] as Color;
    final textColor = countdown['textColor'] as Color;
    final iconColor = countdown['iconColor'] as Color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: borderColor.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withOpacity(0.85),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Today's Shift Card (Shows Shift Name & Timing, NO internal IDs)
  Widget _buildShiftCard(String shiftName, String shiftTiming) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    AppTranslations.tr('todays_shift'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Text(
                  AppTranslations.tr('assigned'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            shiftName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            shiftTiming,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Assigned Work Location Card (No coordinates, radius, or distance)
  Widget _buildCleanLocationCard() {
    final gf = _config?['geofence'];
    final locName = gf != null ? (gf['location_name'] ?? AppTranslations.tr('assigned_work_site')) : AppTranslations.tr('assigned_work_site');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppTranslations.tr('work_location'),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  locName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded, size: 12, color: Color(0xFF059669)),
                const SizedBox(width: 4),
                Text(
                  AppTranslations.tr('verified'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Main Attendance Action Button
  Widget _buildMainAttendanceButton({
    required String label,
    required String subtext,
    required bool enabled,
    required bool isOpen,
    required bool isCompleted,
    VerificationWindowItem? activeWindow,
  }) {
    Color buttonBg;
    if (isCompleted) {
      buttonBg = const Color(0xFF059669);
    } else if (isOpen) {
      buttonBg = AppColors.primary;
    } else {
      buttonBg = const Color(0xFF94A3B8);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          icon: _isCheckingLocation
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Icon(
                  isCompleted ? Icons.check_circle_rounded : Icons.camera_front_rounded,
                  size: 22,
                ),
          label: Text(
            _isCheckingLocation ? AppTranslations.tr('verifying_location') : label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: buttonBg,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFCBD5E1),
            disabledForegroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: enabled ? 3 : 0,
          ),
          onPressed: (enabled && !_isCheckingLocation && activeWindow != null)
              ? () => _handleMarkAttendance(activeWindow)
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          subtext,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Clean Today's Schedule Card (Shows friendly status, no internal IDs)
  Widget _buildScheduleCard(List<VerificationWindowItem> windows) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppTranslations.tr('todays_schedule'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              Text(
                AppTranslations.tr('periods_count', args: {'count': '${windows.length}'}),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const Divider(height: 20),
          ...windows.map((w) => _buildScheduleRow(w)).toList(),
        ],
      ),
    );
  }

  Widget _buildScheduleRow(VerificationWindowItem item) {
    final isAvailable = item.status == 'AVAILABLE';
    final isCompleted = item.status == 'COMPLETED';

    Color bgColor = Colors.transparent;
    Color borderColor = const Color(0xFFE2E8F0);
    if (isAvailable) {
      bgColor = const Color(0xFFF0FDF4);
      borderColor = AppColors.success;
    } else if (isCompleted) {
      bgColor = const Color(0xFFF8FAFC);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isAvailable ? 1.5 : 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.periodName,
                  style: TextStyle(
                    fontWeight: isAvailable ? FontWeight.bold : FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isAvailable ? const Color(0xFF15803D) : AppColors.textSecondary,
                    fontWeight: isAvailable ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (item.punchTime != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Recorded at: ${item.punchTime}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          _buildStatusBadge(item.status),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color border;
    Color text;
    String displayLabel;

    switch (status) {
      case 'AVAILABLE':
        bg = const Color(0xFFDCFCE7);
        border = AppColors.success;
        text = const Color(0xFF166534);
        displayLabel = AppTranslations.tr('open_now');
        break;
      case 'COMPLETED':
        bg = const Color(0xFFDBEAFE);
        border = const Color(0xFF93C5FD);
        text = const Color(0xFF1E40AF);
        displayLabel = AppTranslations.tr('completed');
        break;
      case 'PENDING_SYNC':
        bg = const Color(0xFFFEF3C7);
        border = const Color(0xFFFDE68A);
        text = const Color(0xFF92400E);
        displayLabel = AppTranslations.tr('pending');
        break;
      case 'MISSED':
        bg = const Color(0xFFF1F5F9);
        border = const Color(0xFFE2E8F0);
        text = const Color(0xFF475569);
        displayLabel = AppTranslations.tr('closed');
        break;
      case 'UPCOMING':
      default:
        bg = const Color(0xFFF8FAFC);
        border = const Color(0xFFE2E8F0);
        text = const Color(0xFF64748B);
        displayLabel = AppTranslations.tr('upcoming');
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Text(
        displayLabel,
        style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  /// Developer / Test Mode Panel (Protected, only shown if authorized and active)
  Widget _buildDeveloperModePanel() {
    final gf = _config?['geofence'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DEVELOPER / TEST MODE',
                style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                onPressed: () => setState(() => _isDeveloperMode = false),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 6),
          Text(
            'Server Time: ${_serverTimeService.formattedDate} ${_serverTimeService.formattedTime}',
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11),
          ),
          Text(
            'Monotonic Synced: ${_serverTimeService.isSynchronized} (Offset: ${_serverTimeService.serverOffsetMs}ms)',
            style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 11),
          ),
          if (gf != null) ...[
            Text(
              'Assigned Lat: ${gf['latitude']}, Long: ${gf['longitude']}',
              style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 11),
            ),
            Text(
              'Geofence Radius: ${gf['radius_meters']}m',
              style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
