import '../../config/api_config.dart';

class ApiConstants {
  // Configured backend URLs from centralized ApiConfig
  static const List<String> serverCandidates = [
    ApiConfig.lanApiUrl,        // 1st: http://192.168.1.91:8084 (Office LAN)
    ApiConfig.primaryApiUrl,    // 2nd: http://182.66.233.66:8084 (Public Primary)
    ApiConfig.secondaryApiUrl,  // 3rd: http://115.244.240.22:8084 (Public Secondary)
  ];

  static const String defaultBaseUrl = ApiConfig.lanApiUrl;
  
  // Auth endpoints
  static const String login = '/api/auth/login';
  static const String changePassword = '/api/auth/change-password';
  static const String me = '/api/auth/me';

  // Admin endpoints
  static const String dashboardStats = '/api/admin/dashboard-stats';
  static const String adminUsers = '/api/admin/users';
  static String adminUserDetail(int id) => '/api/admin/users/$id';
  static String adminUserFace(int id) => '/api/admin/users/$id/face';
  static String adminUserGeofence(int id) => '/api/admin/users/$id/geofence';
  static String adminUserWindow(int id) => '/api/admin/users/$id/attendance-window';
  static String adminUserFeatures(int id) => '/api/admin/users/$id/features';
  static String adminUserFeatureToggle(int id) => '/api/admin/users/$id/features/toggle';
  static String adminUserDevice(int id) => '/api/admin/users/$id/device';
  static const String adminAttendance = '/api/admin/attendance';
  
  // Shift Management endpoints
  static const String adminShifts = '/api/admin/shifts';
  static String adminShiftDetail(int id) => '/api/admin/shifts/$id';
  static String adminShiftDuplicate(int id) => '/api/admin/shifts/$id/duplicate';
  static const String adminShiftAssign = '/api/admin/shifts/assign';
  static String adminUserShiftHistory(int userId) => '/api/admin/shifts/users/$userId/shift-history';
  static String adminDeleteShiftAssignment(int assignmentId) => '/api/admin/shifts/assignments/$assignmentId';

  // Global System Settings
  static const String adminBiometricSettings = '/api/admin/settings/biometric';

  // Admin Attendance Requests endpoints
  static const String adminAttendanceRequests = '/api/admin/attendance-requests';
  static String adminAttendanceRequestImage(int id) => '/api/admin/attendance-requests/$id/image';
  static String adminApproveAttendanceRequest(int id) => '/api/admin/attendance-requests/$id/approve';
  static String adminRejectAttendanceRequest(int id) => '/api/admin/attendance-requests/$id/reject';

  // User endpoints
  static const String serverTime = '/api/user/server-time';
  static const String attendanceConfig = '/api/user/attendance-config';
  static const String todaySchedule = '/api/user/today-schedule';
  static const String verifyAttendance = '/api/user/attendance/verify';
  static const String syncOffline = '/api/user/attendance/sync-offline';
  static const String userAttendanceHistory = '/api/user/attendance';
  static const String submitAttendanceRequest = '/api/user/attendance-request';
  static const String userAttendanceRequests = '/api/user/attendance-requests';
}
