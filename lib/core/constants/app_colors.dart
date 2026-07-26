import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Primary Brand Colors ──────────────────────────────────────────
  static const Color primary = Color(0xFF0D47A1);        // Deep Navy Blue
  static const Color primaryLight = Color(0xFF1565C0);   // Medium Blue
  static const Color primaryDark = Color(0xFF082F6E);    // Darker Navy
  static const Color accent = Color(0xFF00BCD4);         // Cyan Accent
  static const Color accentLight = Color(0xFF4DD0E1);    // Light Cyan

  // ── Background Colors ─────────────────────────────────────────────
  static const Color background = Color(0xFFF5F7FF);     // Soft Blue-White
  static const Color surface = Color(0xFFFFFFFF);        // Pure White
  static const Color surfaceVariant = Color(0xFFE8EDF7); // Light Blue-Grey

  // ── Text Colors ───────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0D1B3E);    // Dark Navy Text
  static const Color textSecondary = Color(0xFF5A6A8A);  // Muted Blue-Grey
  static const Color textHint = Color(0xFFADB8CC);       // Placeholder
  static const Color textOnPrimary = Color(0xFFFFFFFF);  // White on blue

  // ── Status Colors ─────────────────────────────────────────────────
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFF57F17);
  static const Color warningLight = Color(0xFFFFF8E1);
  static const Color error = Color(0xFFC62828);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color info = Color(0xFF0288D1);
  static const Color infoLight = Color(0xFFE1F5FE);

  // ── Role Colors ───────────────────────────────────────────────────
  static const Color adminColor = Color(0xFF4A148C);       // Deep Purple
  static const Color adminLight = Color(0xFFF3E5F5);
  static const Color driverColor = Color(0xFF1B5E20);      // Deep Green
  static const Color driverLight = Color(0xFFE8F5E9);
  static const Color userColor = Color(0xFF0D47A1);        // Primary Blue
  static const Color userLight = Color(0xFFE3F2FD);

  // ── Status Badge Colors ───────────────────────────────────────────
  static const Color pendingColor = Color(0xFFF57F17);
  static const Color pendingLight = Color(0xFFFFF8E1);
  static const Color approvedColor = Color(0xFF2E7D32);
  static const Color approvedLight = Color(0xFFE8F5E9);
  static const Color rejectedColor = Color(0xFFC62828);
  static const Color rejectedLight = Color(0xFFFFEBEE);

  // ── UI Elements ───────────────────────────────────────────────────
  static const Color divider = Color(0xFFDDE3F0);
  static const Color shadow = Color(0x1A0D47A1);          // Blue-tinted shadow
  static const Color cardBorder = Color(0xFFE0E8F5);
  static const Color inputBorder = Color(0xFFBDCAE0);
  static const Color inputFocused = Color(0xFF0D47A1);

  // ── Gradient Definitions ──────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primaryDark],
  );

  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0D47A1), Color(0xFF082F6E)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
  );

  static const LinearGradient adminGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6A1B9A), Color(0xFF4A148C)],
  );

  static const LinearGradient driverGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
  );

  // ── Dynamic Theme Helpers ─────────────────────────────────────────
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color getTextPrimary(BuildContext context) =>
      isDark(context) ? Colors.white : textPrimary;

  static Color getTextSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFFC9D1D9) : textSecondary;

  static Color getSurfaceColor(BuildContext context) =>
      isDark(context) ? const Color(0xFF161B22) : surface;

  static Color getCardBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFF30363D) : cardBorder;
}