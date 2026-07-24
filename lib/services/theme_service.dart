import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════════
// THEME SERVICE — ASSA
// Lightweight singleton ThemeMode controller (no external state package
// required — matches the app's existing pattern of singleton services
// like ConnectivityService / Esp32Service). Persists the user's choice
// via SharedPreferences and notifies listeners (root MaterialApp) on
// change so switching is instant, app-wide, and survives restarts.
// ════════════════════════════════════════════════════════════════════

class ThemeController extends ChangeNotifier {
  ThemeController._internal();
  static final ThemeController instance = ThemeController._internal();
  factory ThemeController() => instance;

  static const String _prefsKey = 'assa_theme_mode';

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Call once in main() before runApp() so the correct theme is applied
  /// on the very first frame (no flash of the wrong theme).
  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      _themeMode = _fromString(saved);
    } catch (_) {
      _themeMode = ThemeMode.light;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _toString(mode));
    } catch (_) {}
  }

  static ThemeMode _fromString(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
