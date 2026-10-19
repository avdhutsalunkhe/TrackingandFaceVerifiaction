import 'widgets/tracking_consent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/network/api_client.dart';
import 'core/services/auth_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/tracking_service.dart';
import 'core/localization/language_service.dart';
import 'core/localization/app_translations.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/change_password_screen.dart';
import 'screens/user/user_dashboard_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred portrait orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize network client with stored preferences
  await ApiClient().init();

  // Initialize language preference
  await LanguageService.instance.init();

  // Initialize native local notifications & timezone support
  await NotificationService.instance.init();

  // Restore background tracking session if previously active
  await TrackingService.instance.checkAndRestoreSession();

  // Global 401 Session Expiration Handler
  ApiClient.onSessionExpired = () async {
    final authService = AuthService();
    await authService.logout();
    await TrackingService.instance.stopTrackingForPunchOut();
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen(sessionExpired: true)),
      (route) => false,
    );
  };

  runApp(const FieldStaffAttendanceApp());
}

class FieldStaffAttendanceApp extends StatelessWidget {
  const FieldStaffAttendanceApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageService.instance.localeNotifier,
      builder: (context, locale, child) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: AppTranslations.tr('app_title'),
          theme: AppTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          locale: locale,
          home: const SplashScreen(),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  void _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 1000));
    final loggedIn = await _authService.isLoggedIn();

    if (!mounted) return;

    if (!loggedIn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    final profile = await _authService.getUserProfile();
    final role = profile['role'] ?? 'USER';
    final mustChange = profile['must_change_password'] ?? false;

    if (mustChange) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const ChangePasswordScreen(currentPassword: '', isForced: true),
        ),
      );
    } else if (role == 'ADMIN') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      );
    } else {
      final userId = profile['id'] ?? profile['user_id'] ?? 0;
      final empId = profile['employee_id'] ?? '';
      final ok = await TrackingConsentDialog.showAndHandleConsent(
        context,
        userId: userId is int ? userId : int.tryParse(userId.toString()) ?? 0,
        employeeId: empId.toString(),
      );
      if (ok && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const UserDashboardScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.fingerprint_rounded,
                size: 64,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'FieldStaff AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Biometric & Geofence Attendance',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
