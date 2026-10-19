import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/responsive_util.dart';
import '../../models/user_model.dart';
import '../../models/shift_model.dart';

class AssignShiftScreen extends StatefulWidget {
  final int? preselectedUserId;

  const AssignShiftScreen({Key? key, this.preselectedUserId}) : super(key: key);

  @override
  State<AssignShiftScreen> createState() => _AssignShiftScreenState();
}

class _AssignShiftScreenState extends State<AssignShiftScreen> {
  final ApiClient _apiClient = ApiClient();
  bool _isLoading = true;
  bool _isSubmitting = false;

  List<UserModel> _employees = [];
  List<ShiftModel> _shifts = [];
  List<EmployeeShiftAssignmentModel> _history = [];

  UserModel? _selectedUser;
  ShiftModel? _selectedShift;
  DateTime _effectiveFrom = DateTime.now();
  DateTime? _effectiveTo;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final usersRes = await _apiClient.get(ApiConstants.adminUsers);
      final shiftsRes = await _apiClient.get(ApiConstants.adminShifts);

      if (usersRes is List && shiftsRes is List) {
        setState(() {
          _employees = usersRes.map((u) => UserModel.fromJson(u as Map<String, dynamic>)).toList();
          _shifts = shiftsRes.map((s) => ShiftModel.fromJson(s as Map<String, dynamic>)).where((s) => s.isActive).toList();

          if (_employees.isNotEmpty) {
            _selectedUser = _employees.firstWhere(
              (u) => u.id == widget.preselectedUserId,
              orElse: () => _employees.first,
            );
          }
          if (_shifts.isNotEmpty) {
            _selectedShift = _shifts.first;
          }
          _isLoading = false;
        });

        if (_selectedUser != null) {
          _loadUserHistory(_selectedUser!.id);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _loadUserHistory(int userId) async {
    try {
      final res = await _apiClient.get(ApiConstants.adminUserShiftHistory(userId));
      if (res is List) {
        setState(() {
          _history = res.map((h) => EmployeeShiftAssignmentModel.fromJson(h as Map<String, dynamic>)).toList();
        });
      }
    } catch (e) {
      // Ignored
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final initialDate = isFrom ? _effectiveFrom : (_effectiveTo ?? _effectiveFrom.add(const Duration(days: 30)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _effectiveFrom = picked;
        } else {
          _effectiveTo = picked;
        }
      });
    }
  }

  Future<void> _assignShift() async {
    if (_selectedUser == null || _selectedShift == null) return;

    setState(() => _isSubmitting = true);
    try {
      final payload = {
        'user_id': _selectedUser!.id,
        'shift_id': _selectedShift!.id,
        'effective_from': DateFormat('yyyy-MM-dd').format(_effectiveFrom),
        'effective_to': _effectiveTo != null ? DateFormat('yyyy-MM-dd').format(_effectiveTo!) : null,
      };

      await _apiClient.post(ApiConstants.adminShiftAssign, data: payload);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shift ${_selectedShift!.shiftCode} assigned to ${_selectedUser!.fullName}!'),
          backgroundColor: AppColors.success,
        ),
      );

      _loadUserHistory(_selectedUser!.id);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to assign shift: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _removeShiftAssignment(EmployeeShiftAssignmentModel assignment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Remove Shift Assignment'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove this shift assignment (${assignment.shiftCode ?? ""} - ${assignment.shiftName ?? ""}) for ${_selectedUser?.fullName ?? "this employee"}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _apiClient.delete(ApiConstants.adminDeleteShiftAssignment(assignment.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift assignment removed successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
      if (_selectedUser != null) {
        _loadUserHistory(_selectedUser!.id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove shift assignment: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign Employee Shift'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: context.isDesktop ? 1200 : (context.isTablet ? 900 : double.infinity),
              padding: EdgeInsets.zero,
              child: ListView(
                padding: ResponsiveUtil.screenPadding(context),
                children: [
                  Card(
                    child: Padding(
                      padding: ResponsiveUtil.cardPadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Shift Assignment Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),

                          // Select Employee Dropdown
                          DropdownButtonFormField<UserModel>(
                            isExpanded: true,
                            value: _selectedUser,
                            decoration: const InputDecoration(
                              labelText: 'Select Employee *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            items: _employees.map((u) {
                              return DropdownMenuItem(
                                value: u,
                                child: Text('${u.fullName} (${u.employeeId})', overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (u) {
                              if (u != null) {
                                setState(() => _selectedUser = u);
                                _loadUserHistory(u.id);
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // Select Shift Dropdown
                          DropdownButtonFormField<ShiftModel>(
                            isExpanded: true,
                            value: _selectedShift,
                            decoration: const InputDecoration(
                              labelText: 'Select Shift (30+ Configured Shifts) *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.access_time_rounded),
                            ),
                            items: _shifts.map((s) {
                              return DropdownMenuItem(
                                value: s,
                                child: Text('${s.shiftCode} - ${s.shiftName} (${s.rules.length} rules)', overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (s) => setState(() => _selectedShift = s),
                          ),
                          const SizedBox(height: 16),

                          // Effective Dates
                          if (context.isSmallScreen) ...[
                            InkWell(
                              onTap: () => _pickDate(true),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Effective From *',
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                                ),
                                child: Text(dateFormat.format(_effectiveFrom), style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () => _pickDate(false),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Effective To (Optional)',
                                  border: const OutlineInputBorder(),
                                  suffixIcon: _effectiveTo != null
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 16),
                                          onPressed: () => setState(() => _effectiveTo = null),
                                        )
                                      : const Icon(Icons.calendar_today, size: 18),
                                ),
                                child: Text(
                                  _effectiveTo != null ? dateFormat.format(_effectiveTo!) : 'Ongoing',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _effectiveTo != null ? AppColors.textPrimary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _pickDate(true),
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                        labelText: 'Effective From *',
                                        border: OutlineInputBorder(),
                                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                                      ),
                                      child: Text(dateFormat.format(_effectiveFrom), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _pickDate(false),
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Effective To (Optional)',
                                        border: const OutlineInputBorder(),
                                        suffixIcon: _effectiveTo != null
                                            ? IconButton(
                                                icon: const Icon(Icons.clear, size: 16),
                                                onPressed: () => setState(() => _effectiveTo = null),
                                              )
                                            : const Icon(Icons.calendar_today, size: 18),
                                      ),
                                      child: Text(
                                        _effectiveTo != null ? dateFormat.format(_effectiveTo!) : 'Ongoing',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _effectiveTo != null ? AppColors.textPrimary : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),

                          ElevatedButton.icon(
                            onPressed: _isSubmitting ? null : _assignShift,
                            icon: _isSubmitting
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.check_circle_outline),
                            label: const Text('Save Shift Assignment'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Employee Historical Shift Timeline
                  if (_selectedUser != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 20, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Shift History for ${_selectedUser!.fullName}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_history.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No historical shift assignments found for this employee.', style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      )
                    else
                      ..._history.map((h) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: h.isActive ? AppColors.primary : Colors.grey,
                              child: const Icon(Icons.schedule, color: Colors.white, size: 18),
                            ),
                            title: Text(
                              '${h.shiftCode ?? "Shift"} - ${h.shiftName ?? ""}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('Effective: ${h.effectiveFrom} to ${h.effectiveTo ?? "Ongoing"}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (h.isActive ? AppColors.success : Colors.grey).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    h.isActive ? 'Active' : 'Past',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: h.isActive ? AppColors.success : Colors.grey,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                                  tooltip: 'Remove shift assignment',
                                  onPressed: () => _removeShiftAssignment(h),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                  ],
                ],
              ),
            ),
    );
  }
}
