import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:assa/services/esp32_service.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionStatusController =
  StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionStatusController.stream;

  // ─── TWO SEPARATE STATES ──────────────────────────────────────────
  bool _hasInternet = true;
  bool get hasInternet => _hasInternet;

  bool _isEsp32Reachable = false;
  bool get isEsp32Reachable => _isEsp32Reachable;

  // ─── Cache ──────────────────────────────────────────────────────────
  bool _cachedEsp32Reachable = false;
  DateTime _lastEsp32Check = DateTime.now().subtract(const Duration(minutes: 5));
  static const Duration esp32CacheDuration = Duration(seconds: 3);

  ConnectivityService() {
    _init();
  }

  void _init() {
    // Start checking after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      checkConnectivity();
    });

    // This project's installed connectivity_plus version returns a single
    // ConnectivityResult here (Stream<ConnectivityResult>), not a List —
    // do NOT "upgrade" this to the list-based API unless the pubspec
    // dependency is actually bumped to connectivity_plus ^5.0.0 or later.
    _connectivity.onConnectivityChanged.listen((result) async {
      // Wait for network to settle
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkBoth(result);
    });
  }

  // ─── Check both internet AND ESP32 reachability ───────────────────
  // FIX: wrapped in an overall timeout + try/catch. Previously, if any
  // step below (native plugin call, socket, DNS) hung instead of
  // throwing, checkConnectivity() would never resolve and any UI
  // awaiting it (e.g. RequestScreen's "Checking connection..." spinner)
  // would be stuck on that screen forever. Now this always settles
  // within ~4s no matter what the platform/plugins do.
  Future<void> _checkBoth(ConnectivityResult result) async {
    try {
      // 1. Check if ESP32 AP is reachable (works without internet)
      final esp32Reachable = await _checkEsp32Reachable()
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
      _isEsp32Reachable = esp32Reachable;

      // 2. If ESP32 is reachable, we are on campus network → NO internet
      if (esp32Reachable) {
        _hasInternet = false;
        _connectionStatusController.add(false);
        return;
      }

      // 3. Check if we have real internet
      _hasInternet = await _checkRealInternet(result)
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      _connectionStatusController.add(_hasInternet);
    } catch (_) {
      // Never let a plugin/network hiccup leave callers waiting forever.
      _isEsp32Reachable = false;
      _hasInternet = false;
      _connectionStatusController.add(false);
    }
  }

  // ─── Check internet via DNS ────────────────────────────────────────
  Future<bool> _checkRealInternet(ConnectivityResult result) async {
    if (result == ConnectivityResult.none) return false;

    try {
      // Single DNS lookup with shorter timeout
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      if (lookup.isEmpty || lookup[0].rawAddress.isEmpty) return false;
      if (lookup[0].address == Esp32Service.esp32IpAddress) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Force traffic onto the AP's WiFi (Android only) ───────────────
  // FIX: WiFiForIoTPlugin.forceWifiUsage() is a native MethodChannel call.
  // On some devices/OS versions it can hang indefinitely instead of
  // throwing (e.g. waiting on a system dialog or a stuck binder call) —
  // that hang was propagating all the way up through _checkEsp32Reachable
  // → _checkBoth → checkConnectivity → RequestScreen's "Checking
  // connection..." spinner, leaving the user stuck on that screen with
  // no error and no way forward. A timeout here guarantees this always
  // returns.
  static Future<void> _forceWifi(bool force) async {
    if (!Platform.isAndroid) return;
    try {
      await WiFiForIoTPlugin.forceWifiUsage(force)
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
    } catch (_) {}
  }

  // ─── Check ESP32 reachability (HTTP GET) ──────────────────────────
  Future<bool> _checkEsp32Reachable() async {
    final now = DateTime.now();
    // Use cache to avoid repeated checks
    if (now.difference(_lastEsp32Check) < esp32CacheDuration) {
      return _cachedEsp32Reachable;
    }

    bool reachable = false;
    await _forceWifi(true);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1)
        ..idleTimeout = const Duration(seconds: 1);

      final request = await client
          .getUrl(Uri.parse(
          'http://${Esp32Service.esp32IpAddress}:${Esp32Service.esp32Port}/'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      client.close();

      // Any HTTP response means the AP is alive
      reachable = response.statusCode >= 200 && response.statusCode < 600;
    } on SocketException {
      reachable = false;
    } on TimeoutException {
      reachable = false;
    } catch (_) {
      reachable = false;
    } finally {
      await _forceWifi(false);
    }

    // Update cache
    _cachedEsp32Reachable = reachable;
    _lastEsp32Check = now;

    return reachable;
  }

  // ─── Public methods ──────────────────────────────────────────────────
  // FIX: added an outer timeout + fallback so a hung platform channel
  // (connectivity_plus itself, or the WiFi plugin further down the call
  // chain) can never block a caller — like RequestScreen's initial
  // connectivity check — forever.
  Future<bool> checkConnectivity() async {
    try {
      final result = await _connectivity
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));
      await _checkBoth(result);
      return _hasInternet;
    } catch (_) {
      _hasInternet = false;
      _isEsp32Reachable = false;
      _connectionStatusController.add(false);
      return false;
    }
  }

  // ─── Force refresh ESP32 status ────────────────────────────────────
  Future<bool> refreshEsp32Status() async {
    // Clear cache to force fresh check
    _lastEsp32Check = DateTime.now().subtract(const Duration(seconds: 10));
    _cachedEsp32Reachable = false;
    try {
      return await _checkEsp32Reachable()
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> isWifiConnected() async {
    try {
      final result =
      await _connectivity.checkConnectivity().timeout(const Duration(seconds: 3));
      return result == ConnectivityResult.wifi;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isMobileDataConnected() async {
    try {
      final result =
      await _connectivity.checkConnectivity().timeout(const Duration(seconds: 3));
      return result == ConnectivityResult.mobile;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isInCampusOfflineMode() async {
    final onWifi = await isWifiConnected();
    if (!onWifi) return false;
    await checkConnectivity();
    return _isEsp32Reachable && !_hasInternet;
  }

  void dispose() {
    _connectionStatusController.close();
  }
}
