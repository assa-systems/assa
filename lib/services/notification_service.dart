import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

// ======================================================================
// NOTIFICATION SERVICE — FCM + Firestore + RTDB
//
// Aligned with Chapter 3 Methodology:
// • Online path: Flutter app ← Firebase RTDB (sub-second status push)
// • Both paths:  Firestore notifications collection (in-app bell)
// • FCM token:   Saved to users/{uid}/fcmToken on every login
// • FCM send:    Direct HTTP v1 API call using FCM server key
//
// Usage:
//   main.dart         → await NotificationService.instance.initialize()
//   user_dashboard    → NotificationService.instance.attachRideListener(uid)
//   driver_dashboard  → NotificationService.instance.attachDriverListener(uid)
//   logout            → NotificationService.instance.detachAllListeners()
// ======================================================================

// ── FCM Server Key — stored here for device-to-device push ──
// This is the LEGACY server key from Firebase Console →
// Project Settings → Cloud Messaging → Server key
// Replace with your actual key below:
const String _fcmServerKey = 'YOUR_FCM_SERVER_KEY_HERE';

// Top-level handler for background FCM messages (required by Firebase)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages shown automatically by FCM on Android 8+
  debugPrint('Background FCM: ${message.notification?.title}');
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  factory NotificationService() => instance;

  final _db         = FirebaseFirestore.instance;
  final _fcm        = FirebaseMessaging.instance;
  final _localNotifs = FlutterLocalNotificationsPlugin();

  // Android notification channel
  static const _channelId   = 'assa_main';
  static const _channelName = 'ASSA Notifications';
  static const _fcmServerUrl = 'https://sendnotification-nb2ywctvvq-uc.a.run.app';

  dynamic _rideStatusSub;
  dynamic _driverRequestSub;

  // =====================================================================
  // initialize() — call once in main.dart after Firebase.initializeApp
  // =====================================================================
  Future<void> initialize() async {
    // 1. Register background handler (must be top-level function)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Request permission (iOS + Android 13+)
    await _fcm.requestPermission(
      alert:       true,
      badge:       true,
      sound:       true,
      provisional: false,
    );

    // 3. Create Android notification channel (high importance)
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'ASSA ride updates and driver alerts',
      importance:  Importance.max,
      playSound:   true,
      enableVibration: true,
    );
    await _localNotifs
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // 4. Initialise flutter_local_notifications
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS:     DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    await _localNotifs.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 5. Show banner when app is in FOREGROUND
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. Handle notification tap when app was in BACKGROUND
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    // 7. Check if app was opened from a terminated state via notification
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleNotificationOpen(initial);

    // 8. Save FCM token now (user must be logged in)
    await saveFcmToken();

    // 9. Auto-refresh token when Firebase rotates it
    _fcm.onTokenRefresh.listen(_updateFcmToken);
  }

  // =====================================================================
  // FCM TOKEN MANAGEMENT
  // =====================================================================

  /// Call after login — saves token to users/{uid}/fcmToken in Firestore
  Future<void> saveFcmToken() async {
    try {
      final uid   = FirebaseAuth.instance.currentUser?.uid;
      final token = await _fcm.getToken();
      if (uid == null || token == null) return;
      await _db.collection('users').doc(uid).update({
        'fcmToken':  token,
        'platform':  Platform.isIOS ? 'ios' : 'android',
        'lastSeen':  FieldValue.serverTimestamp(),
      });
      debugPrint('FCM token saved for $uid');
    } catch (e) {
      debugPrint('saveFcmToken error: $e');
    }
  }

  Future<void> _updateFcmToken(String token) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await _db.collection('users').doc(uid).update({
        'fcmToken': token,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('_updateFcmToken error: $e');
    }
  }

  // =====================================================================
  // SEND FCM PUSH NOTIFICATION TO A SPECIFIC DEVICE
  // Uses Firebase Cloud Messaging Legacy HTTP API
  // Target: the FCM token stored in users/{targetUid}/fcmToken
  // =====================================================================
  Future<bool> sendPushToUser({
    required String targetUid,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    try {
      // Get the target user's FCM token from Firestore
      final userDoc = await _db.collection('users').doc(targetUid).get();
      final token   = userDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) {
        debugPrint('sendPushToUser: no FCM token for $targetUid');
        return false;
      }

      // Send via FCM Legacy HTTP API
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'key=$_fcmServerKey',
        },
        body: jsonEncode({
          'to': token,
          'priority': 'high',
          'notification': {
            'title': title,
            'body':  body,
            'sound': 'default',
          },
          'data': {
            ...data,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('FCM push sent to $targetUid');
        return true;
      } else {
        debugPrint('FCM error ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('sendPushToUser error: $e');
      return false;
    }
  }

  /// Send push to ALL drivers simultaneously (for new ride requests)
  Future<void> sendPushToAllDrivers({
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    try {
      final drivers = await _db
          .collection('users')
          .where('role',   isEqualTo: 'driver')
          .where('status', isEqualTo: 'approved')
          .get();

      for (final doc in drivers.docs) {
        final token = doc.data()['fcmToken'] as String?;
        if (token == null || token.isEmpty) continue;
        await http.post(
          Uri.parse('https://fcm.googleapis.com/fcm/send'),
          headers: {
            'Content-Type':  'application/json',
            'Authorization': 'key=$_fcmServerKey',
          },
          body: jsonEncode({
            'to':       token,
            'priority': 'high',
            'notification': {'title': title, 'body': body, 'sound': 'default'},
            'data': {...data, 'click_action': 'FLUTTER_NOTIFICATION_CLICK'},
          }),
        );
      }
    } catch (e) {
      debugPrint('sendPushToAllDrivers error: $e');
    }
  }

  // =====================================================================
  // FOREGROUND MESSAGE HANDLER
  // Shows a local notification banner when app is open
  // =====================================================================
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _showLocalNotification(
      id:    notification.hashCode,
      title: notification.title ?? 'ASSA',
      body:  notification.body  ?? '',
      data:  message.data,
    );
  }

  void _handleNotificationOpen(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');
    // Navigation can be added here based on message.data['type']
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');
  }

  Future<void> _showLocalNotification({
    required int    id,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    await _localNotifs.show(
      id:    id,
      title: title,
      body:  body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance:  Importance.max,
          priority:    Priority.high,
          icon:        '@mipmap/ic_launcher',
          playSound:   true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  // =====================================================================
  // FIRESTORE NOTIFICATION WRITER
  // Writes to notifications/{auto-id} for in-app bell badge
  // =====================================================================
  Future<void> writeNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      await _db.collection('notifications').add({
        'userId':    userId,
        'title':     title,
        'body':      body,
        'type':      type,
        'read':      false,
        'createdAt': FieldValue.serverTimestamp(),
        ...extra,
      });
    } catch (e) {
      debugPrint('writeNotification error: $e');
    }
  }

  // =====================================================================
  // RIDE STATUS LISTENER — User side
  // Listens to ride_requests changes and fires notifications
  // Aligned with methodology: status codes 1=Assigned, 4=Completed
  // =====================================================================
  void attachRideListener(String userId) {
    _rideStatusSub?.cancel();
    _rideStatusSub = _db
        .collection('ride_requests')
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: [1, 4, 5])
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.modified) continue;
        final data    = change.doc.data() ?? {};
        final status  = data['status']   as int?    ?? 0;
        final pickup  = data['pickupLocation'] ?? 'your location';
        final dest    = data['destination']    ?? 'destination';
        final shuttle = data['shuttleIdFeedback'] ?? 'A shuttle';
        final driver  = data['driverName'] ?? 'Your driver';

        String? title, body;
        switch (status) {
          case 1:
            title = '🚌 Shuttle Assigned!';
            body  = '$driver (Shuttle $shuttle) accepted your request from $pickup.';
            break;
          case 4:
            title = '🏁 Ride Completed';
            body  = 'Your ride to $dest is complete. Thank you for using ASSA!';
            break;
          case 5:
            title = '❌ Ride Cancelled';
            body  = 'Your shuttle request from $pickup has been cancelled.';
            break;
        }

        if (title != null && body != null) {
          // Show local banner immediately
          _showLocalNotification(
            id:    status * 1000 + change.doc.id.hashCode % 1000,
            title: title,
            body:  body,
          );
          // Write to Firestore bell
          writeNotification(
            userId: userId,
            title:  title,
            body:   body,
            type:   'ride_status',
            extra:  {'statusCode': status, 'requestId': change.doc.id},
          );
        }
      }
    }, onError: (e) => debugPrint('attachRideListener error: $e'));
  }

  // =====================================================================
  // DRIVER LISTENER — New ride request push
  // Fires when a new ride_request appears with status=0
  // =====================================================================
  void attachDriverListener(String driverUid) {
    _driverRequestSub?.cancel();
    _driverRequestSub = _db
        .collection('ride_requests')
        .where('status', isEqualTo: 0)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data   = change.doc.data() ?? {};
        final pickup = data['pickupLocation'] ?? 'Unknown';
        final dest   = data['destination']    ?? 'Unknown';
        final pax    = data['passengerCount'] ?? 1;
        _showLocalNotification(
          id:    change.doc.id.hashCode,
          title: '🚨 New Ride Request!',
          body:  '$pickup → $dest · $pax pax',
          data:  {'type': 'new_request', 'requestId': change.doc.id},
        );
      }
    }, onError: (e) => debugPrint('attachDriverListener error: $e'));
  }

  void detachRideListener() {
    _rideStatusSub?.cancel();
    _rideStatusSub = null;
  }

  void detachDriverListener() {
    _driverRequestSub?.cancel();
    _driverRequestSub = null;
  }

  void detachAllListeners() {
    detachRideListener();
    detachDriverListener();
  }

  // =====================================================================
  // DRIVER APPROVAL / REJECTION
  // =====================================================================
  Future<void> notifyDriverApproved({
    required String driverUid,
    required String driverName,
  }) async {
    const title = '✅ Application Approved';
    final body  = 'Congratulations $driverName! Your driver application has been approved. You can now log in and start accepting rides.';
    await writeNotification(userId: driverUid, title: title, body: body, type: 'driver_approved');
    await sendPushToUser(targetUid: driverUid, title: title, body: body, data: {'type': 'driver_approved'});
  }

  Future<void> notifyDriverRejected({
    required String driverUid,
    required String driverName,
  }) async {
    const title = '❌ Application Not Approved';
    final body  = 'Hi $driverName, your driver application was not approved. Contact admin for more information.';
    await writeNotification(userId: driverUid, title: title, body: body, type: 'driver_rejected');
    await sendPushToUser(targetUid: driverUid, title: title, body: body, data: {'type': 'driver_rejected'});
  }

  // =====================================================================
  // RIDE ACCEPTED NOTIFICATION — called from acceptRideIntent/acceptRideGroup
  // Notifies the passenger when driver accepts (online path)
  // =====================================================================
  Future<void> notifyRideAccepted({
    required String userId,
    required String driverName,
    required String shuttleId,
    required String pickup,
    required String dest,
    required String requestId,
  }) async {
    final title = '🚌 Shuttle Assigned!';
    final body  = '$driverName (Shuttle $shuttleId) accepted your request: $pickup → $dest';
    await writeNotification(
      userId: userId, title: title, body: body, type: 'ride_assigned',
      extra: {'requestId': requestId, 'driverName': driverName, 'shuttleId': shuttleId},
    );
    await sendPushToUser(
      targetUid: userId, title: title, body: body,
      data: {'type': 'ride_assigned', 'requestId': requestId},
    );
  }

  // =====================================================================
  // ADMIN BROADCAST
  // =====================================================================
  Future<bool> broadcastToAllUsers({
    required String title,
    required String body,
    String type = 'general',
  }) async {
    try {
      final users = await _db.collection('users').get();
      final batch = _db.batch();
      for (final u in users.docs) {
        final ref = _db.collection('notifications').doc();
        batch.set(ref, {
          'userId': u.id, 'title': title, 'body': body,
          'type': type, 'read': false, 'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      // Also send FCM push to all
      for (final u in users.docs) {
        final token = u.data()['fcmToken'] as String?;
        if (token == null || token.isEmpty) continue;
        await http.post(
          Uri.parse('https://fcm.googleapis.com/fcm/send'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'key=$_fcmServerKey'},
          body: jsonEncode({'to': token, 'priority': 'high',
            'notification': {'title': title, 'body': body, 'sound': 'default'}}),
        );
      }
      return true;
    } catch (e) {
      debugPrint('broadcastToAllUsers error: $e');
      return false;
    }
  }

  Future<bool> broadcastToRole({
    required String role,
    required String title,
    required String body,
    String type = 'general',
  }) async {
    try {
      final users = await _db.collection('users').where('role', isEqualTo: role).get();
      final batch = _db.batch();
      for (final u in users.docs) {
        final ref = _db.collection('notifications').doc();
        batch.set(ref, {
          'userId': u.id, 'title': title, 'body': body,
          'type': type, 'read': false, 'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('broadcastToRole error: $e');
      return false;
    }
  }
  // =====================================================================
  // SEND PUSH VIA LOCAL FCM SERVER (FCM V1)
  // =====================================================================
  Future<void> sendPushNotification({
    required String token,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    try {
      await http.post(
        Uri.parse(_fcmServerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'title': title,
          'body': body,
          'data': data,
        }),
      );
    } catch (_) {}
  }
}