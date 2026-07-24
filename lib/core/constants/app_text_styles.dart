import 'package:flutter/material.dart';

/// Centralized Text Styles for ASSA App
/// Strictly enforces standard font sizes and weights across all screens and widgets.
class AppTextStyles {
  AppTextStyles._();

  static const String fontFamily = 'Poppins';

  // ── Standard 12 Font Styles ──────────────────────────────────────────

  /// Display Large: 32px, Bold (800)
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w800,
  );

  /// Display Medium: 28px, Bold (700)
  static const TextStyle displayMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
  );

  /// Headline Large: 24px, Bold (700)
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
  );

  /// Headline Medium: 20px, Bold (700)
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );

  /// Headline Small: 18px, SemiBold (600)
  static const TextStyle headlineSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  /// Title Large: 16px, Bold (700)
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  /// Title Medium: 15px, SemiBold (600)
  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// Body Large: 14px, Medium (500)
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  /// Body Medium: 13px, Regular (400)
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  /// Body Small: 12px, Regular (400)
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  /// Label: 11px, Medium (500)
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  /// Tiny: 10px, SemiBold (600)
  static const TextStyle tiny = TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );

  // ── Convenience / Compatibility Aliases ─────────────────────────────
  static const TextStyle displaySmall = headlineMedium;
  static const TextStyle labelLarge = bodyLarge;
  static const TextStyle labelMedium = bodySmall;
  static const TextStyle labelSmall = label;
  static const TextStyle buttonLarge = titleLarge;
  static const TextStyle buttonMedium = bodyLarge;
  static const TextStyle appBarTitle = headlineMedium;
  static const TextStyle appBarSubtitle = bodySmall;
  static const TextStyle caption = label;
  static const TextStyle overline = tiny;
  static const TextStyle inputText = bodyLarge;
  static const TextStyle inputHint = bodyLarge;
  static const TextStyle inputLabel = bodyMedium;
  static const TextStyle link = bodyLarge;
  static const TextStyle badge = label;
}