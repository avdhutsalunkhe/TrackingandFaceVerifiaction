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

  final bool faceEnabled;
  final bool geofenceEnabled;
  final bool shiftEnabled;
  final bool travelMapEnabled;
  final String? deviceId;
  final bool isDeviceRegistered;
  final String? deviceRegisteredAt;
  final String? deviceModel;

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
    this.faceEnabled = true,
    this.geofenceEnabled = true,
    this.shiftEnabled = true,
    this.travelMapEnabled = true,
    this.deviceId,
    this.isDeviceRegistered = false,
    this.deviceRegisteredAt,
    this.deviceModel,
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
      faceEnabled: json['face_enabled'] ?? true,
      geofenceEnabled: json['geofence_enabled'] ?? true,
      shiftEnabled: json['shift_enabled'] ?? true,
      travelMapEnabled: json['travel_map_enabled'] ?? true,
      deviceId: json['device_id'],
      isDeviceRegistered: json['is_device_registered'] ?? (json['device_id'] != null),
      deviceRegisteredAt: json['device_registered_at'],
      deviceModel: json['device_model'],
    );
  }

  UserModel copyWith({
    int? id,
    String? employeeId,
    String? fullName,
    String? role,
    bool? isActive,
    bool? mustChangePassword,
    bool? hasFaceEnrolled,
    Map<String, dynamic>? geofence,
    Map<String, dynamic>? attendanceWindow,
    bool? faceEnabled,
    bool? geofenceEnabled,
    bool? shiftEnabled,
    bool? travelMapEnabled,
    String? deviceId,
    bool? isDeviceRegistered,
    String? deviceRegisteredAt,
    String? deviceModel,
  }) {
    return UserModel(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      hasFaceEnrolled: hasFaceEnrolled ?? this.hasFaceEnrolled,
      geofence: geofence ?? this.geofence,
      attendanceWindow: attendanceWindow ?? this.attendanceWindow,
      faceEnabled: faceEnabled ?? this.faceEnabled,
      geofenceEnabled: geofenceEnabled ?? this.geofenceEnabled,
      shiftEnabled: shiftEnabled ?? this.shiftEnabled,
      travelMapEnabled: travelMapEnabled ?? this.travelMapEnabled,
      deviceId: deviceId ?? this.deviceId,
      isDeviceRegistered: isDeviceRegistered ?? this.isDeviceRegistered,
      deviceRegisteredAt: deviceRegisteredAt ?? this.deviceRegisteredAt,
      deviceModel: deviceModel ?? this.deviceModel,
    );
  }
}

