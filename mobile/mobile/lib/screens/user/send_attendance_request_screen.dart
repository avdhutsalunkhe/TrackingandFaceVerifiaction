import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/services/location_service.dart';
import '../../core/services/server_time_service.dart';
import '../../core/utils/responsive_util.dart';

class SendAttendanceRequestScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final double? initialAccuracy;
  final String? initialLocationName;
  final String? reason;
  final int? verificationNo;

  const SendAttendanceRequestScreen({
    Key? key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAccuracy,
    this.initialLocationName,
    this.reason,
    this.verificationNo,
  }) : super(key: key);

  @override
  State<SendAttendanceRequestScreen> createState() => _SendAttendanceRequestScreenState();
}

class _SendAttendanceRequestScreenState extends State<SendAttendanceRequestScreen> {
  final ApiClient _apiClient = ApiClient();
  final ServerTimeService _serverTimeService = ServerTimeService();

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraReady = false;
  bool _isSubmitting = false;

  double? _latitude;
  double? _longitude;
  double? _accuracy;
  String _locationName = "Acquiring location...";
  bool _isLoadingLocation = true;

  Uint8List? _rawImageBytes;
  Uint8List? _capturedImageBytes;
  bool _isPreviewing = false;
  String? _clientRequestId;

  @override
  void initState() {
    super.initState();
    _clientRequestId = 'req_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
    _serverTimeService.init();
    _initCamera();
    _resolveLocation();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      final frontCam = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        frontCam,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _resolveLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      if (widget.initialLatitude != null && widget.initialLongitude != null) {
        _latitude = widget.initialLatitude;
        _longitude = widget.initialLongitude;
        _accuracy = widget.initialAccuracy ?? 10.0;
      } else {
        final pos = await LocationService.getCurrentPosition();
        if (pos != null) {
          _latitude = pos.latitude;
          _longitude = pos.longitude;
          _accuracy = pos.accuracy;
        }
      }

      if (_latitude != null && _longitude != null) {
        // Reverse geocoding lookup with fallback to assigned location name
        String locName = widget.initialLocationName ?? "Work Site";
        try {
          final url = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=$_latitude&lon=$_longitude&zoom=18&addressdetails=1',
          );
          final resp = await http.get(url, headers: {'User-Agent': 'FieldStaffAttendanceApp/1.0'}).timeout(
            const Duration(seconds: 4),
          );
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            final disp = data['display_name'];
            if (disp != null && disp.toString().isNotEmpty) {
              final parts = disp.toString().split(',');
              if (parts.length >= 2) {
                locName = '${parts[0].trim()}, ${parts[1].trim()}';
              } else {
                locName = disp.toString();
              }
            }
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _locationName = locName;
            _isLoadingLocation = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _locationName = widget.initialLocationName ?? "Unknown Location";
            _isLoadingLocation = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationName = widget.initialLocationName ?? "Location Unavailable";
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<Uint8List> _burnEvidenceOverlay({
    required Uint8List rawBytes,
    required String locationName,
    required double? lat,
    required double? lon,
    required String dateStr,
    required String timeStr,
  }) async {
    final codec = await ui.instantiateImageCodec(rawBytes);
    final frameInfo = await codec.getNextFrame();
    final img = frameInfo.image;
    final width = img.width.toDouble();
    final height = img.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // Draw camera image
    canvas.drawImage(img, Offset.zero, Paint());

    final bool hasValidGps = lat != null &&
        lon != null &&
        !(lat == 0.0 && lon == 0.0) &&
        lat.abs() <= 90.0 &&
        lon.abs() <= 180.0;

    final latStr = hasValidGps ? lat.toStringAsFixed(6) : 'Unavailable';
    final lonStr = hasValidGps ? lon.toStringAsFixed(6) : 'Unavailable';

    final lines = [
      'Location: $locationName',
      'Lat: $latStr',
      'Long: $lonStr',
      'Date: $dateStr',
      'Time: $timeStr',
    ];

    final fontSize = (width * 0.032).clamp(16.0, 36.0);
    final lineSpans = <TextSpan>[];
    for (final line in lines) {
      lineSpans.add(
        TextSpan(
          text: '$line\n',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
            shadows: const [
              Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
            ],
          ),
        ),
      );
    }

    final textPainter = TextPainter(
      text: TextSpan(children: lineSpans),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: width * 0.85);

    final padding = fontSize * 0.6;
    final boxW = textPainter.width + (padding * 2);
    final boxH = textPainter.height + (padding * 1.5);
    final boxX = padding;
    final boxY = height - boxH - padding;

    // High-contrast translucent dark backdrop
    final bgPaint = Paint()..color = const Color(0xDD000000);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(boxX, boxY, boxW, boxH), const Radius.circular(10)),
      bgPaint,
    );

    // Cyan/Primary accent border
    final borderPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(boxX, boxY, boxW, boxH), const Radius.circular(10)),
      borderPaint,
    );

    // Paint text inside box
    textPainter.paint(canvas, Offset(boxX + padding, boxY + (padding * 0.7)));

    final picture = recorder.endRecording();
    final outputImg = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await outputImg.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _handleCapture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      final xfile = await _cameraController!.takePicture();
      final rawBytes = await xfile.readAsBytes();

      final dateStr = _serverTimeService.formattedDate;
      final timeStr = _serverTimeService.formattedTime;

      // Burn the bottom-left evidence overlay onto image
      final overlaidBytes = await _burnEvidenceOverlay(
        rawBytes: rawBytes,
        locationName: _locationName,
        lat: _latitude,
        lon: _longitude,
        dateStr: dateStr,
        timeStr: timeStr,
      );

      setState(() {
        _rawImageBytes = rawBytes;
        _capturedImageBytes = overlaidBytes;
        _isPreviewing = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture selfie: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _handleRetake() {
    setState(() {
      _rawImageBytes = null;
      _capturedImageBytes = null;
      _isPreviewing = false;
    });
  }

  Future<void> _handleSubmitRequest() async {
    if (_capturedImageBytes == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final bool hasValidGps = _latitude != null &&
          _longitude != null &&
          !(_latitude == 0.0 && _longitude == 0.0) &&
          _latitude!.abs() <= 90.0 &&
          _longitude!.abs() <= 180.0;

      final nowDevice = DateTime.now().toIso8601String();

      final res = await _apiClient.postMultipart(
        endpoint: ApiConstants.submitAttendanceRequest,
        fields: {
          'latitude': hasValidGps ? _latitude.toString() : '0.0',
          'longitude': hasValidGps ? _longitude.toString() : '0.0',
          'location_name': _locationName,
          if (hasValidGps && _accuracy != null) 'accuracy': _accuracy.toString(),
          'device_timestamp': nowDevice,
          'reason': widget.reason ?? 'Face verification failed',
          if (widget.verificationNo != null)
            'verification_no': widget.verificationNo.toString(),
          if (_clientRequestId != null)
            'client_request_id': _clientRequestId!,
        },
        files: [
          MapEntry('selfie', _rawImageBytes ?? _capturedImageBytes!),
        ],
      );

      if (!mounted) return;

      final reqId = res['id'];
      final shiftName = res['shift_name'] ?? 'Assigned Shift';
      final sDate = res['server_formatted_date'] ?? '';
      final sTime = res['server_formatted_time'] ?? '';

      // Success Dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: const [
              Icon(Icons.mark_email_read_rounded, color: AppColors.primary, size: 56),
              SizedBox(height: 12),
              Text(
                'Request Submitted',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your attendance request with live selfie evidence has been sent to Admin for review.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Request ID:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            Text('#$reqId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Server Time:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            Text('$sDate $sTime', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Shift:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            Text(shiftName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Status:', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PENDING REVIEW',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFB45309)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx); // pop dialog
                  Navigator.pop(context, true); // return to dashboard
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Back to Dashboard'),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Send Attendance Request',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 680,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // Top Live Server Time & Authoritative Banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: AppColors.secondary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SERVER TIME (AUTHORITATIVE)',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          ValueListenableBuilder<DateTime>(
                            valueListenable: _serverTimeService.timeNotifier,
                            builder: (_, __, ___) {
                              return Text(
                                '${_serverTimeService.formattedDate} • ${_serverTimeService.formattedTime}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '3s SYNC',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // Camera / Image Preview Area
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                    color: Colors.grey[900],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_isPreviewing && _capturedImageBytes != null)
                        Image.memory(_capturedImageBytes!, fit: BoxFit.cover)
                      else if (_isCameraReady && _cameraController != null)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _cameraController!.value.previewSize?.height ?? 100,
                            height: _cameraController!.value.previewSize?.width ?? 100,
                            child: CameraPreview(_cameraController!),
                          ),
                        )
                      else
                        const Center(child: CircularProgressIndicator(color: Colors.white)),

                      // Live Bottom-Left Evidence Overlay (only when camera is live)
                      if (!_isPreviewing)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, color: AppColors.secondary, size: 16),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Location: $_locationName',
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Builder(
                                  builder: (_) {
                                    final bool hasValidGps = _latitude != null &&
                                        _longitude != null &&
                                        !(_latitude == 0.0 && _longitude == 0.0) &&
                                        _latitude!.abs() <= 90.0 &&
                                        _longitude!.abs() <= 180.0;

                                    if (_isLoadingLocation) {
                                      return const Row(
                                        children: [
                                          SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFBBF24)),
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Acquiring GPS fix...',
                                            style: TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      );
                                    } else if (hasValidGps) {
                                      return Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            'GPS Confirmed (±${_accuracy != null ? _accuracy!.toStringAsFixed(1) : "10"} m)',
                                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      );
                                    } else {
                                      return const Row(
                                        children: [
                                          Icon(Icons.warning_amber_rounded, color: Color(0xFFF97316), size: 14),
                                          SizedBox(width: 4),
                                          Text(
                                            'GPS Unavailable (Assistance Mode)',
                                            style: TextStyle(color: Color(0xFFF97316), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 2),
                                ValueListenableBuilder<DateTime>(
                                  valueListenable: _serverTimeService.timeNotifier,
                                  builder: (_, __, ___) {
                                    return Text(
                                      'Date: ${_serverTimeService.formattedDate}   Time: ${_serverTimeService.formattedTime}',
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: _isPreviewing
                    ? (context.isSmallScreen
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _isSubmitting ? null : _handleRetake,
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                                label: const Text('Retake Selfie', style: TextStyle(color: Colors.white)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white60),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: _isSubmitting ? null : _handleSubmitRequest,
                                icon: _isSubmitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Icon(Icons.send_rounded),
                                label: Text(
                                  _isSubmitting ? 'Submitting...' : 'Submit Request',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isSubmitting ? null : _handleRetake,
                                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                                  label: const Text('Retake Selfie', style: TextStyle(color: Colors.white)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.white60),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isSubmitting ? null : _handleSubmitRequest,
                                  icon: _isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Icon(Icons.send_rounded),
                                  label: Text(
                                    _isSubmitting ? 'Submitting...' : 'Submit Request',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ))
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_isCameraReady && !_isLoadingLocation) ? _handleCapture : null,
                          icon: const Icon(Icons.camera_alt_rounded, size: 24),
                          label: const Text(
                            'CAPTURE EVIDENCE SELFIE',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
