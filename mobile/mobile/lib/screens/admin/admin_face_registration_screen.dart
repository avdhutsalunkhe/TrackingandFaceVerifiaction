import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/auth_service.dart';
import '../../core/localization/app_translations.dart';
import '../../widgets/language_selector.dart';
import '../../models/user_model.dart';
import '../auth/login_screen.dart';
import 'face_enrollment_screen.dart';

enum FaceFilter { all, pending, enrolled }

class AdminFaceRegistrationScreen extends StatefulWidget {
  const AdminFaceRegistrationScreen({Key? key}) : super(key: key);

  @override
  State<AdminFaceRegistrationScreen> createState() => _AdminFaceRegistrationScreenState();
}

class _AdminFaceRegistrationScreenState extends State<AdminFaceRegistrationScreen> {
  final ApiClient _apiClient = ApiClient();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _adminName = 'Administrator';
  String _adminEmpId = 'admin';
  List<UserModel> _users = [];
  String _searchQuery = '';
  FaceFilter _selectedFilter = FaceFilter.all;

  @override
  void initState() {
    super.initState();
    _loadAdminProfile();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _adminName = prefs.getString('full_name') ?? 'Administrator';
        _adminEmpId = prefs.getString('employee_id') ?? 'admin';
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final usersRes = await _apiClient.get(ApiConstants.adminUsers);
      if (mounted) {
        setState(() {
          // Filter to standard USER employees who need face registration
          _users = (usersRes as List)
              .map((u) => UserModel.fromJson(u))
              .where((u) => u.role != 'ADMIN' && u.role != 'TIME_OFFICE')
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load employees: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out of the Face Registration portal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTranslations.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(AppTranslations.tr('logout')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _startFaceEnrollment(UserModel user) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FaceEnrollmentScreen(
          userId: user.id,
          employeeId: user.employeeId,
          fullName: user.fullName,
        ),
      ),
    );

    // Refresh user list upon return so biometric status updates immediately
    _loadData();

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Face template successfully registered for ${user.fullName}!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  List<UserModel> get _filteredUsers {
    return _users.where((user) {
      // Status filter
      if (_selectedFilter == FaceFilter.pending && user.hasFaceEnrolled) {
        return false;
      }
      if (_selectedFilter == FaceFilter.enrolled && !user.hasFaceEnrolled) {
        return false;
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final matchesName = user.fullName.toLowerCase().contains(_searchQuery);
        final matchesId = user.employeeId.toLowerCase().contains(_searchQuery);
        final matchesDept = (user.department ?? '').toLowerCase().contains(_searchQuery);
        final matchesDesig = (user.designation ?? '').toLowerCase().contains(_searchQuery);
        if (!matchesName && !matchesId && !matchesDept && !matchesDesig) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final totalEmployees = _users.length;
    final enrolledCount = _users.where((u) => u.hasFaceEnrolled).length;
    final pendingCount = totalEmployees - enrolledCount;
    final filtered = _filteredUsers;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.primary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Face Registration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              'Admin: $_adminName ($_adminEmpId)',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          const LanguageSelectorAction(isDark: true),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Policy Notice Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFE0E7FF),
                border: Border(bottom: BorderSide(color: Color(0xFFC7D2FE))),
              ),
              child: Row(
                children: const [
                  Icon(Icons.shield_outlined, size: 16, color: Color(0xFF3730A3)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mobile Admin Portal — Authorized for Employee Biometric Face Registration only.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF3730A3), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

            // Metrics Summary Cards
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _buildMetricCard(
                    title: 'Total Staff',
                    count: totalEmployees,
                    color: const Color(0xFF1E293B),
                    icon: Icons.people_alt_outlined,
                  ),
                  const SizedBox(width: 8),
                  _buildMetricCard(
                    title: 'Face Enrolled',
                    count: enrolledCount,
                    color: const Color(0xFF059669),
                    icon: Icons.check_circle_outline,
                  ),
                  const SizedBox(width: 8),
                  _buildMetricCard(
                    title: 'Pending',
                    count: pendingCount,
                    color: const Color(0xFFD97706),
                    icon: Icons.pending_actions_outlined,
                  ),
                ],
              ),
            ),

            // Live Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search employee by name, ID or department...',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),

            // Filter Tabs (Chips)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  _buildFilterChip('All ($totalEmployees)', FaceFilter.all),
                  const SizedBox(width: 6),
                  _buildFilterChip('Pending ($pendingCount)', FaceFilter.pending),
                  const SizedBox(width: 6),
                  _buildFilterChip('Enrolled ($enrolledCount)', FaceFilter.enrolled),
                ],
              ),
            ),

            // Employee Cards List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              return _buildEmployeeCard(filtered[index]);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '$count',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, FaceFilter filter) {
    final isSelected = _selectedFilter == filter;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = filter),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFCBD5E1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(UserModel user) {
    final hasFace = user.hasFaceEnrolled;
    final initials = user.fullName.isNotEmpty
        ? user.fullName.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join('').toUpperCase()
        : 'EM';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasFace ? const Color(0xFFE2E8F0) : const Color(0xFFFED7AA),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // User Avatar with Initials
            CircleAvatar(
              radius: 22,
              backgroundColor: hasFace ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: hasFace ? const Color(0xFF166534) : const Color(0xFFB45309),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Employee Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'ID: ${user.employeeId}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                        ),
                      ),
                      if (user.department != null && user.department!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            user.department!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Biometric Status Tag
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: hasFace ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasFace ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                              size: 13,
                              color: hasFace ? const Color(0xFF15803D) : const Color(0xFFB45309),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              hasFace ? 'Face Enrolled' : 'Pending Enrollment',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: hasFace ? const Color(0xFF15803D) : const Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Register / Re-enroll Action Button
            ElevatedButton(
              onPressed: () => _startFaceEnrollment(user),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasFace ? const Color(0xFFF8FAFC) : AppColors.primary,
                foregroundColor: hasFace ? AppColors.primary : Colors.white,
                elevation: hasFace ? 0 : 2,
                side: hasFace ? const BorderSide(color: AppColors.primary, width: 1.2) : BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasFace ? Icons.refresh_rounded : Icons.camera_alt_outlined,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hasFace ? 'Update' : 'Enroll',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.face_retouching_off, size: 48, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
            const Text(
              'No employees match your filter',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try clearing search keywords or switching filter tabs.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            if (_searchQuery.isNotEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _searchController.clear(),
                child: const Text('Clear Search'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
