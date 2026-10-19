import 'package:flutter/material.dart';

/// Screen category classification based on logical width breakpoints
enum ScreenCategory {
  small,      // Width < 360 dp (e.g. compact, Android Go, older 320x480/533)
  medium,     // 360 <= Width < 600 dp (standard & modern phones 360-430 dp)
  large,      // 600 <= Width < 900 dp (foldables unfolded, 7-inch tablets)
  extraLarge, // Width >= 900 dp (10-inch tablets, desktop/web)
}

/// Extension on BuildContext for rapid, responsive UI calculations
extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.of(this).size;
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  double get aspectRatio => MediaQuery.of(this).size.aspectRatio;
  Orientation get orientation => MediaQuery.of(this).orientation;
  bool get isLandscape => orientation == Orientation.landscape;

  ScreenCategory get screenCategory {
    final w = screenWidth;
    if (w < 360) return ScreenCategory.small;
    if (w < 600) return ScreenCategory.medium;
    if (w < 900) return ScreenCategory.large;
    return ScreenCategory.extraLarge;
  }

  bool get isSmallScreen => screenCategory == ScreenCategory.small;
  bool get isMediumScreen => screenCategory == ScreenCategory.medium;
  bool get isLargeScreen => screenCategory == ScreenCategory.large;
  bool get isExtraLargeScreen => screenCategory == ScreenCategory.extraLarge;
  bool get isTablet => screenWidth >= 600;
}

/// Utility for responsive dimensions, padding, font scaling, and value switching
class ResponsiveUtil {
  /// Returns the ScreenCategory for the given BuildContext
  static ScreenCategory category(BuildContext context) => context.screenCategory;

  /// Resolves a value depending on the current active screen category
  static T value<T>(
    BuildContext context, {
    required T small,
    required T medium,
    T? large,
    T? extraLarge,
  }) {
    switch (context.screenCategory) {
      case ScreenCategory.small:
        return small;
      case ScreenCategory.medium:
        return medium;
      case ScreenCategory.large:
        return large ?? medium;
      case ScreenCategory.extraLarge:
        return extraLarge ?? large ?? medium;
    }
  }

  /// Screen-adaptive horizontal and vertical padding
  static EdgeInsets screenPadding(BuildContext context) {
    return value<EdgeInsets>(
      context,
      small: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      medium: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      large: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      extraLarge: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
    );
  }

  /// Screen-adaptive card interior padding
  static EdgeInsets cardPadding(BuildContext context) {
    return value<EdgeInsets>(
      context,
      small: const EdgeInsets.all(12),
      medium: const EdgeInsets.all(16),
      large: const EdgeInsets.all(20),
      extraLarge: const EdgeInsets.all(24),
    );
  }

  /// Scales font size smoothly within safe bounds
  static double font(BuildContext context, double baseSize) {
    final factor = value<double>(
      context,
      small: 0.90,
      medium: 1.0,
      large: 1.08,
      extraLarge: 1.15,
    );
    return (baseSize * factor).clamp(10.0, baseSize * 1.3);
  }

  /// Standard maximum content width for readability on large screens
  static double maxContentWidth(BuildContext context) {
    return value<double>(
      context,
      small: double.infinity,
      medium: double.infinity,
      large: 640.0,
      extraLarge: 780.0,
    );
  }
}

/// A responsive wrapper widget that centers content and enforces maximum width
/// on large screens while retaining full-bleed responsiveness on smaller displays.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveContainer({
    Key? key,
    required this.child,
    this.maxWidth,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final effectiveMaxWidth = maxWidth ?? ResponsiveUtil.maxContentWidth(context);
    final effectivePadding = padding ?? ResponsiveUtil.screenPadding(context);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: effectiveMaxWidth,
        ),
        child: Padding(
          padding: effectivePadding,
          child: child,
        ),
      ),
    );
  }
}
