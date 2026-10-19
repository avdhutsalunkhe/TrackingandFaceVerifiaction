import 'package:intl/intl.dart';

class AttendanceRecordModel {
  final int id;
  final int userId;
  final String employeeId;
  final String fullName;
  final String attendanceDate;
  final String timestamp;
  final String? formattedDate;
  final String? formattedTime;
  final String status;
  final double verifiedLatitude;
  final double verifiedLongitude;
  final double verifiedDistanceMeters;
  final double faceSimilarityScore;
  final double livenessScore;
  final String? locationName;
  final String? shiftCode;
  final String? shiftName;
  final String attendanceClassification;
  final String verificationMode;
  final int? verificationNo;
  final String? verificationWindow;
  final String source; // ONLINE or OFFLINE
  final String verificationStatus; // COMPLETED, PENDING_SYNC, REVIEW_REQUIRED, REJECTED
  final String? clientPunchId;
  final String? syncStatus;
  final String? syncNotes;

  AttendanceRecordModel({
    required this.id,
    required this.userId,
    required this.employeeId,
    required this.fullName,
    required this.attendanceDate,
    required this.timestamp,
    this.formattedDate,
    this.formattedTime,
    required this.status,
    required this.verifiedLatitude,
    required this.verifiedLongitude,
    required this.verifiedDistanceMeters,
    required this.faceSimilarityScore,
    required this.livenessScore,
    this.locationName,
    this.shiftCode,
    this.shiftName,
    this.attendanceClassification = 'ON_TIME',
    this.verificationMode = 'FACE',
    this.verificationNo,
    this.verificationWindow,
    this.source = 'ONLINE',
    this.verificationStatus = 'COMPLETED',
    this.clientPunchId,
    this.syncStatus,
    this.syncNotes,
  });

  String get displayTime {
    if (formattedTime != null && formattedTime!.isNotEmpty) {
      return formattedTime!;
    }
    if (timestamp.isEmpty) return '--:--';
    try {
      final dt = DateTime.parse(timestamp);
      final local = dt.isUtc ? dt.toLocal() : dt;
      return DateFormat('hh:mm:ss a').format(local);
    } catch (_) {
      final parts = timestamp.split('T');
      if (parts.length > 1) {
        return parts[1].split('.')[0];
      }
      return timestamp;
    }
  }

  String get displayDate {
    if (formattedDate != null && formattedDate!.isNotEmpty) {
      return formattedDate!;
    }
    if (attendanceDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(attendanceDate);
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return attendanceDate;
    }
  }

  factory AttendanceRecordModel.fromJson(Map<String, dynamic> json) {
    return AttendanceRecordModel(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      employeeId: json['employee_id'] ?? '',
      fullName: json['full_name'] ?? '',
      attendanceDate: json['attendance_date'] ?? '',
      timestamp: json['timestamp'] ?? '',
      formattedDate: json['formatted_date'],
      formattedTime: json['formatted_time'],
      status: json['status'] ?? 'PRESENT',
      verifiedLatitude: (json['verified_latitude'] as num?)?.toDouble() ?? 0.0,
      verifiedLongitude: (json['verified_longitude'] as num?)?.toDouble() ?? 0.0,
      verifiedDistanceMeters: (json['verified_distance_meters'] as num?)?.toDouble() ?? 0.0,
      faceSimilarityScore: (json['face_similarity_score'] as num?)?.toDouble() ?? 1.0,
      livenessScore: (json['liveness_score'] as num?)?.toDouble() ?? 1.0,
      locationName: json['location_name'],
      shiftCode: json['shift_code'],
      shiftName: json['shift_name'],
      attendanceClassification: json['attendance_classification'] ?? 'ON_TIME',
      verificationMode: json['verification_mode'] ?? 'FACE',
      verificationNo: json['verification_no'],
      verificationWindow: json['verification_window'],
      source: json['source'] ?? 'ONLINE',
      verificationStatus: json['verification_status'] ?? 'COMPLETED',
      clientPunchId: json['client_punch_id'],
      syncStatus: json['sync_status'],
      syncNotes: json['sync_notes'],
    );
  }
}

class VerificationWindowItem {
  final int? id;
  final int verificationNo;
  final String? ruleName;
  final String? ruleCode;
  final String start;
  final String end;
  final String label;
  final String status; // UPCOMING, AVAILABLE, COMPLETED, MISSED, PENDING_SYNC
  final String? punchTime;
  final String? verifiedAt;
  final String? source;
  final bool showInUserSchedule;
  final bool requireFaceVerification;

  VerificationWindowItem({
    this.id,
    required this.verificationNo,
    this.ruleName,
    this.ruleCode,
    required this.start,
    required this.end,
    required this.label,
    required this.status,
    this.punchTime,
    this.verifiedAt,
    this.source,
    this.showInUserSchedule = true,
    this.requireFaceVerification = true,
  });

  int? get punchPeriodId => id;
  int get punchNo => verificationNo;
  String get periodName => ruleName ?? 'Punch #$verificationNo';
  String get startTime => start;
  String get endTime => end;

  factory VerificationWindowItem.fromJson(Map<String, dynamic> json) {
    final startStr = json['start'] ?? json['start_time'] ?? '00:00:00';
    final endStr = json['end'] ?? json['end_time'] ?? '23:59:59';
    final vNo = json['punch_no'] ?? json['verification_no'] ?? 1;
    final rName = json['name'] ?? json['period_name'] ?? json['rule_name'] ?? 'Punch #$vNo';

    String labelStr = json['label'] ?? '';
    if (labelStr.isEmpty) {
      try {
        final sParts = startStr.split(':').map(int.parse).toList();
        final eParts = endStr.split(':').map(int.parse).toList();
        final sHour12 = sParts[0] > 12 ? sParts[0] - 12 : (sParts[0] == 0 ? 12 : sParts[0]);
        final eHour12 = eParts[0] > 12 ? eParts[0] - 12 : (eParts[0] == 0 ? 12 : eParts[0]);
        final sAmPm = sParts[0] >= 12 ? 'PM' : 'AM';
        final eAmPm = eParts[0] >= 12 ? 'PM' : 'AM';
        labelStr = '${sHour12.toString().padLeft(2, '0')}:${sParts[1].toString().padLeft(2, '0')} $sAmPm – ${eHour12.toString().padLeft(2, '0')}:${eParts[1].toString().padLeft(2, '0')} $eAmPm';
      } catch (_) {
        labelStr = '$startStr – $endStr';
      }
    }

    return VerificationWindowItem(
      id: json['id'] ?? json['punch_period_id'],
      verificationNo: vNo,
      ruleName: rName,
      ruleCode: json['rule_code'] ?? 'PUNCH_$vNo',
      start: startStr,
      end: endStr,
      label: labelStr,
      status: json['status'] ?? 'UPCOMING',
      punchTime: json['punch_time'] ?? json['verified_at'],
      verifiedAt: json['verified_at'] ?? json['punch_time'],
      source: json['source'],
      showInUserSchedule: json['show_in_user_schedule'] ?? true,
      requireFaceVerification: json['require_face_verification'] ?? true,
    );
  }
}

class PunchPeriodItem {
  final int id;
  final int punchNo;
  final String name;
  final String startTime;
  final String endTime;
  final String label;
  final String status;
  final String? punchTime;
  final String? verifiedAt;
  final String? source;
  final bool showInUserSchedule;
  final bool requireFaceVerification;

  PunchPeriodItem({
    required this.id,
    required this.punchNo,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.label,
    required this.status,
    this.punchTime,
    this.verifiedAt,
    this.source,
    this.showInUserSchedule = true,
    this.requireFaceVerification = true,
  });

  factory PunchPeriodItem.fromJson(Map<String, dynamic> json) {
    final w = VerificationWindowItem.fromJson(json);
    return PunchPeriodItem(
      id: w.id ?? 0,
      punchNo: w.verificationNo,
      name: w.periodName,
      startTime: w.start,
      endTime: w.end,
      label: w.label,
      status: w.status,
      punchTime: w.punchTime,
      verifiedAt: w.verifiedAt,
      source: w.source,
      showInUserSchedule: w.showInUserSchedule,
      requireFaceVerification: w.requireFaceVerification,
    );
  }
}

class AttendanceActionModel {
  final bool punchAllowed;
  final int? activePunchPeriodId;
  final String? activePunchPeriodName;
  final String? reason;

  AttendanceActionModel({
    required this.punchAllowed,
    this.activePunchPeriodId,
    this.activePunchPeriodName,
    this.reason,
  });

  factory AttendanceActionModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return AttendanceActionModel(punchAllowed: false, reason: 'NO_ACTION_DATA');
    }
    return AttendanceActionModel(
      punchAllowed: json['punch_allowed'] ?? false,
      activePunchPeriodId: json['active_punch_period_id'],
      activePunchPeriodName: json['active_punch_period_name'],
      reason: json['reason'],
    );
  }
}
