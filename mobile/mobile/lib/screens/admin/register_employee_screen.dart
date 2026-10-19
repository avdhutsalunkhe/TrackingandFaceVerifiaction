import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/responsive_util.dart';
import 'face_enrollment_screen.dart';

class RegisterEmployeeScreen extends StatefulWidget {
  const RegisterEmployeeScreen({Key? key}) : super(key: key);

  @override
  State<RegisterEmployeeScreen> createState() => _RegisterEmployeeScreenState();
}

class _RegisterEmployeeScreenState extends State<RegisterEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _employeeIdController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _initialPasswordController = TextEditingController();
  final _apiClient = ApiClient();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _employeeIdController.dispose();
    _fullNameController.dispose();
    _initialPasswordController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiClient.post(
        ApiConstants.adminUsers,
        body: {
          'employee_id': _employeeIdController.text.trim(),
          'full_name': _fullNameController.text.trim(),
          'initial_password': _initialPasswordController.text.trim().isNotEmpty
              ? _initialPasswordController.text.trim()
              : _employeeIdController.text.trim(),
          'role': 'USER',
          'is_active': true,
        },
      );

      final newUserId = res['id'];
      final employeeId = res['employee_id'];
      final fullName = res['full_name'];

      if (!mounted) return;

      // Ask Admin if they want to proceed straight to face enrollment
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Employee Created!'),
          content: Text(
            'Employee "$fullName" (ID: $employeeId) registered successfully.\n\nWould you like to enroll their biometric face template now?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => FaceEnrollmentScreen(
                      userId: newUserId,
                      employeeId: employeeId,
                      fullName: fullName,
                    ),
                  ),
                );
              },
              child: const Text('Enroll Face Now'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = context.isSmallScreen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Employee'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ResponsiveContainer(
              maxWidth: context.isDesktop ? 700 : 520,
              padding: isSmall
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                  : const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                      ),
                      const SizedBox(height: 18),
                    ],

                    TextFormField(
                      controller: _employeeIdController,
                      decoration: const InputDecoration(
                        labelText: 'Employee ID *',
                        hintText: 'e.g. 2668',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Employee ID is required' : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        hintText: 'e.g. Employee 2668',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Full Name is required' : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _initialPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'Initial Password (Optional)',
                        hintText: 'Defaults to Employee ID if omitted',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleRegister,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: isSmall ? 14 : 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Create Employee Account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
