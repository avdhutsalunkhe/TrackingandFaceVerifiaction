import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../widgets/camera_overlay.dart';

class FaceEnrollmentScreen extends StatefulWidget {
  final int userId;
  final String employeeId;
  final String fullName;

  const FaceEnrollmentScreen({
    Key? key,
    required this.userId,
    required this.employeeId,
    required this.fullName,
  }) : super(key: key);

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isAutoLoopRunning = false;

  final int _totalSamplesRequired = 3;
  int _validatedSamplesCount = 0; // 0, 1, 2, 3

  String _statusMessage = "Detecting face...";
  OvalState _ovalState = OvalState.neutral;

  final ApiClient _apiClient = ApiClient();

  @override
  void initState() {
    super.initState();
    _initFrontCamera();
  }

  Future<void> _initFrontCamera() async {
    try {
      _cameras = await availableCameras();
      final frontCam = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        frontCam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      try {
        await _cameraController!.setExposureMode(ExposureMode.auto);
        await _cameraController!.setFocusMode(FocusMode.auto);
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _isCameraReady = true;
      });

      // Start the master enrollment loop
      _runAutoEnrollmentSequence();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _runAutoEnrollmentSequence() async {
    if (_isAutoLoopRunning) return;
    _isAutoLoopRunning = true;

    // Fast warm-up for front camera auto-exposure to stabilize
    await Future.delayed(const Duration(milliseconds: 300));

    while (mounted && _isAutoLoopRunning && _validatedSamplesCount < _totalSamplesRequired) {
      final targetIndex = _validatedSamplesCount + 1;

      if (mounted) {
        setState(() {
          _statusMessage = "Hold still for sample $targetIndex of 3...";
          _ovalState = OvalState.detected;
        });
      }

      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted || !_isAutoLoopRunning) break;

      // Execute single capture
      final bool success = await _executeSingleCapture(targetIndex);

      if (success) {
        if (mounted) {
          setState(() {
            _statusMessage = "Sample $targetIndex captured ✓";
            _ovalState = OvalState.success;
          });
        }
        // Brief pause after successful capture before next sample
        await Future.delayed(const Duration(milliseconds: 350));
      } else {
        // Quality issue / transient fail: wait briefly before retrying
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    if (mounted && _validatedSamplesCount >= _totalSamplesRequired) {
      setState(() {
        _statusMessage = "Face registration complete ✓";
        _ovalState = OvalState.success;
      });
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _showSuccessDialog();
    }

    _isAutoLoopRunning = false;
  }

  Future<bool> _executeSingleCapture(int sampleIndex) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isCapturing) {
      return false;
    }

    if (mounted) {
      setState(() {
        _isCapturing = true;
        _statusMessage = "Validating sample $sampleIndex...";
        _ovalState = OvalState.blinking;
      });
    }

    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();

      // Send to server
      final res = await _apiClient.postMultipart(
        endpoint: ApiConstants.adminUserFace(widget.userId),
        fields: {
          'sample_index': sampleIndex.toString(),
        },
        files: [MapEntry('image', bytes)],
      );

      final isValid = res['is_valid'] ?? false;
      if (!isValid) {
        throw Exception(res['message'] ?? 'Sample validation failed');
      }

      // Increment validated counter upon confirmed server 200 OK
      if (mounted) {
        setState(() {
          _validatedSamplesCount = sampleIndex;
        });
      }
      return true;
    } catch (e) {
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      final isResetError = errMsg.contains('Face registration validation failed') || errMsg.contains('inconsistent samples');

      if (mounted) {
        setState(() {
          if (isResetError) {
            _validatedSamplesCount = 0; // Synchronize with backend sample reset
            _statusMessage = "Biometric mismatch across samples. Restarting enrollment...";
          } else {
            _statusMessage = errMsg;
          }
          _ovalState = OvalState.error;
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _manualCaptureTrigger() async {
    if (_isCapturing || _validatedSamplesCount >= _totalSamplesRequired) return;
    final targetIndex = _validatedSamplesCount + 1;
    final success = await _executeSingleCapture(targetIndex);
    if (success && _validatedSamplesCount < _totalSamplesRequired) {
      // Continue auto loop
      if (!_isAutoLoopRunning) {
        _runAutoEnrollmentSequence();
      }
    } else if (_validatedSamplesCount >= _totalSamplesRequired && mounted) {
      setState(() {
        _statusMessage = "Face registration complete ✓";
        _ovalState = OvalState.success;
      });
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.verified_user_rounded, color: AppColors.success, size: 30),
            SizedBox(width: 10),
            Text('Registration Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Face biometric profile for "${widget.fullName}" (ID: ${widget.employeeId}) has been successfully enrolled.',
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '3/3 Samples Enrolled • Same-Face Self-Test Verified ✓',
                      style: TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isAutoLoopRunning = false;
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nextSampleNum = _validatedSamplesCount + 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Enroll Face: ${widget.employeeId}'),
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Live Camera Preview
            if (_isCameraReady && _cameraController != null)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize?.height ?? 100,
                    height: _cameraController!.value.previewSize?.width ?? 100,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),

            // Oval Guide Overlay
            CameraOvalOverlay(
              state: _ovalState,
              instruction: _statusMessage,
              bottomOffset: 92.0,
              previewSize: _cameraController?.value.previewSize,
            ),

            // Top Sample Progress Counter Banner
            Positioned(
              top: 14,
              left: 16,
              right: 16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.80),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primaryLight.withOpacity(0.5)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'Sample $_validatedSamplesCount of $_totalSamplesRequired Validated',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${((_validatedSamplesCount / _totalSamplesRequired) * 100).toInt()}%',
                              style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: _validatedSamplesCount / _totalSamplesRequired,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryLight),
                          minHeight: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Manual Capture / Progress Bar
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: ElevatedButton.icon(
                    onPressed: _isCapturing ? null : _manualCaptureTrigger,
                    icon: _isCapturing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_rounded, size: 20),
                    label: Text(
                      _isCapturing
                          ? "Processing Sample $nextSampleNum..."
                          : (_validatedSamplesCount >= _totalSamplesRequired
                              ? "Registration Complete ✓"
                              : "Capture Sample $nextSampleNum of 3"),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
