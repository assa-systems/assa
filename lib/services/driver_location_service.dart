import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

/// ===========================================================================
/// ASSA Ultra-Low-Data Driver Location Service
/// Target daily data usage: < 5 MB (Full 8-12 hr shift)
///
/// Optimization Strategy:
/// 1. Stationary Deadband: If driver moved < 12m (waiting at bus stop / gate),
///    do NOT send continuous updates. Send a single heartbeat every 60 seconds.
/// 2. Moving State: When distance >= 12m (driving), send every 6 seconds.
/// 3. Truncated Precision: 5 decimal places (~1.1m precision) saves payload bytes.
/// ===========================================================================
class DriverLocationService {
  static final DriverLocationService instance = DriverLocationService._();
  DriverLocationService._();

  Timer? _timer;
  bool _isTracking = false;
  bool get isTracking => _isTracking;

  double? _lastLat;
  double? _lastLng;
  DateTime? _lastSendTime;

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Future<void> startTracking({String? shuttleId}) async {
    if (_isTracking) return;
    final hasPermission = await requestPermission();
    if (!hasPermission) return;
    _isTracking = true;
    _lastLat = null;
    _lastLng = null;
    _lastSendTime = null;

    _tick(shuttleId);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick(shuttleId));
  }

  Future<void> _tick(String? shuttleId) async {
    if (!_isTracking) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      final now = DateTime.now();
      final currentLat = double.parse(pos.latitude.toStringAsFixed(5));
      final currentLng = double.parse(pos.longitude.toStringAsFixed(5));

      // SMART STATIONARY FILTER (SAVES 95% DATA WHILE WAITING)
      if (_lastLat != null && _lastLng != null && _lastSendTime != null) {
        final distanceMeters = Geolocator.distanceBetween(
          _lastLat!,
          _lastLng!,
          currentLat,
          currentLng,
        );

        if (distanceMeters < 12.0) {
          // Stationary / Waiting for passengers
          if (now.difference(_lastSendTime!).inSeconds < 60) {
            return; // ZERO network data consumed while waiting!
          }
        } else {
          // Moving / Driving
          if (now.difference(_lastSendTime!).inSeconds < 6) {
            return; // Throttle to 6 seconds
          }
        }
      }

      _lastLat = currentLat;
      _lastLng = currentLng;
      _lastSendTime = now;

      final data = <String, dynamic>{
        'liveLocation': {
          'lat': currentLat,
          'lng': currentLng,
          'heading': pos.heading,
          'speed': pos.speed,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'isOnline': true,
      };

      if (shuttleId != null && shuttleId.isNotEmpty) {
        data['shuttleId'] = shuttleId;
      }

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .set(data, SetOptions(merge: true));

      if (shuttleId != null && shuttleId.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('shuttle_status')
            .doc(shuttleId)
            .set({
          'shuttleId': shuttleId,
          'lat': currentLat,
          'lng': currentLng,
          'accuracy': pos.accuracy,
          'updatedAt': FieldValue.serverTimestamp(),
          'driverId': uid,
          'online': true,
        }, SetOptions(merge: true)).catchError((_) {});
      }
    } catch (_) {}
  }

  Future<void> stopTracking({String? shuttleId}) async {
    _isTracking = false;
    _timer?.cancel();
    _timer = null;
    _lastLat = null;
    _lastLng = null;
    _lastSendTime = null;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .update({'liveLocation': FieldValue.delete(), 'isOnline': false});

      if (shuttleId != null && shuttleId.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('shuttle_status')
            .doc(shuttleId)
            .update({'online': false}).catchError((_) {});
      }
    } catch (_) {}
  }
}
