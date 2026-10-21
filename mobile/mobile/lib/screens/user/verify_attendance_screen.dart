import '../../core/services/notification_service.dart';
import '../../core/services/tracking_service.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/server_time_service.dart';
import '../../widgets/camera_overlay.dart';
import 'send_attendance_request_screen.dart';

enum VerificationStep {
  cameraFaceScan,
  faceMatched,
  faceMismatch,
  checkingLocation,
  locationConfirmed,
  wrongLocation,
  finalSuccess,
  error,
}

class VerifyAttendanceScreen extends StatefulWidget {
  final double currentLatitude;
  final double currentLongitude;
  final double? gpsAccuracy;
  final String locationName;
  final double assignedLatitude;
  final double assignedLongitude;
  final double allowedRadiusMeters;
  final int userId;
  final int activeVerificationNo;
  final int? activeVerificationRuleId;
  final String activeWindowLabel;
  final bool isDeveloperMode;

  const VerifyAttendanceScreen({
    Key? key,
    required this.currentLatitude,
    required this.currentLongitude,
    this.gpsAccuracy,
    required this.locationName,
    this.assignedLatitude = 0.0,
    this.assignedLongitude = 0.0,
    this.allowedRadiusMeters = 150.0,
    this.userId = 0,
    this.activeVerificationNo = 1,
    this.activeVerificationRuleId,
    this.activeWindowLabel = '',
    this.isDeveloperMode = false,
  }) : super(key: key);

  @override
  State<VerifyAttendanceScreen> createState() => _VerifyAttendanceScreenState();
}

class _VerifyAttendanceScreenState extends State<VerifyAttendanceScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _isAutoLoopActive = false;
  int _retryAttempts = 0;

  VerificationStep _currentStep = VerificationStep.cameraFaceScan;
  OvalState _overlayState = OvalState.neutral;
  String _promptInstruction = "Position your face inside the frame.";

  // Final attendance result details
  String _resultTime = '';
  String _resultShift = 'General Shift';
  String _resultStatus = 'On Time';

  // Debug data (available only in Developer Mode)
  double? _debugSimilarity;
  double? _debugDistance;
  String? _debugRejectionReason;
  String? _debugRawMessage;

  final ApiClient _apiClient = ApiClient();
  final ServerTimeService _serverTimeService = ServerTimeService();

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
        _isAutoLoopActive = true;
        _currentStep = VerificationStep.cameraFaceScan;
      });

      // Start automated guided sequence
      _startGuidedSequence();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to initialize camera. Please allow camera permissions.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _startGuidedSequence() async {
    if (!_isAutoLoopActive || !mounted) return;

    setState(() {
      _currentStep = VerificationStep.cameraFaceScan;
      _overlayState = OvalState.neutral;
      _promptInstruction = "Position your face inside the frame.";
    });

    // Fast stabilization delay for front camera auto-exposure and face positioning
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted || !_isAutoLoopActive) return;

    setState(() {
      _overlayState = OvalState.detected;
      _promptInstruction = "Hold still...";
    });

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted || !_isAutoLoopActive) return;

    _captureAndSubmit();
  }

  Future<void> _captureAndSubmit() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _promptInstruction = "Verifying face...";
      _overlayState = OvalState.blinking;
    });

    try {
      // 1. Capture camera frame
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();

      // 2. Generate client idempotency punch ID
      final todayStr = DateFormat('yyyy-MM-dd').format(_serverTimeService.estimatedCurrentServerTime);
      final randomNum = Random().nextInt(999999).toString().padLeft(6, '0');
      final clientPunchId = 'PUNCH_${widget.userId}_${todayStr}_V${widget.activeVerificationNo}_${DateTime.now().millisecondsSinceEpoch}_$randomNum';

      // 3. Check connectivity
      if (!_serverTimeService.isOnline) {
        if (!mounted) return;
        _isAutoLoopActive = false;
        setState(() {
          _currentStep = VerificationStep.error;
          _overlayState = OvalState.error;
        });
        _showOfflineDialog();
        return;
      }

      // Online Verification with frames
      final List<MapEntry<String, Uint8List>> frames = [
        MapEntry('frames', bytes),
      ];

      try {
        if (_cameraController != null && _cameraController!.value.isInitialized) {
          await Future.delayed(const Duration(milliseconds: 120));
          final xFile2 = await _cameraController!.takePicture();
          final bytes2 = await xFile2.readAsBytes();
          frames.add(MapEntry('frames', bytes2));
        }
      } catch (_) {}

      final requestId = 'REQ_${DateTime.now().millisecondsSinceEpoch}';
      final res = await _apiClient.postMultipart(
        endpoint: ApiConstants.verifyAttendance,
        fields: {
          'current_latitude': widget.currentLatitude.toString(),
          'current_longitude': widget.currentLongitude.toString(),
          'gps_accuracy': (widget.gpsAccuracy ?? 10.0).toString(),
          'device_id': 'MOBILE_APP_CLIENT',
          'request_id': requestId,
          'client_punch_id': clientPunchId,
          'verification_no': widget.activeVerificationNo.toString(),
          if (widget.activeVerificationRuleId != null)
            'verification_rule_id': widget.activeVerificationRuleId.toString(),
          'device_wall_time': DateTime.now().toIso8601String(),
        },
        files: frames,
      );

      final bool isSuccess = res['success'] ?? false;
      final String reason = res['rejection_reason'] ?? '';
      final String message = res['message'] ?? '';
      final simScore = res['face_similarity_score'];
      final distance = res['calculated_distance_meters'];
      final shiftName = res['shift_name'] ?? 'General Shift';
      final classification = res['attendance_classification'] ?? 'ON_TIME';

      // Cache debug data
      _debugSimilarity = simScore != null ? (simScore as num).toDouble() : null;
      _debugDistance = distance != null ? (distance as num).toDouble() : null;
      _debugRejectionReason = reason;
      _debugRawMessage = message;

      if (!mounted) return;

      // Transient blur auto-retry
      if (!isSuccess &&
          (reason == "CAPTURE_NOT_READY" || reason == "FACE_NOT_DETECTED" || reason == "FACE_QUALITY_FAILED") &&
          _retryAttempts < 2) {
        _retryAttempts++;
        setState(() {
          _overlayState = OvalState.neutral;
          _promptInstruction = "Center face & hold still...";
        });
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted && _isAutoLoopActive) {
          _captureAndSubmit();
        }
        return;
      }

      _isAutoLoopActive = false;

      // Handle Outcomes according to Section 8, 9, 10
      if (isSuccess) {
        await _handleSuccessfulFlow(shiftName: shiftName, classification: classification);
      } else {
        final isGeofenceError = reason.contains('GEOFENCE') || reason.contains('LOCATION') || reason == 'OUTSIDE_GEOFENCE';
        if (isGeofenceError) {
          // Face matched, but location is wrong
          await _handleWrongLocationFlow();
        } else {
          // Face mismatch or failure
          _handleFaceMismatchFlow();
        }
      }
    } catch (e) {
      if (!mounted) return;
      _isAutoLoopActive = false;
      setState(() {
        _currentStep = VerificationStep.error;
        _overlayState = OvalState.error;
      });
      _showGenericErrorDialog();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Step 1 Success (Face Match) -> Step 2 Success (Location Confirmed) -> Step 3 (Attendance Recorded)
  Future<void> _handleSuccessfulFlow({
    required String shiftName,
    required String classification,
  }) async {
    // 1. Step 1: Face Match ✓
    setState(() {
      _currentStep = VerificationStep.faceMatched;
      _overlayState = OvalState.success;
      _promptInstruction = "Face Match ✓";
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    // 2. Step 2: Location Verification
    setState(() {
      _currentStep = VerificationStep.checkingLocation;
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    setState(() {
      _currentStep = VerificationStep.locationConfirmed;
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    // 3. Final Attendance Result
    final now = _serverTimeService.estimatedCurrentServerTime;
    final timeStr = DateFormat('hh:mm a').format(now);
    final statusStr = classification == 'ON_TIME' ? 'On Time' : 'Late';

    setState(() {
      _currentStep = VerificationStep.finalSuccess;
      _resultTime = timeStr;
      _resultShift = shiftName;
      _resultStatus = statusStr;
    });

    // Attendance verification successfully recorded
    await NotificationService.instance.notifyPunchSuccess(
      title: widget.activeVerificationNo == 1
          ? 'Punch-In Successful'
          : 'Verification #${widget.activeVerificationNo} Recorded',
      message: 'Attendance recorded successfully at $timeStr ($statusStr).',
    );

    // Automatically ensure journey tracking is running for duty hours
    if (!TrackingService.instance.isTracking && widget.userId > 0) {
      try {
        await TrackingService.instance.startTrackingForPunchIn(
          userId: widget.userId,
          attendanceDate: DateFormat('yyyy-MM-dd').format(now),
          startLat: widget.currentLatitude,
          startLng: widget.currentLongitude,
        );
      } catch (e) {
        debugPrint('[VerifyAttendanceScreen] Auto-start tracking on punch: $e');
      }
    }

    _showFinalSuccessDialog();
  }

  /// Face match succeeded, but location is wrong
  Future<void> _handleWrongLocationFlow() async {
    // Show face matched briefly first
    setState(() {
      _currentStep = VerificationStep.faceMatched;
      _overlayState = OvalState.success;
      _promptInstruction = "Face Match ✓";
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    setState(() {
      _currentStep = VerificationStep.wrongLocation;
      _overlayState = OvalState.error;
    });

    _showWrongLocationDialog();
  }

  /// Face mismatch or quality failure
  void _handleFaceMismatchFlow() {
    setState(() {
      _currentStep = VerificationStep.faceMismatch;
      _overlayState = OvalState.error;
      _promptInstruction = "Face Mismatch ✕";
    });

    _showFaceMismatchDialog();
  }

  /// Dialog: Face Mismatch ✕
  void _showFaceMismatchDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: Color(0xFFDC2626), size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Face Mismatch ✕',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF991B1B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please position your face clearly and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            if (widget.isDeveloperMode) ...[
              const SizedBox(height: 12),
              _buildDebugSection(),
            ],
          ],
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _retryAttempts = 0;
                  setState(() {
                    _isAutoLoopActive = true;
                    _currentStep = VerificationStep.cameraFaceScan;
                  });
                  _startGuidedSequence();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'TRY AGAIN',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SendAttendanceRequestScreen(
                        initialLatitude: widget.currentLatitude,
                        initialLongitude: widget.currentLongitude,
                        initialAccuracy: widget.gpsAccuracy,
                        initialLocationName: widget.locationName,
                        verificationNo: widget.activeVerificationNo,
                        reason: 'Face verification issue',
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Trouble verifying? Submit Attendance Request',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dialog: Wrong Location ✕
  void _showWrongLocationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_off_rounded, color: Color(0xFFDC2626), size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Wrong Location ✕',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF991B1B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Move to your assigned work location and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            if (widget.isDeveloperMode) ...[
              const SizedBox(height: 12),
              _buildDebugSection(),
            ],
          ],
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _retryAttempts = 0;
                  setState(() {
                    _isAutoLoopActive = true;
                    _currentStep = VerificationStep.cameraFaceScan;
                  });
                  _startGuidedSequence();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'TRY AGAIN',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SendAttendanceRequestScreen(
                        initialLatitude: widget.currentLatitude,
                        initialLongitude: widget.currentLongitude,
                        initialAccuracy: widget.gpsAccuracy,
                        initialLocationName: widget.locationName,
                        verificationNo: widget.activeVerificationNo,
                        reason: 'Location verification issue',
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Trouble verifying? Submit Attendance Request',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dialog: Final Attendance Success (Section 10)
  void _showFinalSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFECFDF5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'Attendance Recorded ✓',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF065F46),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your attendance has been successfully marked.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),

            // Summary Card: Time, Shift, Status
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildSummaryRow('Time:', _resultTime),
                  const Divider(height: 16),
                  _buildSummaryRow('Shift:', _resultShift),
                  const Divider(height: 16),
                  _buildSummaryRow('Status:', _resultStatus, isHighlight: true),
                ],
              ),
            ),

            if (widget.isDeveloperMode) ...[
              const SizedBox(height: 12),
              _buildDebugSection(),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context); // Return to Dashboard
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'DONE',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isHighlight ? const Color(0xFF059669) : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// Dialog: Offline / Server Issue (Section 12)
  void _showOfflineDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_off_rounded, color: Color(0xFFDC2626), size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Attendance verification unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
            ),
            const SizedBox(height: 8),
            const Text(
              'The attendance service is temporarily unavailable. Please try again when the service is available.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Back to Home'),
            ),
          ),
        ],
      ),
    );
  }

  /// Dialog: Generic Error (Section 11)
  void _showGenericErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Unable to verify attendance',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _isAutoLoopActive = true;
                _currentStep = VerificationStep.cameraFaceScan;
              });
              _startGuidedSequence();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('TRY AGAIN'),
          ),
        ],
      ),
    );
  }

  /// Developer / Test info (ONLY rendered if Developer Mode is active)
  Widget _buildDebugSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DEVELOPER / TEST INFO', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (_debugSimilarity != null)
            Text('Similarity: ${(_debugSimilarity! * 100).toStringAsFixed(2)}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace')),
          if (_debugDistance != null)
            Text('Distance: ${_debugDistance!.toStringAsFixed(1)}m / Radius: ${widget.allowedRadiusMeters}m', style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace')),
          Text('GPS: ${widget.currentLatitude}, ${widget.currentLongitude}', style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace')),
          if (_debugRejectionReason != null && _debugRejectionReason!.isNotEmpty)
            Text('Code: $_debugRejectionReason', style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 10, fontFamily: 'monospace')),
          if (_debugRawMessage != null && _debugRawMessage!.isNotEmpty)
            Text('Msg: $_debugRawMessage', style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isAutoLoopActive = false;
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Camera Preview
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
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // 2. Step 1 Top Header: "Verify Your Face" & Subtitle (Section 8)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          widget.activeWindowLabel.isNotEmpty ? widget.activeWindowLabel : 'Attendance Verification',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Column(
                      children: [
                        Text(
                          'Verify Your Face',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Position your face inside the frame.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 3. Oval Guide Overlay
            CameraOvalOverlay(
              state: _overlayState,
              instruction: _promptInstruction,
              previewSize: _cameraController?.value.previewSize,
            ),

            // 4. Step 2 Overlay: "Checking your work location..." (Section 9)
            if (_currentStep == VerificationStep.checkingLocation || _currentStep == VerificationStep.locationConfirmed)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.85),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_currentStep == VerificationStep.checkingLocation) ...[
                            const SizedBox(
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Checking your work location...',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ] else ...[
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'Location Confirmed ✓',
                              style: TextStyle(color: Color(0xFF10B981), fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'You are at the assigned attendance location.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70, fontSize: 13),
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
