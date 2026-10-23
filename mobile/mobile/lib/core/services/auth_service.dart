import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../network/api_client.dart';
import 'device_service.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> login(String employeeId, String password) async {
    final deviceId = await DeviceService.instance.getDeviceId();
    final res = await _apiClient.post(
      ApiConstants.login,
      body: {
        'employee_id': employeeId.trim(),
        'password': password.trim(),
        'client_type': kIsWeb ? 'WEB' : 'MOBILE',
        'device_id': deviceId,
      },
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', res['access_token']);
    if (res['refresh_token'] != null && res['refresh_token'].toString().isNotEmpty) {
      await prefs.setString('refresh_token', res['refresh_token'].toString());
    }
    if (res['expires_at'] != null) {
      final exp = res['expires_at'] is int
          ? res['expires_at']
          : int.tryParse(res['expires_at'].toString());
      if (exp != null) {
        await prefs.setInt('token_expires_at', exp);
      }
    }
    if (deviceId.isNotEmpty) {
      await prefs.setString('device_id', deviceId);
    }
    await prefs.setString('role', res['role']);
    await prefs.setString('employee_id', res['employee_id']);
    await prefs.setString('full_name', res['full_name']);
    if (res['user_id'] != null) {
      await prefs.setInt('user_id', res['user_id'] is int ? res['user_id'] : int.tryParse(res['user_id'].toString()) ?? 0);
    }
    await prefs.setBool('must_change_password', res['must_change_password'] ?? false);

    // Save effective feature toggles
    await prefs.setBool('face_enabled', res['face_enabled'] ?? true);
    await prefs.setBool('geofence_enabled', res['geofence_enabled'] ?? true);
    await prefs.setBool('shift_enabled', res['shift_enabled'] ?? true);
    await prefs.setBool('travel_map_enabled', res['travel_map_enabled'] ?? true);

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
    await prefs.remove('refresh_token');
    await prefs.remove('token_expires_at');
    await prefs.remove('role');
    await prefs.remove('employee_id');
    await prefs.remove('full_name');
    await prefs.remove('must_change_password');
    await prefs.remove('user_id');
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
