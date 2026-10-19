class UserModel {
  final int id;
  final String employeeId;
  final String fullName;
  final String role;
  final bool isActive;
  final bool mustChangePassword;
  final bool hasFaceEnrolled;
  final Map<String, dynamic>? geofence;
  final Map<String, dynamic>? attendanceWindow;

  UserModel({
    required this.id,
    required this.employeeId,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.mustChangePassword,
    required this.hasFaceEnrolled,
    this.geofence,
    this.attendanceWindow,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      employeeId: json['employee_id'] ?? '',
      fullName: json['full_name'] ?? '',
      role: json['role'] ?? 'USER',
      isActive: json['is_active'] ?? true,
      mustChangePassword: json['must_change_password'] ?? false,
      hasFaceEnrolled: json['has_face_enrolled'] ?? false,
      geofence: json['geofence'] != null ? Map<String, dynamic>.from(json['geofence']) : null,
      attendanceWindow: json['attendance_window'] != null ? Map<String, dynamic>.from(json['attendance_window']) : null,
    );
  }
}
