import 'package:flutter/services.dart';
import '../common/notification_center_screen.dart';
import 'employee_travel_map_screen.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/auth_service.dart';
import '../../core/localization/app_translations.dart';
import '../../widgets/language_selector.dart';
import '../../models/user_model.dart';
import '../auth/login_screen.dart';
import 'register_employee_screen.dart';
import 'face_enrollment_screen.dart';
import 'geofence_config_screen.dart';
import 'attendance_report_screen.dart';
import 'shift_management_screen.dart';
import 'assign_shift_screen.dart';
import 'global_settings_dialog.dart';
import 'attendance_requests_screen.dart';
import 'admin_face_registration_screen.dart';
import '../../core/utils/responsive_util.dart';

import '../../core/services/app_update_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _apiClient = ApiClient();
  final _authService = AuthService();

  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _biometricSettings;
  List<UserModel> _users = [];
  final Set<String> _pendingToggles = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.instance.checkForUpdates(context, showNoUpdateNotice: false);
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final statsRes = await _apiClient.get(ApiConstants.dashboardStats);
      final usersRes = await _apiClient.get(ApiConstants.adminUsers);
      Map<String, dynamic>? bioRes;
      try {
        bioRes = await _apiClient.get(ApiConstants.adminBiometricSettings);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _stats = statsRes;
          _users = (usersRes as List).map((u) => UserModel.fromJson(u)).toList();
          _biometricSettings = bioRes;
        });
      }
    } catch (e) {
      debugPrint('Admin dashboard data load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLogout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTranslations.tr('admin_dashboard')),
        actions: [
          IconButton(
            icon: const Icon(Icons.face_retouching_natural_rounded),
            tooltip: 'Employee Face Registration Portal',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminFaceRegistrationScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.map_rounded),
            tooltip: 'Employee Travel Route Map',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmployeeTravelMapScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
              );
            },
          ),
          const LanguageSelectorAction(isDark: true),
          IconButton(
            icon: Badge(
              isLabelVisible: (_stats?['pending_attendance_requests'] ?? 0) > 0,
              label: Text('${_stats?['pending_attendance_requests'] ?? 0}'),
              child: const Icon(Icons.mark_email_unread_rounded),
            ),
            tooltip: AppTranslations.tr('attendance_requests'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AttendanceRequestsScreen()),
              ).then((_) => _loadData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: AppTranslations.tr('global_settings'),
            onPressed: () async {
              await GlobalSettingsDialog.show(context);
              if (mounted) _loadData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.assessment_rounded),
            tooltip: AppTranslations.tr('attendance_reports'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AttendanceReportScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: AppTranslations.tr('logout'),
            onPressed: _handleLogout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: const Text('Register Employee', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RegisterEmployeeScreen()),
          ).then((_) => _loadData());
        },
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ResponsiveContainer(
                  maxWidth: context.isDesktop ? 1440 : (context.isTablet ? 960 : double.infinity),
                  padding: context.isSmallScreen
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                      : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Stats Metrics Row (4-column on desktop/tablet, 2x2 on phones)
                      if (context.isTablet || context.isDesktop)
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: "Employees",
                                value: '${_stats?['total_employees'] ?? 0}',
                                icon: Icons.people_alt_rounded,
                                color: AppColors.primaryLight,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: "Present Today",
                                value: '${_stats?['today_present'] ?? 0}',
                                icon: Icons.check_circle_rounded,
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: "Failed Attempts",
                                value: '${_stats?['today_failed_attempts'] ?? 0}',
                                icon: Icons.error_rounded,
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: "Enrolled Faces",
                                value: '${_stats?['enrolled_faces_count'] ?? 0}',
                                icon: Icons.face_rounded,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: "Employees",
                                value: '${_stats?['total_employees'] ?? 0}',
                                icon: Icons.people_alt_rounded,
                                color: AppColors.primaryLight,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: "Present Today",
                                value: '${_stats?['today_present'] ?? 0}',
                                icon: Icons.check_circle_rounded,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: "Failed Attempts",
                                value: '${_stats?['today_failed_attempts'] ?? 0}',
                                icon: Icons.error_rounded,
                                color: AppColors.error,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: "Enrolled Faces",
                                value: '${_stats?['enrolled_faces_count'] ?? 0}',
                                icon: Icons.face_rounded,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                    // Pending Attendance Requests Banner Card
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AttendanceRequestsScreen()),
                        ).then((_) => _loadData());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: (_stats?['pending_attendance_requests'] ?? 0) > 0
                              ? const Color(0xFFFFFBEB)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: (_stats?['pending_attendance_requests'] ?? 0) > 0
                                ? const Color(0xFFF59E0B)
                                : AppColors.primaryLight.withOpacity(0.3),
                            width: (_stats?['pending_attendance_requests'] ?? 0) > 0 ? 1.5 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: (_stats?['pending_attendance_requests'] ?? 0) > 0
                                    ? const Color(0xFFFEF3C7)
                                    : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.mark_email_unread_rounded,
                                color: (_stats?['pending_attendance_requests'] ?? 0) > 0
                                    ? const Color(0xFFD97706)
                                    : AppColors.primary,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Attendance Requests Queue',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                                      ),
                                      const SizedBox(width: 8),
                                      if ((_stats?['pending_attendance_requests'] ?? 0) > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '${_stats?['pending_attendance_requests']} PENDING',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Review live selfies, GPS coords, & approve/reject',
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textSecondary, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Shift Management Banner Card
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ShiftManagementScreen()),
                        ).then((_) => _loadData());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, Color(0xFF2563EB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.access_time_filled_rounded, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Shift Master & Rule Engine',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Configure 30+ unlimited shifts & second-precision dynamic rules',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Global Biometric Threshold Card
                    InkWell(
                      onTap: () async {
                        await GlobalSettingsDialog.show(context);
                        if (mounted) _loadData();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primaryLight.withOpacity(0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
                              ),
                              child: const Icon(Icons.tune_rounded, color: AppColors.success, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Biometric Threshold',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${(((_biometricSettings?['similarity_threshold'] as num?)?.toDouble() ?? 0.65) * 100).toInt()}% Match',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Global Cosine Similarity: ${((_biometricSettings?['similarity_threshold'] as num?)?.toDouble() ?? 0.65).toStringAsFixed(2)} • Tap to edit',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.edit_rounded, color: AppColors.primary, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Employees List Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Staff Directory',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        Text(
                          '${_users.length} total',
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // User Cards List
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final user = _users[i];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user.fullName,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'ID: ${user.employeeId} (${user.role})',
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: user.isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        user.isActive ? 'ACTIVE' : 'INACTIVE',
                                        style: TextStyle(
                                          color: user.isActive ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),

                                // Status Badges (Face, Geofence, Time Window)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    Chip(
                                      avatar: Icon(
                                        user.hasFaceEnrolled ? Icons.check_circle : Icons.warning_amber_rounded,
                                        size: 16,
                                        color: user.hasFaceEnrolled ? AppColors.success : AppColors.warning,
                                      ),
                                      label: Text(
                                        user.hasFaceEnrolled ? 'Face Enrolled' : 'No Face',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    Chip(
                                      avatar: Icon(
                                        user.geofence != null ? Icons.location_on : Icons.location_off,
                                        size: 16,
                                        color: user.geofence != null ? AppColors.primaryLight : AppColors.error,
                                      ),
                                      label: Text(
                                        user.geofence != null ? user.geofence!['location_name'] : 'No Location',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Admin Action Buttons (Responsive Wrap)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _buildFeaturePill(
                                      label: 'Face',
                                      icon: Icons.face_retouching_natural,
                                      enabled: user.faceEnabled,
                                      isLoading: _pendingToggles.contains('${user.id}_face'),
                                      onTapConfigure: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => FaceEnrollmentScreen(
                                              userId: user.id,
                                              employeeId: user.employeeId,
                                              fullName: user.fullName,
                                            ),
                                          ),
                                        ).then((_) => _loadData());
                                      },
                                      onToggle: () => _handleFeatureToggle(user, 'face', user.faceEnabled),
                                    ),
                                    _buildFeaturePill(
                                      label: 'Geofence',
                                      icon: Icons.pin_drop_outlined,
                                      enabled: user.geofenceEnabled,
                                      isLoading: _pendingToggles.contains('${user.id}_geofence'),
                                      onTapConfigure: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => GeofenceConfigScreen(
                                              userId: user.id,
                                              employeeId: user.employeeId,
                                              fullName: user.fullName,
                                              initialGeofence: user.geofence,
                                            ),
                                          ),
                                        ).then((_) => _loadData());
                                      },
                                      onToggle: () => _handleFeatureToggle(user, 'geofence', user.geofenceEnabled),
                                    ),
                                    _buildFeaturePill(
                                      label: 'Shift',
                                      icon: Icons.schedule_rounded,
                                      enabled: user.shiftEnabled,
                                      isLoading: _pendingToggles.contains('${user.id}_shift'),
                                      onTapConfigure: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => AssignShiftScreen(preselectedUserId: user.id),
                                          ),
                                        ).then((_) => _loadData());
                                      },
                                      onToggle: () => _handleFeatureToggle(user, 'shift', user.shiftEnabled),
                                    ),
                                    _buildFeaturePill(
                                      label: 'Travel Map',
                                      icon: Icons.route_rounded,
                                      enabled: user.travelMapEnabled,
                                      isLoading: _pendingToggles.contains('${user.id}_travel_map'),
                                      activeColor: const Color(0xFF1D4ED8),
                                      activeBgColor: const Color(0xFFEFF6FF),
                                      activeBorderColor: const Color(0xFF93C5FD),
                                      onTapConfigure: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => EmployeeTravelMapScreen(
                                              initialEmployeeId: user.id,
                                              initialEmployeeCode: user.employeeId,
                                              initialEmployeeName: user.fullName,
                                            ),
                                          ),
                                        );
                                      },
                                      onToggle: () => _handleFeatureToggle(user, 'travel_map', user.travelMapEnabled),
                                    ),
                                    _buildDeviceButton(user),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturePill({
    required String label,
    required IconData icon,
    required bool enabled,
    required bool isLoading,
    required VoidCallback onTapConfigure,
    required VoidCallback onToggle,
    Color activeColor = const Color(0xFF2563EB),
    Color activeBgColor = const Color(0xFFEFF6FF),
    Color activeBorderColor = const Color(0xFF93C5FD),
  }) {
    final effectiveBorderColor = enabled ? activeBorderColor : const Color(0xFFCBD5E1);
    final effectiveBgColor = enabled ? activeBgColor : const Color(0xFFF8FAFC);
    final effectiveTextColor = enabled ? activeColor : const Color(0xFF64748B);
    final effectiveIconColor = enabled ? activeColor : const Color(0xFF94A3B8);

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: effectiveBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: effectiveBorderColor, width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTapConfigure,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 13, color: effectiveIconColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: effectiveTextColor,
                  ),
                ),
                const SizedBox(width: 5),
                // Independent ON/OFF Toggle Switch
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: isLoading
                        ? SizedBox(
                            width: 26,
                            height: 15,
                            child: Center(
                              child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: activeColor,
                                ),
                              ),
                            ),
                          )
                        : AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 26,
                            height: 15,
                            padding: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: enabled ? activeColor : const Color(0xFFCBD5E1),
                            ),
                            child: Align(
                              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceButton(UserModel user) {
    final isRegistered = user.isDeviceRegistered;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: isRegistered ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRegistered ? const Color(0xFF6EE7B7) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDeviceRegistrationModal(user),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRegistered ? Icons.phone_android_rounded : Icons.phonelink_setup_rounded,
                  size: 14,
                  color: isRegistered ? const Color(0xFF059669) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
                Text(
                  'Device',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isRegistered ? const Color(0xFF059669) : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRegistered ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleFeatureToggle(UserModel user, String feature, bool currentVal) async {
    final key = '${user.id}_$feature';
    if (_pendingToggles.contains(key)) return;

    final newVal = !currentVal;
    setState(() {
      _pendingToggles.add(key);
      _updateUserFeatureLocal(user.id, feature, newVal);
    });

    try {
      await _apiClient.post(
        ApiConstants.adminUserFeatureToggle(user.id),
        body: {
          'feature': feature,
          'enabled': newVal,
        },
      );

      final displayName = _featureDisplayName(feature);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$displayName ${newVal ? "enabled" : "disabled"} for ${user.fullName}'),
            backgroundColor: newVal ? const Color(0xFF10B981) : const Color(0xFF64748B),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _updateUserFeatureLocal(user.id, feature, currentVal);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update $feature: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingToggles.remove(key);
        });
      }
    }
  }

  void _updateUserFeatureLocal(int userId, String feature, bool val) {
    setState(() {
      _users = _users.map((u) {
        if (u.id != userId) return u;
        switch (feature) {
          case 'face':
            return u.copyWith(faceEnabled: val);
          case 'geofence':
            return u.copyWith(geofenceEnabled: val);
          case 'shift':
            return u.copyWith(shiftEnabled: val);
          case 'travel_map':
            return u.copyWith(travelMapEnabled: val);
          default:
            return u;
        }
      }).toList();
    });
  }

  String _featureDisplayName(String feature) {
    switch (feature) {
      case 'face': return 'Face Attendance';
      case 'geofence': return 'Geofence Verification';
      case 'shift': return 'Shift Schedule';
      case 'travel_map': return 'Travel Map Tracking';
      default: return feature;
    }
  }

  void _showDeviceRegistrationModal(UserModel user) {
    final controller = TextEditingController(text: user.deviceId ?? '');
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final hasDevice = user.isDeviceRegistered && user.deviceId != null && user.deviceId!.isNotEmpty;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.phonelink_lock_rounded, color: Color(0xFF2563EB), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Device ID Registration',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${user.fullName} (${user.employeeId})',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hasDevice ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasDevice ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasDevice ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                            color: hasDevice ? const Color(0xFF059669) : const Color(0xFFD97706),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasDevice ? 'Registered Device Bound' : 'No Device Registered',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: hasDevice ? const Color(0xFF065F46) : const Color(0xFF92400E),
                                  ),
                                ),
                                if (hasDevice) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    user.deviceId!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Color(0xFF047857),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ] else ...[
                                  const SizedBox(height: 2),
                                  const Text(
                                    'This employee can currently log in from any mobile device.',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF78350F)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (hasDevice)
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF059669)),
                              tooltip: 'Copy Device ID',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: user.deviceId!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Device ID copied to clipboard'),
                                    duration: Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: 'Device ID (UUID)',
                        hintText: 'e.g. 550e8400-e29b-41d4-a716-446655440000',
                        prefixIcon: const Icon(Icons.smartphone_rounded),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.content_paste_rounded, size: 18),
                          tooltip: 'Paste from clipboard',
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null && data!.text!.isNotEmpty) {
                              setModalState(() {
                                controller.text = data.text!.trim();
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (hasDevice) ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            icon: const Icon(Icons.phonelink_erase_rounded, size: 16),
                            label: const Text('Remove', style: TextStyle(fontSize: 12)),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: ctx,
                                      builder: (alertCtx) => AlertDialog(
                                        title: const Text('Remove Device Binding?'),
                                        content: Text(
                                          'Are you sure you want to remove device binding for ${user.fullName} (${user.employeeId})?\n\nThey will be able to log in from any device until a new device is bound.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(alertCtx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                                            onPressed: () => Navigator.pop(alertCtx, true),
                                            child: const Text('Remove Binding'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm != true) return;

                                    setModalState(() => isSubmitting = true);
                                    try {
                                      await _apiClient.delete(ApiConstants.adminUserDevice(user.id));
                                      if (mounted) {
                                        setState(() {
                                          _users = _users.map((u) {
                                            if (u.id != user.id) return u;
                                            return u.copyWith(deviceId: null, isDeviceRegistered: false);
                                          }).toList();
                                        });
                                        Navigator.pop(dialogCtx);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Device registration removed for ${user.fullName}'),
                                            backgroundColor: const Color(0xFF10B981),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setModalState(() => isSubmitting = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}'),
                                            backgroundColor: AppColors.error,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    }
                                  },
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_rounded, size: 16),
                            label: Text(
                              isSubmitting
                                  ? 'Saving...'
                                  : (hasDevice ? 'Update Device' : 'Register Device'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final devId = controller.text.trim();
                                    if (devId.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please enter or paste a valid Device ID'),
                                          backgroundColor: AppColors.warning,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }

                                    setModalState(() => isSubmitting = true);
                                    try {
                                      await _apiClient.post(
                                        ApiConstants.adminUserDevice(user.id),
                                        body: {'device_id': devId},
                                      );
                                      if (mounted) {
                                        setState(() {
                                          _users = _users.map((u) {
                                            if (u.id != user.id) return u;
                                            return u.copyWith(deviceId: devId, isDeviceRegistered: true);
                                          }).toList();
                                        });
                                        Navigator.pop(dialogCtx);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Device registered successfully for ${user.fullName}'),
                                            backgroundColor: const Color(0xFF10B981),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setModalState(() => isSubmitting = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Error: ${e.toString().replaceFirst("Exception: ", "")}'),
                                            backgroundColor: AppColors.error,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

