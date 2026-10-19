import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/responsive_util.dart';
import '../../models/shift_model.dart';
import 'shift_create_edit_screen.dart';
import 'assign_shift_screen.dart';

class ShiftManagementScreen extends StatefulWidget {
  const ShiftManagementScreen({Key? key}) : super(key: key);

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
  final ApiClient _apiClient = ApiClient();
  bool _isLoading = true;
  List<ShiftModel> _shifts = [];
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _fetchShifts();
  }

  Future<void> _fetchShifts() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiClient.get(ApiConstants.adminShifts);
      if (res is List) {
        setState(() {
          _shifts = res.map((item) => ShiftModel.fromJson(item as Map<String, dynamic>)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading shifts: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _duplicateShift(ShiftModel shift) async {
    final codeCtrl = TextEditingController(text: "${shift.shiftCode}_COPY");
    final nameCtrl = TextEditingController(text: "${shift.shiftName} (Copy)");

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duplicate Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Clone "${shift.shiftName}" (${shift.shiftCode}) along with its ${shift.rules.length} configured rules.'),
            const SizedBox(height: 16),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'New Shift Code (e.g. S004)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'New Shift Name', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Duplicate')),
        ],
      ),
    );

    if (result == true) {
      try {
        await _apiClient.post(
          ApiConstants.adminShiftDuplicate(shift.id),
          data: {
            'new_shift_code': codeCtrl.text.trim().toUpperCase(),
            'new_shift_name': nameCtrl.text.trim(),
          },
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shift duplicated successfully!'), backgroundColor: AppColors.success),
        );
        _fetchShifts();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to duplicate: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _deleteShift(ShiftModel shift) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete / Deactivate Shift'),
        content: Text('Are you sure you want to remove "${shift.shiftName}" (${shift.shiftCode})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await _apiClient.delete(ApiConstants.adminShiftDetail(shift.id));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Shift removed'), backgroundColor: AppColors.success),
        );
        _fetchShifts();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _shifts.where((s) {
      return s.shiftCode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.shiftName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift Management (30+ Shifts)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: 'Assign Shift to Employee',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AssignShiftScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchShifts,
          ),
        ],
      ),
      body: ResponsiveContainer(
        maxWidth: context.isDesktop ? 1440 : (context.isTablet ? 960 : double.infinity),
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Search and Create Header
            Container(
              padding: context.isSmallScreen ? const EdgeInsets.all(12) : const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                children: [
                  TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search shift name or code...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Configured Shifts: ${_shifts.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final created = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (_) => const ShiftCreateEditScreen()),
                          );
                          if (created == true) _fetchShifts();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Create Shift'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Shift List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.schedule_rounded, size: 64, color: AppColors.textSecondary),
                              const SizedBox(height: 12),
                              const Text('No shifts found', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () async {
                                  final created = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(builder: (_) => const ShiftCreateEditScreen()),
                                  );
                                  if (created == true) _fetchShifts();
                                },
                                child: const Text('Create New Shift (e.g. S001)'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final shift = filtered[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ExpansionTile(
                                leading: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    shift.shiftCode,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                ),
                                title: Text(
                                  shift.shiftName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Text(
                                  '${shift.rules.length} Dynamic Rules • ${shift.isActive ? "Active" : "Inactive"}',
                                  style: TextStyle(
                                    color: shift.isActive ? AppColors.success : AppColors.error,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (val) async {
                                    if (val == 'edit') {
                                      final updated = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(builder: (_) => ShiftCreateEditScreen(shift: shift)),
                                      );
                                      if (updated == true) _fetchShifts();
                                    } else if (val == 'duplicate') {
                                      _duplicateShift(shift);
                                    } else if (val == 'delete') {
                                      _deleteShift(shift);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit Shift & Rules')]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'duplicate',
                                      child: Row(children: [Icon(Icons.copy, size: 18), SizedBox(width: 8), Text('Duplicate Shift')]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(children: [Icon(Icons.delete, color: AppColors.error, size: 18), SizedBox(width: 8), Text('Delete / Deactivate', style: TextStyle(color: AppColors.error))]),
                                    ),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (shift.description != null && shift.description!.isNotEmpty) ...[
                                          Text(shift.description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                          const SizedBox(height: 12),
                                        ],
                                        const Text(
                                          'Configured Non-Overlapping Time Windows:',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                                        ),
                                        const SizedBox(height: 8),
                                        ...shift.rules.map((rule) {
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 6),
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: AppColors.background,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: AppColors.border),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        rule.ruleName,
                                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      Text(
                                                        '${rule.startTime} - ${rule.endTime} (Priority ${rule.priority})',
                                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: _getClassificationColor(rule.resultCode).withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    rule.resultCode,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                      color: _getClassificationColor(rule.resultCode),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        const SizedBox(height: 10),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getClassificationColor(String code) {
    switch (code) {
      case 'ON_TIME':
        return AppColors.success;
      case 'LATE':
        return AppColors.warning;
      case 'HALF_DAY':
        return Colors.orange;
      case 'AFTERNOON_PUNCH':
        return Colors.purple;
      case 'SECOND_HALF':
        return Colors.indigo;
      default:
        return AppColors.primary;
    }
  }
}
