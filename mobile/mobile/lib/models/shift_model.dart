class ShiftRuleModel {
  final int? id;
  final int? shiftId;
  String ruleCode;
  String ruleName;
  String startTime; // HH:MM:SS
  String endTime;   // HH:MM:SS
  String resultCode;// ON_TIME, LATE, HALF_DAY, AFTERNOON_PUNCH, etc.
  int priority;
  bool isActive;
  bool showInUserSchedule;
  bool requireFaceVerification;
  int verificationNo;

  ShiftRuleModel({
    this.id,
    this.shiftId,
    required this.ruleCode,
    required this.ruleName,
    required this.startTime,
    required this.endTime,
    required this.resultCode,
    this.priority = 1,
    this.isActive = true,
    this.showInUserSchedule = true,
    this.requireFaceVerification = true,
    this.verificationNo = 1,
  });

  int get punchNo => verificationNo;
  set punchNo(int v) => verificationNo = v;
  String get periodName => ruleName;
  set periodName(String v) => ruleName = v;

  factory ShiftRuleModel.fromJson(Map<String, dynamic> json) {
    final vNo = json['punch_no'] ?? json['verification_no'] ?? 1;
    final pName = json['period_name'] ?? json['rule_name'] ?? 'Punch #$vNo';
    return ShiftRuleModel(
      id: json['id'],
      shiftId: json['shift_id'],
      ruleCode: json['rule_code'] ?? 'PUNCH_$vNo',
      ruleName: pName,
      startTime: json['start_time'] ?? '08:30:00',
      endTime: json['end_time'] ?? '09:09:59',
      resultCode: json['result_code'] ?? json['result_classification'] ?? 'ON_TIME',
      priority: json['priority'] ?? 1,
      isActive: json['is_active'] ?? true,
      showInUserSchedule: json['show_in_user_schedule'] ?? true,
      requireFaceVerification: json['require_face_verification'] ?? true,
      verificationNo: vNo,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rule_code': ruleCode,
      'rule_name': ruleName,
      'period_name': ruleName,
      'punch_no': verificationNo,
      'start_time': startTime,
      'end_time': endTime,
      'result_code': resultCode,
      'result_classification': resultCode,
      'priority': priority,
      'is_active': isActive,
      'show_in_user_schedule': showInUserSchedule,
      'require_face_verification': requireFaceVerification,
      'verification_no': verificationNo,
    };
  }
}

class ShiftModel {
  final int id;
  final String shiftCode;
  final String shiftName;
  final String? description;
  final bool isActive;
  final List<ShiftRuleModel> rules;
  List<ShiftRuleModel> get punchPeriods => rules;
  final String? createdAt;

  ShiftModel({
    required this.id,
    required this.shiftCode,
    required this.shiftName,
    this.description,
    required this.isActive,
    required this.rules,
    this.createdAt,
  });

  factory ShiftModel.fromJson(Map<String, dynamic> json) {
    final rawList = (json['punch_periods'] as List<dynamic>?) ??
                    (json['rules'] as List<dynamic>?) ??
                    [];
    final rulesList = rawList
        .map((r) => ShiftRuleModel.fromJson(r as Map<String, dynamic>))
        .toList();

    return ShiftModel(
      id: json['id'] ?? 0,
      shiftCode: json['shift_code'] ?? '',
      shiftName: json['shift_name'] ?? '',
      description: json['description'],
      isActive: json['is_active'] ?? true,
      rules: rulesList,
      createdAt: json['created_at'],
    );
  }
}

class EmployeeShiftAssignmentModel {
  final int id;
  final int userId;
  final int shiftId;
  final String? shiftCode;
  final String? shiftName;
  final String effectiveFrom;
  final String? effectiveTo;
  final bool isActive;

  EmployeeShiftAssignmentModel({
    required this.id,
    required this.userId,
    required this.shiftId,
    this.shiftCode,
    this.shiftName,
    required this.effectiveFrom,
    this.effectiveTo,
    required this.isActive,
  });

  factory EmployeeShiftAssignmentModel.fromJson(Map<String, dynamic> json) {
    return EmployeeShiftAssignmentModel(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      shiftId: json['shift_id'] ?? 0,
      shiftCode: json['shift_code'],
      shiftName: json['shift_name'],
      effectiveFrom: json['effective_from'] ?? '',
      effectiveTo: json['effective_to'],
      isActive: json['is_active'] ?? true,
    );
  }
}
