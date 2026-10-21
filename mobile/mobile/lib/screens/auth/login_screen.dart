import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/tracking_service.dart';
import '../../core/utils/responsive_util.dart';
import '../../core/localization/app_translations.dart';
import '../../widgets/language_selector.dart';
import '../../network/api_client.dart';
import '../../core/services/device_service.dart';
import 'package:flutter/foundation.dart';
import 'change_password_screen.dart';
import '../user/user_dashboard_screen.dart';
import '../admin/admin_dashboard_screen.dart';
import '../admin/admin_face_registration_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool sessionExpired;
  const LoginScreen({Key? key, this.sessionExpired = false}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _employeeIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
    // Proactively ping candidate servers so live server is active when user attempts login
    ApiClient().failoverManager.pingAndDiscoverServer();
    if (widget.sessionExpired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your session has expired. Please log in again.'),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 4),
          ),
        );
      });
    }
  }

  Future<void> _loadDeviceId() async {
    try {
      final id = await DeviceService.instance.getDeviceId();
      if (mounted) setState(() => _deviceId = id);
    } catch (_) {}
  }


  @override
  void dispose() {
    _employeeIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _authService.login(
        _employeeIdController.text.trim(),
        _passwordController.text.trim(),
      );

      final role = res['role'] ?? 'USER';
      final mustChange = res['must_change_password'] ?? false;

      if (!mounted) return;

      if (mustChange) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChangePasswordScreen(
              currentPassword: _passwordController.text.trim(),
            ),
          ),
        );
      } else {
        if (role == 'ADMIN') {
          final isMobileView = !kIsWeb || (MediaQuery.of(context).size.width < 800);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => isMobileView
                  ? const AdminFaceRegistrationScreen()
                  : const AdminDashboardScreen(),
            ),
          );
        } else {
          final userId = res['user_id'] ?? 0;
          final empId = res['employee_id'] ?? _employeeIdController.text.trim();
          final uid = userId is int ? userId : int.tryParse(userId.toString()) ?? 0;

          // Automatically initialize and schedule background GPS tracking
          TrackingService.instance.initializeAutomaticDailyTracking(
            userId: uid,
            employeeId: empId.toString(),
          );

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const UserDashboardScreen()),
            );
          }
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final isSmall = context.isSmallScreen;
    final double logoSize = isSmall ? 64 : 80;
    final double titleSize = isSmall ? 22 : 26;
    final double spacing = isSmall ? 14 : 22;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              right: 16,
              child: const LanguageSelectorPill(isDarkBackground: false),
            ),
            Center(
              child: SingleChildScrollView(
                child: ResponsiveContainer(
                  maxWidth: 460,
                  padding: isSmall
                      ? const EdgeInsets.symmetric(horizontal: 18, vertical: 12)
                      : const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 10),
                        // Logo / Header Icon
                        Center(
                          child: Container(
                            width: logoSize,
                            height: logoSize,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(isSmall ? 18 : 24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 15,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(isSmall ? 18 : 24),
                              child: Image.asset(
                                'assets/branding/fieldtrack_app_icon.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: spacing),

                        Text(
                          AppTranslations.tr('app_title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppTranslations.tr('app_subtitle'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isSmall ? 12 : 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(height: isSmall ? 18 : 30),

                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: AppColors.error, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: spacing),
                        ],

                        // Employee ID
                        TextFormField(
                          controller: _employeeIdController,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            labelText: AppTranslations.tr('employee_id'),
                            prefixIcon: const Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? AppTranslations.tr('please_enter_emp_id') : null,
                        ),
                        SizedBox(height: isSmall ? 12 : 18),

                        // Password
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: AppTranslations.tr('password'),
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? AppTranslations.tr('please_enter_password') : null,
                        ),
                        SizedBox(height: isSmall ? 18 : 26),

                        // Login Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: isSmall ? 14 : 16),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : Text(AppTranslations.tr('sign_in'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),

                        // Pre-login Device ID Registration Info
                        if (_deviceId != null) ...[
                          SizedBox(height: isSmall ? 16 : 22),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.phonelink_setup_rounded, size: 16, color: Color(0xFF64748B)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'DEVICE ID (For Registration)',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      Text(
                                        _deviceId!,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontFamily: 'monospace',
                                          color: Color(0xFF1E293B),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
                                  tooltip: 'Copy Device ID',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  onPressed: () => DeviceService.instance.copyDeviceId(context),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
