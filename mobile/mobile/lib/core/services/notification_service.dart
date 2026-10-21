import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'tracking_database.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  final StreamController<int> _unreadCountController = StreamController<int>.broadcast();
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  static const String channelId = 'fieldstaff_attendance_channel';
  static const String channelName = 'FieldStaff Attendance & Tracking';
  static const String channelDesc = 'Notifications for attendance punch status, journey tracking, and shift alerts.';

  Future<void> init() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      _isInitialized = true;
      await refreshUnreadCount();
      return;
    }

    try {
      tz.initializeTimeZones();
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (e) {
      debugPrint('[NotificationService] Timezone init fallback: $e');
    }

    const androidSettings = AndroidInitializationSettings('@drawable/ic_stat_fieldtrack');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('[NotificationService] Notification tapped: ${response.payload}');
      },
    );

    // Request permissions for Android 13+
    await requestPermissions();

    _isInitialized = true;
    await refreshUnreadCount();
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;
    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      final granted = await androidImplementation.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  /// Helper to notify punch success
  Future<void> notifyPunchSuccess({
    required String title,
    required String message,
    String category = 'ATTENDANCE',
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: message,
      category: category,
    );
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String category = 'ATTENDANCE',
  }) async {
    if (!kIsWeb) {
      const androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_stat_fieldtrack',
        showWhen: true,
      );

      try {
        await _notificationsPlugin.show(
          id,
          title,
          body,
          const NotificationDetails(android: androidDetails),
          payload: payload,
        );
      } catch (e) {
        debugPrint('[NotificationService] Error showing notification: $e');
      }
    }

    // Save to In-App Notification Center
    await TrackingDatabase.instance.insertNotification(title, body, category: category);
    await refreshUnreadCount();
  }

  Future<void> refreshUnreadCount() async {
    final count = await TrackingDatabase.instance.getUnreadNotificationCount();
    _unreadCountController.add(count);
  }
}
