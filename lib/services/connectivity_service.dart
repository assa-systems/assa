import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _controller.stream;
  bool _hasInternet = true;
  bool get hasInternet => _hasInternet;

  ConnectivityService() {
    _init();
  }

  void _init() {
    Future.delayed(const Duration(milliseconds: 500), checkConnectivity);
    _connectivity.onConnectivityChanged.listen((result) async {
      await Future.delayed(const Duration(milliseconds: 500));
      await checkConnectivity();
    });
  }

  Future<bool> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity()
          .timeout(const Duration(seconds: 3));
      bool online = result != ConnectivityResult.none;
      if (online) {
        try {
          final lookup = await InternetAddress.lookup('google.com')
              .timeout(const Duration(seconds: 3));
          online = lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
        } catch (_) {
          online = false;
        }
      }
      _hasInternet = online;
      _controller.add(_hasInternet);
      return _hasInternet;
    } catch (_) {
      _hasInternet = false;
      _controller.add(false);
      return false;
    }
  }

  void dispose() {
    _controller.close();
  }
}
