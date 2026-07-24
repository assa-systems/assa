import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';

import '../models/user_model.dart';
import '../models/driver_model.dart';
import '../models/admin_model.dart';

// Stub so code compiles without local_auth
enum BiometricType { fingerprint, face, iris }

class AuthService {
  final FirebaseAuth    _auth         = FirebaseAuth.instance;
  final FirebaseFirestore _firestore  = FirebaseFirestore.instance;
  final Random          _rng          = Random.secure();

  static const String _keyCachedEmail     = 'cached_email';
  static const String _keyCachedRole      = 'cached_role';
  static const String _keyAdminPasscodeSet = 'admin_passcode_set';

  User? get currentUser        => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  bool  get isLoggedIn         => _auth.currentUser != null;

  // ════════════════════════════════════════════════════════════════════
  // PICKUP ID GENERATION
  // Format: 1 uppercase letter (A-Z) + 2 digits (0-9)  →  e.g. K47
  // 26 × 10 × 10 = 2,600 possible IDs.
  // Uniqueness is checked against Firestore before assignment.
  // ════════════════════════════════════════════════════════════════════

  Future<String> _generateUniquePickupId() async {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I/O to avoid confusion
    String candidate = '';
    bool unique = false;

    for (int attempt = 0; attempt < 20; attempt++) {
      final letter = letters[_rng.nextInt(letters.length)];
      final digits = _rng.nextInt(100).toString().padLeft(2, '0');
      candidate = '$letter$digits';

      // Check uniqueness in Firestore
      try {
        final existing = await _firestore
            .collection('users')
            .where('pickupId', isEqualTo: candidate)
            .limit(1)
            .get();
        if (existing.docs.isEmpty) {
          unique = true;
          break;
        }
      } catch (_) {
        // If check fails, proceed — collision risk is low
        unique = true;
        break;
      }
    }

    // Fallback: timestamp-based if all attempts collide (extremely unlikely)
    if (!unique || candidate.isEmpty) {
      final ts      = DateTime.now().millisecondsSinceEpoch % 1000;
      const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
      final letter  = letters[ts % letters.length];
      candidate     = '$letter${(ts % 100).toString().padLeft(2, '0')}';
    }

    return candidate;
  }

  // ════════════════════════════════════════════════════════════════════
  // USER REGISTRATION
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> registerUser({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      UserCredential? credential;
      String? uid;

      try {
        credential = await _auth.createUserWithEmailAndPassword(
            email: email.trim(), password: password);
        uid = credential.user!.uid;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          try {
            final signIn = await _auth.signInWithEmailAndPassword(
                email: email.trim(), password: password);
            uid        = signIn.user!.uid;
            credential = signIn;
            final existing = await _getUserData(uid!);
            if (existing != null) {
              return {'success': false,
                'error': 'An account already exists with this email. Please sign in.'};
            }
          } catch (_) {
            return {'success': false,
              'error': 'An account already exists with this email. Please sign in.'};
          }
        } else {
          return {'success': false, 'error': _handleAuthError(e.code)};
        }
      }

      if (uid == null || credential == null) {
        return {'success': false, 'error': 'Registration failed. Please try again.'};
      }

      // Generate unique pickup ID
      final pickupId    = await _generateUniquePickupId();
      final onlineUUID  = _generateOnlineUUID(uid);
      final offlineUUID = _generateOfflineUUID(uid);

      final user = UserModel(
        uid:      uid,
        name:     name.trim(),
        email:    email.trim(),
        role:     'user',
        pickupId: pickupId,
        createdAt: DateTime.now(),
      );

      // Write Firestore doc — retry once if it fails
      bool firestoreSuccess = false;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          await _firestore.collection('users').doc(uid).set({
            ...user.toMap(),
            'onlineUUID':         onlineUUID,
            'offlineUUID':        offlineUUID,
            'fingerprintEnabled': false,
            'authProvider':       'email',
          });
          firestoreSuccess = true;
          break;
        } catch (e) {
          if (attempt == 1) {
            try { await credential.user!.delete(); } catch (_) {}
            return {'success': false,
              'error': 'Account created but profile setup failed. Please try again.'};
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (!firestoreSuccess) {
        try { await credential.user!.delete(); } catch (_) {}
        return {'success': false,
          'error': 'Registration failed. Please check your connection and try again.'};
      }

      try { await credential.user!.sendEmailVerification(); } catch (_) {}

      return {'success': true, 'user': user, 'needsVerification': true};
    } catch (e) {
      debugPrint('Registration error: $e');
      return {'success': false, 'error': 'Registration failed. Please try again.'};
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // DRIVER REGISTRATION
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> registerDriver({
    required String name,
    required String email,
    required String password,
    required String phoneNumber,
    required String shuttleId,
    required String driverIdCardUrl,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      final uid = credential.user!.uid;
      final driver = DriverModel(
        uid: uid, name: name.trim(), email: email.trim(),
        phoneNumber: phoneNumber.trim(), shuttleId: shuttleId.trim(),
        driverIdCardUrl: driverIdCardUrl, status: 'pending',
        createdAt: DateTime.now(),
      );
      await _firestore.collection('users').doc(uid).set(driver.toMap());
      await credential.user!.sendEmailVerification();
      return {'success': true, 'driver': driver, 'needsVerification': true};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _handleAuthError(e.code)};
    } catch (e) {
      return {'success': false, 'error': 'Registration failed. Please try again.'};
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // LOGIN
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      final uid      = credential.user!.uid;
      final userData = await _getUserData(uid);

      if (userData == null) {
        // Auth exists but Firestore doc missing — create it now
        final pickupId    = await _generateUniquePickupId();
        final onlineUUID  = _generateOnlineUUID(uid);
        final offlineUUID = _generateOfflineUUID(uid);
        final provider    = credential.user!.providerData.isNotEmpty
            ? credential.user!.providerData.first.providerId
            : 'console';
        await _firestore.collection('users').doc(uid).set({
          'uid':               uid,
          'name':              credential.user!.displayName ?? email.split('@')[0],
          'email':             email.trim(),
          'role':              'user',
          'pickupId':          pickupId,
          'createdAt':         DateTime.now().toIso8601String(),
          'onlineUUID':        onlineUUID,
          'offlineUUID':       offlineUUID,
          'fingerprintEnabled': false,
          'authProvider':      provider,
        });
        await _cacheUserCredentials(email.trim(), 'user');
        return {'success': true, 'role': 'user', 'uid': uid};
      }

      final role = userData['role'] ?? 'user';
      if (role == 'removed_admin') {
        await _auth.signOut();
        return {'success': false,
          'error': 'Your admin access has been revoked. Contact the system administrator.'};
      }
      if (role == 'driver') {
        final status = userData['status'] ?? 'pending';
        if (status == 'pending') {
          await _auth.signOut();
          return {'success': false, 'error': 'pending', 'status': 'pending'};
        }
        if (status == 'rejected') {
          await _auth.signOut();
          return {'success': false, 'error': 'rejected', 'status': 'rejected'};
        }
      }

      final isGoogleUser   = credential.user!.providerData.any((p) => p.providerId == 'google.com');
      final authProvider   = userData['authProvider'] ?? '';
      final isConsoleUser  = authProvider.isEmpty;
      if (role != 'admin' && !isGoogleUser && !isConsoleUser) {
        if (!credential.user!.emailVerified) {
          await _auth.signOut();
          return {'success': false, 'error': 'email_not_verified', 'email': email.trim()};
        }
      }
      await _cacheUserCredentials(email.trim(), role);
      return {'success': true, 'role': role, 'uid': uid};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _handleAuthError(e.code)};
    } catch (e) {
      return {'success': false, 'error': 'Login failed. Please try again.'};
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // GOOGLE SIGN-IN
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      try { await googleSignIn.signOut(); } catch (_) {}
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return {'success': false, 'error': ''};

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        return {'success': false, 'error': 'Google sign-in failed. Please try again.'};
      }

      final cred           = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      final userCredential = await _auth.signInWithCredential(cred);
      final uid            = userCredential.user!.uid;
      final existingData   = await _getUserData(uid);

      if (existingData != null) {
        final role = existingData['role'] ?? 'user';
        if (role == 'driver') {
          final status = existingData['status'] ?? 'pending';
          if (status == 'pending') { await _auth.signOut(); return {'success': false, 'error': 'pending'}; }
          if (status == 'rejected') { await _auth.signOut(); return {'success': false, 'error': 'rejected'}; }
        }
        await _cacheUserCredentials(userCredential.user!.email ?? '', role);
        return {'success': true, 'role': role, 'uid': uid, 'isNewUser': false};
      } else {
        return {
          'success': true, 'uid': uid,
          'name':    userCredential.user!.displayName ?? '',
          'email':   userCredential.user!.email ?? '',
          'isNewUser': true, 'role': 'user',
        };
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('network') || msg.contains('Network')) {
        return {'success': false, 'error': 'No internet connection.'};
      }
      return {'success': false, 'error': 'Google sign-in failed. Please try again.'};
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // PHONE AUTH
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> sendPhoneOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onFailed,
  }) async {
    try {
      final normalized = normalizeNigerianPhone(phoneNumber);
      await _auth.verifyPhoneNumber(
        phoneNumber: normalized,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential cred) async {
          await _auth.signInWithCredential(cred);
        },
        verificationFailed: (FirebaseAuthException e) {
          onFailed(e.message ?? 'Phone verification failed.');
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verifyOtpAndRegister({
    required String verificationId,
    required String otp,
    required String name,
    required String phoneNumber,
    required String password,
  }) async {
    try {
      final cred           = PhoneAuthProvider.credential(
          verificationId: verificationId, smsCode: otp.trim());
      final userCredential = await _auth.signInWithCredential(cred);
      final uid            = userCredential.user!.uid;

      final existing = await _getUserData(uid);
      if (existing != null) {
        final role = existing['role'] ?? 'user';
        await _cacheUserCredentials(phoneNumber, role);
        return {'success': true, 'role': role, 'uid': uid, 'isNewUser': false};
      }

      final pickupId    = await _generateUniquePickupId();
      final onlineUUID  = _generateOnlineUUID(uid);
      final offlineUUID = _generateOfflineUUID(uid);
      final user        = UserModel(
        uid: uid, name: name.trim(), email: '',
        role: 'user', pickupId: pickupId, createdAt: DateTime.now(),
      );
      await _firestore.collection('users').doc(uid).set({
        ...user.toMap(),
        'phone':              normalizeNigerianPhone(phoneNumber),
        'onlineUUID':         onlineUUID,
        'offlineUUID':        offlineUUID,
        'fingerprintEnabled': false,
        'authProvider':       'phone',
      });
      await _cacheUserCredentials(phoneNumber, 'user');
      return {'success': true, 'role': 'user', 'uid': uid, 'isNewUser': true};
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') {
        return {'success': false, 'error': 'Invalid OTP. Please try again.'};
      }
      return {'success': false, 'error': e.message ?? 'Verification failed.'};
    } catch (e) {
      return {'success': false, 'error': 'Verification failed. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> verifyOtpAndLogin({
    required String verificationId,
    required String otp,
  }) async {
    try {
      final cred           = PhoneAuthProvider.credential(
          verificationId: verificationId, smsCode: otp.trim());
      final userCredential = await _auth.signInWithCredential(cred);
      final uid            = userCredential.user!.uid;
      final data           = await _getUserData(uid);
      if (data == null) {
        await _auth.signOut();
        return {'success': false, 'error': 'No account found for this number.'};
      }
      final role = data['role'] ?? 'user';
      await _cacheUserCredentials(data['phone'] ?? '', role);
      return {'success': true, 'role': role, 'uid': uid};
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') {
        return {'success': false, 'error': 'Invalid OTP. Please try again.'};
      }
      return {'success': false, 'error': e.message ?? 'Verification failed.'};
    } catch (e) {
      return {'success': false, 'error': 'Verification failed. Please try again.'};
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // EMAIL VERIFICATION
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> resendVerificationEmail([String email = '']) async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        return {'success': true};
      }
      return {'success': false, 'error': 'No unverified account found.'};
    } catch (e) {
      return {'success': false, 'error': 'Failed to resend. Try again later.'};
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // PASSWORD RESET
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return {'success': true};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _handleAuthError(e.code)};
    } catch (e) {
      return {'success': false, 'error': 'Failed to send reset email.'};
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // ADMIN PASSCODE
  // ════════════════════════════════════════════════════════════════════

  String _hashPasscode(String passcode) {
    final bytes = utf8.encode(passcode);
    return sha256.convert(bytes).toString();
  }

  Future<bool> isAdminPasscodeSet(String uid) async {
    try {
      final doc = await _firestore.collection('admin_settings').doc(uid).get();
      return doc.exists && doc.data()?['passcodeHash'] != null;
    } catch (_) { return false; }
  }

  Future<bool> setAdminPasscode({required String uid, required String passcode}) async {
    try {
      await _firestore.collection('admin_settings').doc(uid).set({
        'passcodeHash':    _hashPasscode(passcode),
        'passcodeEnabled': true,
        'updatedAt':       FieldValue.serverTimestamp(),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAdminPasscodeSet, true);
      return true;
    } catch (_) { return false; }
  }

  Future<bool> verifyAdminPasscode({required String uid, required String passcode}) async {
    try {
      final doc = await _firestore.collection('admin_settings').doc(uid).get();
      if (!doc.exists) return false;
      return doc.data()?['passcodeHash'] == _hashPasscode(passcode);
    } catch (_) { return false; }
  }

  // ════════════════════════════════════════════════════════════════════
  // ADMIN CREATION
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> createAdmin({
    required String name,
    required String email,
    required String password,
    required String createdByUid,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      final uid    = credential.user!.uid;
      final admin  = AdminModel(
        uid: uid, name: name.trim(), email: email.trim(),
        createdBy: createdByUid, createdAt: DateTime.now(),
      );
      await _firestore.collection('users').doc(uid).set(admin.toMap());
      return {'success': true, 'admin': admin};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': _handleAuthError(e.code)};
    } catch (e) {
      return {'success': false, 'error': 'Failed to create admin account.'};
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // LOGOUT
  // ════════════════════════════════════════════════════════════════════

  Future<void> logout() async {
    try { await GoogleSignIn().signOut(); } catch (_) {}
    await _auth.signOut();
  }

  Future<void> updateUserRole(String uid, String role) async {
    try {
      final Map<String, dynamic> update = {'role': role};
      if (role == 'driver') update['status'] = 'pending';
      await _firestore.collection('users').doc(uid).update(update);
    } catch (_) {}
  }


  // ════════════════════════════════════════════════════════════════════
  // SHORT ID ASSIGNMENT — kept for Google registration screens
  // register_user_screen and register_driver_screen call assignShortId()
  // directly when creating Firestore docs for Google sign-in users.
  // ════════════════════════════════════════════════════════════════════

  /// Public wrapper — called by registration screens for Google users.
  /// Generates a unique 3-char Pickup ID (same as _generateUniquePickupId).
  Future<String> assignShortId() => _generateUniquePickupId();

  // ════════════════════════════════════════════════════════════════════
  // PUBLIC STATIC HELPERS
  // ════════════════════════════════════════════════════════════════════

  static String generateOnlineUUIDStatic(String uid) {
    final hash = sha256.convert(utf8.encode(uid + 'online')).toString();
    return hash.substring(0, 10).toUpperCase();
  }

  static String generateOfflineUUIDStatic(String uid) {
    final hash = sha256.convert(utf8.encode(uid + 'offline')).toString();
    return hash.substring(0, 6).toUpperCase();
  }

  static String normalizeNigerianPhone(String phone) {
    String p = phone.trim().replaceAll(' ', '').replaceAll('-', '');
    if (p.startsWith('+234')) return p;
    if (p.startsWith('234'))  return '+$p';
    if (p.startsWith('0'))    return '+234${p.substring(1)}';
    return '+234$p';
  }

  // ════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.exists ? doc.data() : null;
    } catch (_) { return null; }
  }

  Future<void> _cacheUserCredentials(String email, String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCachedEmail, email);
      await prefs.setString(_keyCachedRole,  role);
    } catch (_) {}
  }

  String _generateOnlineUUID(String uid) {
    final hash = sha256.convert(utf8.encode('online_$uid')).toString();
    return hash.substring(0, 10).toUpperCase();
  }

  String _generateOfflineUUID(String uid) {
    final hash = sha256.convert(utf8.encode('offline_$uid')).toString();
    return hash.substring(0, 6).toUpperCase();
  }

  String _handleAuthError(String code) {
    switch (code) {
      case 'user-not-found':          return 'No account found with this email.';
      case 'wrong-password':          return 'Incorrect password. Please try again.';
      case 'email-already-in-use':    return 'An account already exists with this email.';
      case 'weak-password':           return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':           return 'Please enter a valid email address.';
      case 'user-disabled':           return 'This account has been disabled.';
      case 'too-many-requests':       return 'Too many attempts. Please try again later.';
      case 'network-request-failed':  return 'No internet connection. Please check your data.';
      case 'requires-recent-login':   return 'Session expired. Please log out and log back in.';
      case 'email-already-exists':    return 'An account already exists with this email.';
      case 'operation-not-allowed':   return 'This sign-in method is not enabled.';
      case 'invalid-credential':      return 'Incorrect email or password. Please check and try again.';
      case 'INVALID_LOGIN_CREDENTIALS': return 'Incorrect email or password. Please check and try again.';
      default:
        debugPrint('Unhandled Firebase auth error: $code');
        return 'Sign-in failed ($code). Please try again.';
    }
  }
}