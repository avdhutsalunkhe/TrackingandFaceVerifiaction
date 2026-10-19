import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  static final DeviceService instance = DeviceService._internal();
  DeviceService._internal();

  static const String _prefKeyDeviceId = 'app_device_id';
  String? _cachedDeviceId;

  /// Generates a cryptographically secure RFC 4122 version 4 UUID
  static String generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // Set version 4 (bits 12-15 = 0100)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122 (bits 6-7 = 10)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Returns the persistent, app-installation-specific UUID.
  /// Generates it on the first app launch and persists across normal restarts and logouts.
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_prefKeyDeviceId);
    if (id == null || id.trim().isEmpty) {
      id = generateUuidV4();
      await prefs.setString(_prefKeyDeviceId, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  /// Copies the Device ID to the system clipboard and displays a feedback toast.
  Future<void> copyDeviceId(BuildContext context) async {
    final id = await getDeviceId();
    await Clipboard.setData(ClipboardData(text: id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Device ID copied to clipboard: $id'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
