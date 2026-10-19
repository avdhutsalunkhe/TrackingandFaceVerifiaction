import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/responsive_util.dart';
import '../../models/shift_model.dart';

class ShiftCreateEditScreen extends StatefulWidget {
  final ShiftModel? shift;

  const ShiftCreateEditScreen({Key? key, this.shift}) : super(key: key);

  @override
  State<ShiftCreateEditScreen> createState() => _ShiftCreateEditScreenState();
}

class _ShiftCreateEditScreenState extends State<ShiftCreateEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApiClient _apiClient = ApiClient();

  late TextEditingController _codeCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  bool _isActive = true;
  bool _isSaving = false;

  List<ShiftRuleModel> _rules = [];

  @override
  void initState() {
    super.initState();
    final isEdit = widget.shift != null;
    _codeCtrl = TextEditingController(text: isEdit ? widget.shift!.shiftCode : '');
    _nameCtrl = TextEditingController(text: isEdit ? widget.shift!.shiftName : '');
    _descCtrl = TextEditingController(text: isEdit ? (widget.shift!.description ?? '') : '');
    _isActive = isEdit ? widget.shift!.isActive : true;

    if (isEdit && widget.shift!.rules.isNotEmpty) {
      _rules = widget.shift!.rules
          .map((r) => ShiftRuleModel(
                id: r.id,
                shiftId: r.shiftId,
                ruleCode: r.ruleCode,
                ruleName: r.ruleName,
                startTime: r.startTime,
                endTime: r.endTime,
                resultCode: r.resultCode,
                priority: r.priority,
                isActive: r.isActive,
                showInUserSchedule: r.showInUserSchedule,
                verificationNo: r.verificationNo,
              ))
          .toList();
    } else {
      // Default initial templates for a fresh shift
      _rules = [
        ShiftRuleModel(
          ruleCode: 'PUNCH_1',
          ruleName: 'Morning Verification',
          startTime: '08:00:00',
          endTime: '09:00:00',
          resultCode: 'ON_TIME',
          priority: 1,
          showInUserSchedule: true,
          verificationNo: 1,
        ),
        ShiftRuleModel(
          ruleCode: 'PUNCH_2',
          ruleName: 'Afternoon Verification',
          startTime: '13:00:00',
          endTime: '14:00:00',
          resultCode: 'AFTERNOON_PUNCH',
          priority: 2,
          showInUserSchedule: true,
          verificationNo: 2,
        ),
        ShiftRuleModel(
          ruleCode: 'PUNCH_3',
          ruleName: 'Evening Verification',
          startTime: '17:00:00',
          endTime: '18:00:00',
          resultCode: 'ON_TIME',
          priority: 3,
          showInUserSchedule: true,
          verificationNo: 3,
        ),
      ];
    }
  }

  void _addNewPunchPeriod() {
    final nextNum = _rules.length + 1;
    setState(() {
      _rules.add(
        ShiftRuleModel(
          ruleCode: 'PUNCH_$nextNum',
          ruleName: 'Punch #$nextNum',
          startTime: '09:00:00',
          endTime: '10:00:00',
          resultCode: 'ON_TIME',
          priority: nextNum,
          showInUserSchedule: true,
          requireFaceVerification: true,
          isActive: true,
          verificationNo: nextNum,
        ),
      );
    });
  }

  void _removeRule(int index) {
    setState(() {
      _rules.removeAt(index);
      for (int i = 0; i < _rules.length; i++) {
        _rules[i].verificationNo = i + 1;
        _rules[i].priority = i + 1;
      }
    });
  }

  void _movePeriod(int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= _rules.length) return;
    setState(() {
      final item = _rules.removeAt(oldIndex);
      _rules.insert(newIndex, item);
      for (int i = 0; i < _rules.length; i++) {
        _rules[i].verificationNo = i + 1;
        _rules[i].priority = i + 1;
      }
    });
  }

  Future<void> _pickTime(int index, bool isStart) async {
    final currentStr = isStart ? _rules[index].startTime : _rules[index].endTime;
    final parts = currentStr.split(':');
    final initialTime = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts[1]) ?? 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      final hourStr = picked.hour.toString().padLeft(2, '0');
      final minStr = picked.minute.toString().padLeft(2, '0');
      setState(() {
        if (isStart) {
          _rules[index].startTime = '$hourStr:$minStr:00';
        } else {
          _rules[index].endTime = '$hourStr:$minStr:00';
        }
      });
    }
  }

  Future<void> _saveShift() async {
    if (!_formKey.currentState!.validate()) return;
    if (_rules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one punch period'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final isEdit = widget.shift != null;
      final periodsPayload = _rules.asMap().entries.map((entry) {
        final idx = entry.key;
        final r = entry.value;
        return {
          'punch_no': idx + 1,
          'period_name': r.ruleName.trim(),
          'start_time': r.startTime,
          'end_time': r.endTime,
          'show_in_user_schedule': r.showInUserSchedule,
          'is_active': r.isActive,
          'require_face_verification': r.requireFaceVerification,
          'priority': idx + 1,
        };
      }).toList();

      final payload = {
        'shift_code': _codeCtrl.text.trim().toUpperCase(),
        'shift_name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'is_active': _isActive,
        'punch_periods': periodsPayload,
        'rules': _rules.map((r) => r.toJson()).toList(),
      };

      if (isEdit) {
        await _apiClient.put(ApiConstants.adminShiftDetail(widget.shift!.id), data: payload);
      } else {
        await _apiClient.post(ApiConstants.adminShifts, data: payload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEdit ? 'Shift updated successfully!' : 'New Shift created successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error),
              SizedBox(width: 8),
              Text('Validation Error'),
            ],
          ),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.shift != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Shift: ${widget.shift!.shiftCode}' : 'Create New Shift'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: 'Save Shift',
            onPressed: _isSaving ? null : _saveShift,
          ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              maxWidth: context.isDesktop ? 1200 : (context.isTablet ? 900 : double.infinity),
              padding: EdgeInsets.zero,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: ResponsiveUtil.screenPadding(context),
                  children: [
                    // General Shift Info
                    Card(
                      child: Padding(
                        padding: ResponsiveUtil.cardPadding(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Shift Metadata', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _codeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Shift Code * (e.g. S001, S002, S030)',
                                hintText: 'S001',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Shift Name * (e.g. General Shift, Morning Shift)',
                                hintText: 'General Shift',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _descCtrl,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Description (Optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Shift Active Status', style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('Inactive shifts are not selectable for punch evaluation'),
                              value: _isActive,
                              onChanged: (val) => setState(() => _isActive = val),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Dynamic Shift Punch Periods Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Punch Periods',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _addNewPunchPeriod,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add Punch Period'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Punch Periods list
                    ..._rules.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final rule = entry.value;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: AppColors.primary,
                                        child: Text(
                                          '${idx + 1}',
                                          style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Punch Period #${idx + 1}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      if (idx > 0)
                                        IconButton(
                                          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                                          tooltip: 'Move Up',
                                          onPressed: () => _movePeriod(idx, idx - 1),
                                        ),
                                      if (idx < _rules.length - 1)
                                        IconButton(
                                          icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                                          tooltip: 'Move Down',
                                          onPressed: () => _movePeriod(idx, idx + 1),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                                        tooltip: 'Remove Period',
                                        onPressed: () => _removeRule(idx),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 12),

                              // Rule Name
                              TextFormField(
                                initialValue: rule.ruleName,
                                decoration: const InputDecoration(labelText: 'Rule Name *', isDense: true),
                                onChanged: (v) => rule.ruleName = v,
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                              const SizedBox(height: 12),

                              // Show Verification to User Toggle Section
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: rule.showInUserSchedule
                                      ? AppColors.primary.withValues(alpha: 0.06)
                                      : Colors.grey.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: rule.showInUserSchedule
                                        ? AppColors.primary.withValues(alpha: 0.3)
                                        : Colors.grey.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Show Verification to User',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: rule.showInUserSchedule ? Colors.green : Colors.grey.shade600,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  rule.showInUserSchedule ? '● ON' : '○ OFF',
                                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  rule.showInUserSchedule
                                                      ? 'Employee can see & verify'
                                                      : 'Hidden from employee schedule',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: rule.showInUserSchedule ? Colors.green.shade800 : Colors.grey.shade700,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: rule.showInUserSchedule,
                                      activeColor: AppColors.primary,
                                      onChanged: (val) {
                                        setState(() {
                                          rule.showInUserSchedule = val;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Time Windows (Second level precision)
                              if (context.isSmallScreen) ...[
                                InkWell(
                                  onTap: () => _pickTime(idx, true),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Start Time (HH:MM:SS)',
                                      isDense: true,
                                      suffixIcon: Icon(Icons.access_time, size: 18),
                                    ),
                                    child: Text(rule.startTime, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => _pickTime(idx, false),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'End Time (HH:MM:SS)',
                                      isDense: true,
                                      suffixIcon: Icon(Icons.access_time, size: 18),
                                    ),
                                    child: Text(rule.endTime, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => _pickTime(idx, true),
                                        child: InputDecorator(
                                          decoration: const InputDecoration(
                                            labelText: 'Start Time (HH:MM:SS)',
                                            isDense: true,
                                            suffixIcon: Icon(Icons.access_time, size: 18),
                                          ),
                                          child: Text(rule.startTime, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => _pickTime(idx, false),
                                        child: InputDecorator(
                                          decoration: const InputDecoration(
                                            labelText: 'End Time (HH:MM:SS)',
                                            isDense: true,
                                            suffixIcon: Icon(Icons.access_time, size: 18),
                                          ),
                                          child: Text(rule.endTime, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 12),

                              // Toggles: Active Status & Require Face Verification
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          rule.isActive = !rule.isActive;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: rule.isActive
                                              ? Colors.green.withValues(alpha: 0.1)
                                              : Colors.grey.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: rule.isActive ? Colors.green : Colors.grey,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              rule.isActive ? Icons.check_circle : Icons.cancel,
                                              size: 16,
                                              color: rule.isActive ? Colors.green : Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              rule.isActive ? 'Active: ON' : 'Active: OFF',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: rule.isActive ? Colors.green.shade900 : Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          rule.requireFaceVerification = !rule.requireFaceVerification;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: rule.requireFaceVerification
                                              ? AppColors.primary.withValues(alpha: 0.1)
                                              : Colors.grey.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: rule.requireFaceVerification ? AppColors.primary : Colors.grey,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              rule.requireFaceVerification ? Icons.face_rounded : Icons.face_outlined,
                                              size: 16,
                                              color: rule.requireFaceVerification ? AppColors.primary : Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              rule.requireFaceVerification ? 'Face: ON' : 'Face: OFF',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: rule.requireFaceVerification ? AppColors.primary : Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveShift,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(isEdit ? 'Save Shift Changes' : 'Create Shift & Validate Non-Overlap'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }
}
