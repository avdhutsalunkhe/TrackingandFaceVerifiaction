import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../core/services/tracking_service.dart';
import '../core/services/notification_service.dart';

class TrackingConsentDialog {
  /// Displays the mandatory GPS duty tracking dialog after login.
  /// If OK is pressed, tracking starts immediately and returns true (opens dashboard).
  /// If Cancel is pressed, closes the app and returns false.
  static Future<bool> showAndHandleConsent(
    BuildContext context, {
    required int userId,
    required String employeeId,
  }) async {
    // If tracking is already running (e.g. session restored), proceed directly
    if (TrackingService.instance.isTracking) {
      return true;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.location_on_rounded, color: AppColors.primary, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Start Duty & GPS Tracking',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Continuous GPS journey tracking is required during field duty hours to record travel routes and calculate field distance.',
              style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
            ),
            SizedBox(height: 12),
            Text(
              'Press OK to start tracking and open the attendance portal, or Cancel to exit the application.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: const Text('Cancel (Exit App)'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            child: const Text(
              'OK (Start Duty)',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await TrackingService.instance.startTrackingForLogin(
          userId: userId,
          employeeId: employeeId,
        );
        await NotificationService.instance.notifyPunchSuccess(
          title: 'Duty Tracking Started',
          message: 'Continuous GPS journey tracking is now active for your duty.',
        );
      } catch (e) {
        debugPrint('[TrackingConsent] Error starting tracking on login: $e');
      }
      return true;
    } else {
      // User cancelled -> Exit the application
      await SystemNavigator.pop();
      return false;
    }
  }
}
