import 'dart:math';
import 'package:flutter/material.dart';

enum OvalState { neutral, detected, blinking, success, error }

/// Mathematically calibrated biometric camera oval overlay.
/// Computes exact coordinate transformations between camera preview,
/// device screen aspect ratio, and face crop geometry.
class CameraOvalOverlay extends StatelessWidget {
  final OvalState state;
  final String instruction;
  final double bottomOffset;
  final Size? previewSize;

  const CameraOvalOverlay({
    Key? key,
    this.state = OvalState.neutral,
    this.instruction = "Position your face inside the frame",
    this.bottomOffset = 36.0,
    this.previewSize,
  }) : super(key: key);

  Color get _borderColor {
    switch (state) {
      case OvalState.detected:
        return const Color(0xFF38BDF8); // Electric Sky Cyan
      case OvalState.blinking:
        return const Color(0xFFF59E0B); // Amber / Processing
      case OvalState.success:
        return const Color(0xFF10B981); // Emerald Green
      case OvalState.error:
        return const Color(0xFFEF4444); // Crimson Red
      case OvalState.neutral:
        return Colors.white.withValues(alpha: 0.85);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        // Calibrated human face oval aspect ratio: 1.34 (height = width * 1.34)
        const double faceAspectRatio = 1.34;

        double ovalWidth;
        double ovalHeight;
        double centerY;

        if (previewSize != null && previewSize!.width > 0 && previewSize!.height > 0) {
          // Camera sensor dimensions normalized to portrait
          final double camW = min(previewSize!.width, previewSize!.height);
          final double camH = max(previewSize!.width, previewSize!.height);

          // BoxFit.cover scaling factor
          final double scale = max(screenWidth / camW, screenHeight / camH);
          final double scaledH = camH * scale;
          final double offsetY = (scaledH - screenHeight) / 2.0;

          // Target face region in camera sensor space:
          // Centered horizontally, ~52% of sensor width, positioned slightly above vertical center
          final double targetCamFaceW = camW * 0.52;
          final double targetCamCenterY = camH * 0.46;

          // Project to screen coordinates
          ovalWidth = (targetCamFaceW * scale).clamp(200.0, screenWidth * 0.72);
          ovalHeight = ovalWidth * faceAspectRatio;
          centerY = targetCamCenterY * scale - offsetY;

          // Guard against off-center drift on extreme aspect ratios
          centerY = centerY.clamp(ovalHeight / 2 + 60, screenHeight - ovalHeight / 2 - 120);
        } else {
          // Fallback screen-proportional sizing if preview size is not yet available
          if (screenWidth < 360) {
            ovalWidth = (screenWidth * 0.68).clamp(190.0, 240.0);
          } else if (screenWidth < 600) {
            ovalWidth = (screenWidth * 0.65).clamp(220.0, 280.0);
          } else {
            ovalWidth = (screenWidth * 0.38).clamp(240.0, 320.0);
          }
          ovalHeight = ovalWidth * faceAspectRatio;
          centerY = screenHeight * 0.44;
        }

        // Cap height to ensure ample space for top header and bottom instruction banner
        final double maxAllowedHeight = screenHeight * 0.55;
        if (ovalHeight > maxAllowedHeight) {
          ovalHeight = maxAllowedHeight;
          ovalWidth = ovalHeight / faceAspectRatio;
        }

        final double centerX = screenWidth / 2.0;
        final Rect holeRect = Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: ovalWidth,
          height: ovalHeight,
        );

        final double bannerMaxWidth = min(screenWidth * 0.88, 420.0);
        final double bannerFontSize = screenWidth < 360 ? 13.5 : 15.0;

        return Stack(
          children: [
            // 1. Hardware-accelerated smooth difference cutout (No blend-mode glitches)
            Positioned.fill(
              child: CustomPaint(
                painter: _OvalHolePainter(
                  holeRect: holeRect,
                  overlayColor: Colors.black.withValues(alpha: 0.68),
                ),
              ),
            ),

            // 2. Animated Oval Border & Subtle Scanner Accents
            Positioned.fromRect(
              rect: holeRect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                decoration: BoxDecoration(
                  border: Border.all(color: _borderColor, width: 3.2),
                  borderRadius: BorderRadius.all(
                    Radius.elliptical(ovalWidth / 2, ovalHeight / 2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _borderColor.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),

            // 3. Instruction Text Banner (Clean, anchored above bottom safe margin)
            Positioned(
              bottom: bottomOffset,
              left: 16,
              right: 16,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: bannerMaxWidth),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: _borderColor.withValues(alpha: 0.7), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      instruction,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: bannerFontSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Custom painter that creates a clean, transparent elliptical hole inside a darkened canvas.
/// Uses Path.combine with PathOperation.difference, avoiding conflicting GPU BlendModes.
class _OvalHolePainter extends CustomPainter {
  final Rect holeRect;
  final Color overlayColor;

  _OvalHolePainter({
    required this.holeRect,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final backgroundPath = Path()..addRect(screenRect);
    final holePath = Path()..addOval(holeRect);

    final combinedPath = Path.combine(PathOperation.difference, backgroundPath, holePath);

    final paint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(_OvalHolePainter oldDelegate) {
    return oldDelegate.holeRect != holeRect || oldDelegate.overlayColor != overlayColor;
  }
}
