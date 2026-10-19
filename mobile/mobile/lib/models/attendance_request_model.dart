class AttendanceRequestModel {
  final int id;
  final int userId;
  final String employeeId;
  final String fullName;
  final String requestDate;
  final String serverTimestamp;
  final String serverFormattedDate;
  final String serverFormattedTime;
  final String? deviceTimestamp;
  final int? shiftId;
  final String? shiftName;
  final String? shiftCode;
  final String status;
  final String? rejectionReasonTrigger;
  final double latitude;
  final double longitude;
  final double? gpsAccuracy;
  final String? locationName;
  final String? assignedLocationName;
  final double distanceFromLocation;
  final bool isWithinGeofence;
  final bool hasEvidenceImage;
  final String? adminNotes;
  final String? reviewedAt;
  final String? reviewedByName;
  final String createdAt;

  AttendanceRequestModel({
    required this.id,
    required this.userId,
    required this.employeeId,
    required this.fullName,
    required this.requestDate,
    required this.serverTimestamp,
    required this.serverFormattedDate,
    required this.serverFormattedTime,
    this.deviceTimestamp,
    this.shiftId,
    this.shiftName,
    this.shiftCode,
    required this.status,
    this.rejectionReasonTrigger,
    required this.latitude,
    required this.longitude,
    this.gpsAccuracy,
    this.locationName,
    this.assignedLocationName,
    required this.distanceFromLocation,
    required this.isWithinGeofence,
    this.hasEvidenceImage = true,
    this.adminNotes,
    this.reviewedAt,
    this.reviewedByName,
    required this.createdAt,
  });

  factory AttendanceRequestModel.fromJson(Map<String, dynamic> json) {
    return AttendanceRequestModel(
      id: json['id'],
      userId: json['user_id'],
      employeeId: json['employee_id'] ?? '',
      fullName: json['full_name'] ?? '',
      requestDate: json['request_date'] ?? '',
      serverTimestamp: json['server_timestamp'] ?? '',
      serverFormattedDate: json['server_formatted_date'] ?? '',
      serverFormattedTime: json['server_formatted_time'] ?? '',
      deviceTimestamp: json['device_timestamp'],
      shiftId: json['shift_id'],
      shiftName: json['shift_name'],
      shiftCode: json['shift_code'],
      status: json['status'] ?? 'PENDING',
      rejectionReasonTrigger: json['rejection_reason_trigger'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      gpsAccuracy: json['gps_accuracy'] != null ? (json['gps_accuracy'] as num).toDouble() : null,
      locationName: json['location_name'],
      assignedLocationName: json['assigned_location_name'],
      distanceFromLocation: (json['distance_from_location'] as num).toDouble(),
      isWithinGeofence: json['is_within_geofence'] ?? false,
      hasEvidenceImage: json['has_evidence_image'] ?? true,
      adminNotes: json['admin_notes'],
      reviewedAt: json['reviewed_at'],
      reviewedByName: json['reviewed_by_name'],
      createdAt: json['created_at'] ?? '',
    );
  }
}
