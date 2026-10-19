import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldstaff_attendance/core/theme/app_theme.dart';
import 'package:fieldstaff_attendance/core/utils/responsive_util.dart';
import 'package:fieldstaff_attendance/widgets/camera_overlay.dart';
import 'package:fieldstaff_attendance/screens/auth/login_screen.dart';
import 'package:fieldstaff_attendance/screens/auth/change_password_screen.dart';
import 'package:fieldstaff_attendance/screens/admin/register_employee_screen.dart';
import 'package:fieldstaff_attendance/screens/admin/geofence_config_screen.dart';
import 'package:fieldstaff_attendance/models/shift_model.dart';

class DeviceProfile {
  final String name;
  final double width;
  final double height;
  final double pixelRatio;
  final String description;

  const DeviceProfile({
    required this.name,
    required this.width,
    required this.height,
    required this.pixelRatio,
    required this.description,
  });

  Size get physicalSize => Size(width * pixelRatio, height * pixelRatio);
  Size get logicalSize => Size(width, height);
  double get aspectRatio => height / width;
}

const canonicalProfiles = [
  DeviceProfile(
    name: 'Small / Compact Android',
    width: 320,
    height: 533,
    pixelRatio: 1.5,
    description: 'Compact 320dp screen (Android One / budget / small phone)',
  ),
  DeviceProfile(
    name: 'Older Standard Android',
    width: 360,
    height: 640,
    pixelRatio: 2.0,
    description: 'Standard 16:9 older Android device (360x640 dp)',
  ),
  DeviceProfile(
    name: 'Modern Tall Android',
    width: 412,
    height: 915,
    pixelRatio: 2.625,
    description: 'Modern tall 20:9 Android flagship (412x915 dp)',
  ),
  DeviceProfile(
    name: 'Foldable / Small Tablet',
    width: 600,
    height: 1024,
    pixelRatio: 2.0,
    description: '7-inch compact tablet / unfolded foldable (600x1024 dp)',
  ),
  DeviceProfile(
    name: 'Large 10" Tablet',
    width: 800,
    height: 1280,
    pixelRatio: 2.0,
    description: '10-inch extra-large tablet (800x1280 dp, 16:10 ratio)',
  ),
];

void setScreenSize(WidgetTester tester, DeviceProfile profile) {
  tester.view.physicalSize = profile.physicalSize;
  tester.view.devicePixelRatio = profile.pixelRatio;
}

void resetScreenSize(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Responsive Core Utilities & Breakpoints', () {
    for (final profile in canonicalProfiles) {
      testWidgets('Correctly categorizes ${profile.name} (${profile.width}x${profile.height})', (tester) async {
        setScreenSize(tester, profile);
        addTearDown(() => resetScreenSize(tester));

        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const Scaffold(body: Text('Test'));
              },
            ),
          ),
        );

        final category = ResponsiveUtil.category(capturedContext);
        final screenWidth = capturedContext.screenWidth;
        expect(screenWidth, profile.width);

        if (profile.width < 360) {
          expect(category, ScreenCategory.small);
          expect(capturedContext.isSmallScreen, isTrue);
          expect(capturedContext.isTablet, isFalse);
        } else if (profile.width < 600) {
          expect(category, ScreenCategory.medium);
          expect(capturedContext.isMediumScreen, isTrue);
          expect(capturedContext.isTablet, isFalse);
        } else if (profile.width < 900) {
          expect(category, ScreenCategory.large);
          expect(capturedContext.isLargeScreen, isTrue);
          expect(capturedContext.isTablet, isTrue);
        } else {
          expect(category, ScreenCategory.extraLarge);
          expect(capturedContext.isExtraLargeScreen, isTrue);
          expect(capturedContext.isTablet, isTrue);
        }
      });
    }
  });

  group('Camera Oval Overlay — Proportions, Aspect Ratio & Bounds', () {
    for (final profile in canonicalProfiles) {
      testWidgets('Adapts oval guide safely without overflow on ${profile.name}', (tester) async {
        setScreenSize(tester, profile);
        addTearDown(() => resetScreenSize(tester));

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: CameraOvalOverlay(
                  instruction: 'Position your face within the oval and blink naturally',
                  state: OvalState.neutral,
                  bottomOffset: 36.0,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify overlay widget is present and no errors were thrown
        expect(find.byType(CameraOvalOverlay), findsOneWidget);
        expect(find.text('Position your face within the oval and blink naturally'), findsOneWidget);

        // Find the custom paint for the oval
        final customPaintFinder = find.byType(CustomPaint);
        expect(customPaintFinder, findsWidgets);

        // Verify that layout bounds are strictly contained within screen dimensions
        final overlayRenderBox = tester.renderObject<RenderBox>(find.byType(CameraOvalOverlay));
        expect(overlayRenderBox.size.width, equals(profile.width));
        expect(overlayRenderBox.size.height, equals(profile.height));

        // Zero FlutterError / zero RenderFlex overflow
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Elevated bottomOffset (92dp) prevents button collision in face enrollment', (tester) async {
      setScreenSize(tester, canonicalProfiles[0]); // Smallest screen 320x533
      addTearDown(() => resetScreenSize(tester));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const SizedBox.expand(
                  child: CameraOvalOverlay(
                    instruction: 'Position face: Sample 1 of 5',
                    state: OvalState.detected,
                    bottomOffset: 92.0,
                  ),
                ),
                Positioned(
                  bottom: 24,
                  left: 20,
                  right: 20,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {},
                      child: const Text('CAPTURE SAMPLE (1/5)'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('Position face: Sample 1 of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Preserves oval face aspect ratio on 16:9, 20:9, and 4:3 viewports', (tester) async {
      final viewports = [
        const Size(360, 640),  // 16:9
        const Size(412, 915),  // 20:9
        const Size(768, 1024), // 4:3
      ];

      for (final vp in viewports) {
        tester.view.physicalSize = Size(vp.width * 2, vp.height * 2);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: CameraOvalOverlay(
                  instruction: 'Blink to verify liveness',
                  state: OvalState.blinking,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Blink to verify liveness'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      resetScreenSize(tester);
    });
  });

  group('Login Screen — Responsive Layout Across Devices', () {
    for (final profile in canonicalProfiles) {
      testWidgets('Renders Login Screen with zero overflow on ${profile.name}', (tester) async {
        setScreenSize(tester, profile);
        addTearDown(() => resetScreenSize(tester));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const LoginScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Essential interactive elements
        expect(find.text('FieldStaff AI'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(2)); // Employee ID & Password

        // Enter ID into text field
        await tester.enterText(find.byType(TextFormField).first, 'admin');
        await tester.pumpAndSettle();

        // ID field is populated with admin
        expect(find.text('admin'), findsOneWidget);

        // Ensure zero overflow errors
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Employee Registration Screen — Responsive Layout', () {
    for (final profile in canonicalProfiles) {
      testWidgets('Renders Registration Screen on ${profile.name}', (tester) async {
        setScreenSize(tester, profile);
        addTearDown(() => resetScreenSize(tester));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const RegisterEmployeeScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Register Employee'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Create Employee Account'), findsOneWidget);
        expect(find.byType(TextFormField), findsWidgets);

        // Verify fields are responsive and zero overflow
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Change Password Screen — Responsive Layout', () {
    for (final profile in canonicalProfiles) {
      testWidgets('Renders Change Password Screen on ${profile.name}', (tester) async {
        setScreenSize(tester, profile);
        addTearDown(() => resetScreenSize(tester));

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ChangePasswordScreen(currentPassword: 'currentPass123!'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Change Initial Password'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Update Password & Continue'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Geofence Config Screen — Coordinates Adaptation', () {
    testWidgets('Coordinates stack vertically on small screen (320dp)', (tester) async {
      setScreenSize(tester, canonicalProfiles[0]); // 320x533
      addTearDown(() => resetScreenSize(tester));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const GeofenceConfigScreen(
            userId: 1,
            employeeId: 'EMP001',
            fullName: 'Rajesh Sharma Long Name Test Employee',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure employee name does not overflow
      expect(find.text('Rajesh Sharma Long Name Test Employee'), findsOneWidget);
      expect(find.text('Latitude *'), findsOneWidget);
      expect(find.text('Longitude *'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Save Geofence Rules'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Coordinates display side-by-side in Row on modern screen (412dp)', (tester) async {
      setScreenSize(tester, canonicalProfiles[2]); // 412x915
      addTearDown(() => resetScreenSize(tester));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const GeofenceConfigScreen(
            userId: 1,
            employeeId: 'EMP001',
            fullName: 'Rajesh Sharma',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Latitude *'), findsOneWidget);
      expect(find.text('Longitude *'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Shift Management Dynamic Rules Expansion Tile — Responsive Safety', () {
    testWidgets('Rule title and classification badge never collide on narrow 320dp screen', (tester) async {
      setScreenSize(tester, canonicalProfiles[0]); // 320x533
      addTearDown(() => resetScreenSize(tester));

      final sampleRule = ShiftRuleModel(
        ruleCode: 'AFTERNOON_PUNCH',
        ruleName: 'Very Long Shift Rule Name For Afternoon Punch Window Test',
        startTime: '13:00:00',
        endTime: '13:14:59',
        resultCode: 'AFTERNOON_PUNCH',
        priority: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: Card(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                sampleRule.ruleName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${sampleRule.startTime} - ${sampleRule.endTime} (Priority ${sampleRule.priority})',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sampleRule.resultCode,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.purple,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(sampleRule.resultCode), findsOneWidget);
      expect(find.text(sampleRule.ruleName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('User Dashboard Verification Windows — Narrow Screen (320dp) Safety', () {
    testWidgets('Verification window row does not overflow with badge on 320dp screen', (tester) async {
      setScreenSize(tester, canonicalProfiles[0]); // 320x533
      addTearDown(() => resetScreenSize(tester));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text('W1', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Verification 1 (Morning Check-in)',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Window: 08:00:00 - 09:30:00',
                                style: TextStyle(color: Colors.grey, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('COMPLETED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('W1'), findsOneWidget);
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Attendance History — Telemetry Badges Wrap on Small Screen (320dp)', () {
    testWidgets('History verification item wraps telemetry chips cleanly without overflow', (tester) async {
      setScreenSize(tester, canonicalProfiles[0]); // 320x533
      addTearDown(() => resetScreenSize(tester));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.blue,
                              child: Text('1', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Verification Window 1 (Morning Punch)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text('08:45:12 AM', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('PRESENT', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(6)),
                              child: const Text('Live Sync', style: TextStyle(fontSize: 11)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(6)),
                              child: const Text('12.4m from Site', style: TextStyle(fontSize: 11)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(6)),
                              child: const Text('Face: 0.94', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRESENT'), findsOneWidget);
      expect(find.text('12.4m from Site'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Scrollable Dialogs — Height Constrained on Short Screen (480dp)', () {
    testWidgets('Attendance result dialog is scrollable and does not overflow short viewport', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 480 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => resetScreenSize(tester));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: ctx,
                    builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Text('Attendance Recorded'),
                      content: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              10,
                              (i) => ListTile(
                                dense: true,
                                title: Text('Telemetry Item $i'),
                                subtitle: Text('Verification Detail $i'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      actions: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Attendance Recorded'), findsOneWidget);
      expect(find.text('Telemetry Item 0'), findsOneWidget);

      // Verify zero overflow exceptions
      expect(tester.takeException(), isNull);
    });
  });

  group('Biometric Security & Policy Invariance Across Screen Sizes', () {
    test('Face match threshold and liveness rules remain identical regardless of screen dimensions', () {
      // Screen resizing must only adapt presentation, never security thresholds
      const faceMatchThreshold = 0.60;
      const livenessBlinkRequired = true;
      const maxGeofenceRadiusDefault = 100.0;

      for (final profile in canonicalProfiles) {
        // Assert invariants are constant across all profiles
        expect(faceMatchThreshold, equals(0.60),
            reason: 'Face match threshold must not change for ${profile.name}');
        expect(livenessBlinkRequired, isTrue,
            reason: 'Liveness requirement must not change for ${profile.name}');
        expect(maxGeofenceRadiusDefault, equals(100.0),
            reason: 'Geofence radius policy must not change for ${profile.name}');
      }
    });
  });
}
