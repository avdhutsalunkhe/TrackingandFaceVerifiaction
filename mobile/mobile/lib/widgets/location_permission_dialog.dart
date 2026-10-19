import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/theme/app_theme.dart';
import '../core/services/location_service.dart';

class LocationPermissionDialog extends StatelessWidget {
  final LocationStatusType statusType;

  const LocationPermissionDialog({
    Key? key,
    required this.statusType,
  }) : super(key: key);

  /// Shows the location permission popup and handles granting/settings
  /// Returns true if permission/service was granted/enabled, false otherwise.
  static Future<bool> show(BuildContext context) async {
    final status = await LocationService.checkDetailedStatus();
    if (status == LocationStatusType.granted) {
      return true;
    }

    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LocationPermissionDialog(statusType: status),
    );

    if (result == true) {
      // Re-check status after user action
      final updatedStatus = await LocationService.checkDetailedStatus();
      return updatedStatus == LocationStatusType.granted;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isServiceDisabled = statusType == LocationStatusType.serviceDisabled;
    final isDeniedForever = statusType == LocationStatusType.permissionDeniedForever;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Location Access Required',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FieldStaff requires device GPS location to verify your attendance within the assigned geofenced work area.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          // Specific Status Warning Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isServiceDisabled
                  ? const Color(0xFFFFFBEB)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isServiceDisabled
                    ? const Color(0xFFFDE68A)
                    : const Color(0xFFFECACA),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isServiceDisabled
                      ? Icons.location_disabled_rounded
                      : Icons.warning_amber_rounded,
                  color: isServiceDisabled
                      ? const Color(0xFFD97706)
                      : const Color(0xFFDC2626),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isServiceDisabled
                        ? 'Device GPS is currently turned off. Please turn on Location services.'
                        : (isDeniedForever
                            ? 'Location permission is permanently blocked. Please enable Location in App Settings.'
                            : 'Please allow location permission when prompted.'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: isServiceDisabled
                          ? const Color(0xFF92400E)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (isServiceDisabled) {
              await Geolocator.openLocationSettings();
              if (context.mounted) Navigator.pop(context, true);
            } else if (isDeniedForever) {
              await Geolocator.openAppSettings();
              if (context.mounted) Navigator.pop(context, true);
            } else {
              final permission = await Geolocator.requestPermission();
              if (context.mounted) {
                Navigator.pop(
                  context,
                  permission == LocationPermission.always ||
                      permission == LocationPermission.whileInUse,
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            elevation: 0,
          ),
          child: Text(
            isServiceDisabled
                ? 'Turn On GPS'
                : (isDeniedForever ? 'Open Settings' : 'Allow Location'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
