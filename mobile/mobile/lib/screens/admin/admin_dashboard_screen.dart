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
                  maxWidth: 820,
                  padding: context.isSmallScreen
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                      : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Stats Metrics Row (4-column on tablet, 2x2 on phones)
                      if (context.isTablet)
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
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.face_retouching_natural, size: 14),
                                      label: const Text('Face', style: TextStyle(fontSize: 11.5)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: const Size(64, 32),
                                      ),
                                      onPressed: () {
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
                                    ),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.pin_drop_outlined, size: 14),
                                      label: const Text('Geofence', style: TextStyle(fontSize: 11.5)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: const Size(78, 32),
                                      ),
                                      onPressed: () {
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
                                    ),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.schedule_rounded, size: 14),
                                      label: const Text('Shift', style: TextStyle(fontSize: 11.5)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: const Size(64, 32),
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => AssignShiftScreen(preselectedUserId: user.id),
                                          ),
                                        ).then((_) => _loadData());
                                      },
                                    ),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.route_rounded, size: 14, color: Color(0xFF2563EB)),
                                      label: const Text('Travel Map', style: TextStyle(fontSize: 11.5, color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: const Size(88, 32),
                                        side: const BorderSide(color: Color(0xFF93C5FD)),
                                        backgroundColor: const Color(0xFFEFF6FF),
                                      ),
                                      onPressed: () {
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
                                    ),
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
}
