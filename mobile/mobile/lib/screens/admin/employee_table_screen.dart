import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/responsive_util.dart';
import '../../models/user_model.dart';
import 'face_enrollment_screen.dart';
import 'geofence_config_screen.dart';
import 'assign_shift_screen.dart';
import 'register_employee_screen.dart';
import 'employee_travel_map_screen.dart';

class EmployeeTableScreen extends StatefulWidget {
  const EmployeeTableScreen({Key? key}) : super(key: key);

  @override
  State<EmployeeTableScreen> createState() => _EmployeeTableScreenState();
}

class _EmployeeTableScreenState extends State<EmployeeTableScreen> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();

  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  bool _isLoading = true;
  String? _errorMessage;
  final Set<String> _pendingToggles = {};

  // Filter States
  String _roleFilter = 'ALL';
  String _statusFilter = 'ALL';
  String _faceFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiClient.get(ApiConstants.adminUsers);
      if (res is List) {
        final users = res.map((u) => UserModel.fromJson(u as Map<String, dynamic>)).toList();
        if (mounted) {
          setState(() {
            _allUsers = users;
            _applyFilters();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredUsers = _allUsers.where((user) {
        // Search query filter (employee_id or full_name)
        final matchesSearch = query.isEmpty ||
            user.employeeId.toLowerCase().contains(query) ||
            user.fullName.toLowerCase().contains(query);

        // Role filter
        final matchesRole = _roleFilter == 'ALL' || user.role.toUpperCase() == _roleFilter;

        // Active status filter
        final matchesStatus = _statusFilter == 'ALL' ||
            (_statusFilter == 'ACTIVE' && user.isActive) ||
            (_statusFilter == 'INACTIVE' && !user.isActive);

        // Face enrollment filter
        final matchesFace = _faceFilter == 'ALL' ||
            (_faceFilter == 'ENROLLED' && user.hasFaceEnrolled) ||
            (_faceFilter == 'NOT_ENROLLED' && !user.hasFaceEnrolled);

        return matchesSearch && matchesRole && matchesStatus && matchesFace;
      }).toList();
    });
  }

  Future<void> _toggleUserActiveStatus(UserModel user) async {
    final newStatus = !user.isActive;
    final actionName = newStatus ? 'activate' : 'deactivate';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${newStatus ? "Activate" : "Deactivate"} Employee'),
        content: Text('Are you sure you want to $actionName ${user.fullName} (${user.employeeId})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus ? AppColors.success : AppColors.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(newStatus ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiClient.put(
        ApiConstants.adminUserDetail(user.id),
        body: {'is_active': newStatus},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Employee ${user.fullName} ${newStatus ? "activated" : "deactivated"} successfully.'),
          backgroundColor: newStatus ? AppColors.success : AppColors.secondary,
        ),
      );
      _loadEmployees();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: AppColors.error),
      );
    }
  }

  void _showEditEntityDialog(UserModel user) {
    final nameCtrl = TextEditingController(text: user.fullName);
    final passwordCtrl = TextEditingController();
    String selectedRole = user.role;
    bool isActive = user.isActive;
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Edit Employee (${user.employeeId})'),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 440,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Full Name *',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: selectedRole,
                          decoration: const InputDecoration(
                            labelText: 'Role',
                            prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'USER', child: Text('USER (Field Staff)')),
                            DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN')),
                            DropdownMenuItem(value: 'TIME_OFFICE', child: Text('TIME_OFFICE')),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedRole = val);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Reset Password (Optional)',
                            hintText: 'Leave blank to keep unchanged',
                            prefixIcon: Icon(Icons.lock_reset_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Account Active Status', style: TextStyle(fontSize: 14)),
                          subtitle: Text(isActive ? 'User can log in and submit punches' : 'User access is blocked'),
                          value: isActive,
                          activeColor: AppColors.primary,
                          onChanged: (val) => setDialogState(() => isActive = val),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  icon: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save Changes'),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);
                          try {
                            final Map<String, dynamic> updateBody = {
                              'full_name': nameCtrl.text.trim(),
                              'role': selectedRole,
                              'is_active': isActive,
                            };
                            if (passwordCtrl.text.trim().isNotEmpty) {
                              updateBody['password'] = passwordCtrl.text.trim();
                            }

                            await _apiClient.put(
                              ApiConstants.adminUserDetail(user.id),
                              body: updateBody,
                            );
                            if (mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Employee updated successfully.'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                              _loadEmployees();
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Update failed: ${e.toString()}'), backgroundColor: AppColors.error),
                            );
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;
    final isSmall = context.isSmallScreen;

    final activeCount = _allUsers.where((u) => u.isActive).length;
    final faceCount = _allUsers.where((u) => u.hasFaceEnrolled).length;
    final geofenceCount = _allUsers.where((u) => u.geofence != null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Master Table'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Employees',
            onPressed: _loadEmployees,
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: 'Register New Employee',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RegisterEmployeeScreen()),
              ).then((_) => _loadEmployees());
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: const Text('New Employee', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RegisterEmployeeScreen()),
          ).then((_) => _loadEmployees());
        },
      ),
      body: RefreshIndicator(
        onRefresh: _loadEmployees,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isSmall ? 12 : 20,
            vertical: 14,
          ),
          child: ResponsiveContainer(
            maxWidth: context.isDesktop ? 1600 : 1100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Summary Chips Bar
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _buildSummaryCard('Total Employees', '${_allUsers.length}', Icons.groups_rounded, AppColors.primary),
                    _buildSummaryCard('Active Staff', '$activeCount', Icons.check_circle_rounded, AppColors.success),
                    _buildSummaryCard('Face Enrolled', '$faceCount', Icons.face_rounded, const Color(0xFF8B5CF6)),
                    _buildSummaryCard('Geofenced', '$geofenceCount', Icons.location_on_rounded, AppColors.warning),
                  ],
                ),
                const SizedBox(height: 16),

                // Search & Filter Panel Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.filter_alt_outlined, color: AppColors.primary, size: 20),
                            const SizedBox(width: 8),
                            const Text('Search & Entity Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const Spacer(),
                            if (_searchController.text.isNotEmpty || _roleFilter != 'ALL' || _statusFilter != 'ALL' || _faceFilter != 'ALL')
                              TextButton.icon(
                                icon: const Icon(Icons.clear_all_rounded, size: 16),
                                label: const Text('Reset Filters', style: TextStyle(fontSize: 12)),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _roleFilter = 'ALL';
                                    _statusFilter = 'ALL';
                                    _faceFilter = 'ALL';
                                    _applyFilters();
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by Employee ID or Full Name...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () => _searchController.clear(),
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Dropdown Filters Row
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _buildFilterDropdown(
                              label: 'Role',
                              value: _roleFilter,
                              items: const {
                                'ALL': 'All Roles',
                                'USER': 'USER',
                                'ADMIN': 'ADMIN',
                                'TIME_OFFICE': 'TIME_OFFICE',
                              },
                              onChanged: (val) {
                                if (val != null) {
                                  _roleFilter = val;
                                  _applyFilters();
                                }
                              },
                            ),
                            _buildFilterDropdown(
                              label: 'Status',
                              value: _statusFilter,
                              items: const {
                                'ALL': 'All Statuses',
                                'ACTIVE': 'Active Only',
                                'INACTIVE': 'Inactive Only',
                              },
                              onChanged: (val) {
                                if (val != null) {
                                  _statusFilter = val;
                                  _applyFilters();
                                }
                              },
                            ),
                            _buildFilterDropdown(
                              label: 'Biometric Face',
                              value: _faceFilter,
                              items: const {
                                'ALL': 'All Faces',
                                'ENROLLED': 'Face Enrolled',
                                'NOT_ENROLLED': 'No Face Enrolled',
                              },
                              onChanged: (val) {
                                if (val != null) {
                                  _faceFilter = val;
                                  _applyFilters();
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Table Results Count Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${_filteredUsers.length} of ${_allUsers.length} Employees',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error))),
                        ElevatedButton(onPressed: _loadEmployees, child: const Text('Retry')),
                      ],
                    ),
                  )
                else if (_filteredUsers.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: Column(
                      children: const [
                        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No employees match the selected search & filters.', style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  )
                else if (isTablet)
                  _buildDataTable()
                else
                  _buildCardList(),

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
              Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          items: items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // Tablet / Desktop Data Table View
  Widget _buildDataTable() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 22,
          headingRowColor: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08)),
          columns: const [
            DataColumn(label: Text('Emp ID', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Face Biometric', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Geofence', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _filteredUsers.map((user) {
            return DataRow(
              cells: [
                DataCell(Text(user.employeeId, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(user.fullName)),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: user.role == 'ADMIN'
                          ? Colors.purple.shade50
                          : (user.role == 'TIME_OFFICE' ? Colors.orange.shade50 : Colors.blue.shade50),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: user.role == 'ADMIN'
                            ? Colors.purple.shade300
                            : (user.role == 'TIME_OFFICE' ? Colors.orange.shade300 : Colors.blue.shade300),
                      ),
                    ),
                    child: Text(
                      user.role,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: user.role == 'ADMIN'
                            ? Colors.purple.shade700
                            : (user.role == 'TIME_OFFICE' ? Colors.orange.shade800 : Colors.blue.shade800),
                      ),
                    ),
                  ),
                ),
                DataCell(
                  InkWell(
                    onTap: () => _toggleUserActiveStatus(user),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: user.isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        user.isActive ? 'ACTIVE' : 'INACTIVE',
                        style: TextStyle(
                          color: user.isActive ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        user.hasFaceEnrolled ? Icons.check_circle_rounded : Icons.cancel_outlined,
                        size: 16,
                        color: user.hasFaceEnrolled ? AppColors.success : AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        user.hasFaceEnrolled ? 'Enrolled' : 'Not Enrolled',
                        style: TextStyle(
                          fontSize: 12,
                          color: user.hasFaceEnrolled ? AppColors.success : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    user.geofence != null ? (user.geofence!['location_name'] ?? 'Assigned') : 'None',
                    style: TextStyle(
                      fontSize: 12,
                      color: user.geofence != null ? AppColors.primaryLight : Colors.grey,
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                        tooltip: 'Edit Employee Entity',
                        onPressed: () => _showEditEntityDialog(user),
                      ),
                      IconButton(
                        icon: const Icon(Icons.face_retouching_natural_rounded, size: 18, color: Color(0xFF8B5CF6)),
                        tooltip: 'Enroll Face',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => FaceEnrollmentScreen(
                                userId: user.id,
                                employeeId: user.employeeId,
                                fullName: user.fullName,
                              ),
                            ),
                          ).then((_) => _loadEmployees());
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.location_on_outlined, size: 18, color: AppColors.warning),
                        tooltip: 'Configure Geofence',
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
                          ).then((_) => _loadEmployees());
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.schedule_rounded, size: 18, color: AppColors.success),
                        tooltip: 'Assign Shift',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AssignShiftScreen(preselectedUserId: user.id),
                            ),
                          ).then((_) => _loadEmployees());
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.route_rounded, size: 18, color: Color(0xFF2563EB)),
                        tooltip: 'Employee Travel Map',
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
                      IconButton(
                        icon: Icon(
                          user.isDeviceRegistered ? Icons.phone_android_rounded : Icons.phonelink_setup_rounded,
                          size: 18,
                          color: user.isDeviceRegistered ? const Color(0xFF059669) : const Color(0xFF64748B),
                        ),
                        tooltip: user.isDeviceRegistered ? 'Device Bound (${user.deviceId})' : 'Register Device ID',
                        onPressed: () => _showDeviceRegistrationModal(user),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // Mobile Phones Card List View
  Widget _buildCardList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredUsers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final user = _filteredUsers[i];
        return Card(
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ID: ${user.employeeId}  •  Role: ${user.role}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        InkWell(
                          onTap: () => _toggleUserActiveStatus(user),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: user.isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              user.isActive ? 'ACTIVE' : 'INACTIVE',
                              style: TextStyle(
                                color: user.isActive ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                          onPressed: () => _showEditEntityDialog(user),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      avatar: Icon(
                        user.hasFaceEnrolled ? Icons.check_circle : Icons.warning_amber_rounded,
                        size: 15,
                        color: user.hasFaceEnrolled ? AppColors.success : AppColors.warning,
                      ),
                      label: Text(
                        user.hasFaceEnrolled ? 'Face Enrolled' : 'No Face',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    Chip(
                      avatar: Icon(
                        user.geofence != null ? Icons.location_on : Icons.location_off,
                        size: 15,
                        color: user.geofence != null ? AppColors.primaryLight : AppColors.error,
                      ),
                      label: Text(
                        user.geofence != null ? (user.geofence!['location_name'] ?? 'Location') : 'No Location',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                        ).then((_) => _loadEmployees());
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
                        ).then((_) => _loadEmployees());
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
                        ).then((_) => _loadEmployees());
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
      _allUsers = _allUsers.map((u) {
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
      _applyFilters();
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
                                          _allUsers = _allUsers.map((u) {
                                            if (u.id != user.id) return u;
                                            return u.copyWith(deviceId: null, isDeviceRegistered: false);
                                          }).toList();
                                          _applyFilters();
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
                                          _allUsers = _allUsers.map((u) {
                                            if (u.id != user.id) return u;
                                            return u.copyWith(deviceId: devId, isDeviceRegistered: true);
                                          }).toList();
                                          _applyFilters();
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
