import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../network/api_client.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> login(String employeeId, String password) async {
    final res = await _apiClient.post(
      ApiConstants.login,
      body: {
        'employee_id': employeeId.trim(),
        'password': password.trim(),
        'client_type': 'MOBILE',
      },
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', res['access_token']);
    await prefs.setString('role', res['role']);
    await prefs.setString('employee_id', res['employee_id']);
    await prefs.setString('full_name', res['full_name']);
    await prefs.setBool('must_change_password', res['must_change_password'] ?? false);

    return res;
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _apiClient.post(
      ApiConstants.changePassword,
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('must_change_password', false);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('role');
    await prefs.remove('employee_id');
    await prefs.remove('full_name');
    await prefs.remove('must_change_password');
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    return token != null && token.isNotEmpty;
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'role': prefs.getString('role') ?? 'USER',
      'employee_id': prefs.getString('employee_id') ?? '',
      'full_name': prefs.getString('full_name') ?? '',
      'must_change_password': prefs.getBool('must_change_password') ?? false,
    };
  }
}
