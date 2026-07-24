import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/login_screen.dart';
import '../admin/admin_dashboard.dart';
import '../user/user_dashboard.dart';
import '../driver/driver_dashboard.dart';
import '../driver/driver_pending_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _pulseController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startSequence();
  }

  void _setupAnimations() {
    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _textController, curve: Curves.easeIn));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic));
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    await _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    await _textController.forward();
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) _navigate();
  }

  Future<void> _navigate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _goTo(const LoginScreen()); return; }
    try {
      DocumentSnapshot? doc;
      try {
        doc = await FirebaseFirestore.instance.collection('users').doc(user.uid)
            .get(const GetOptions(source: Source.cache));
      } catch (_) { doc = null; }
      if (doc == null || !doc.exists) {
        try {
          doc = await FirebaseFirestore.instance.collection('users').doc(user.uid)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 3));
        } catch (_) { _goTo(const UserDashboard()); return; }
      }
      if (!doc.exists) { _goTo(const LoginScreen()); return; }
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final role = data['role'] ?? 'user';
      if (role == 'driver') {
        final status = data['status'] ?? 'pending';
        _goTo(status == 'approved' ? const DriverDashboard() : DriverPendingScreen(status: status));
        return;
      }
      switch (role) {
        case 'admin': _goTo(const AdminDashboard()); break;
        case 'user':  _goTo(const UserDashboard());  break;
        default:      _goTo(const LoginScreen());
      }
    } catch (_) { _goTo(const UserDashboard()); }
  }

  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 600),
    ));
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF082F6E), Color(0xFF051E4A)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Positioned(top: -80, right: -80, child: Container(width: 300, height: 300,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.04)))),
          Positioned(bottom: -60, left: -60, child: Container(width: 250, height: 250,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.04)))),
          Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AnimatedBuilder(
                animation: Listenable.merge([_logoController, _pulseController]),
                builder: (context, child) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(scale: _logoScale.value * _pulseAnimation.value, child: child),
                ),
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.12),
                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                    boxShadow: [BoxShadow(color: const Color(0xFF00BCD4).withOpacity(0.4), blurRadius: 40, spreadRadius: 10)],
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/icons/app_icon.png', fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.directions_bus_rounded, size: 60, color: Colors.white)),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              AnimatedBuilder(
                animation: _textController,
                builder: (context, child) => SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(opacity: _textOpacity, child: child),
                ),
                child: Column(children: [
                  const Text('ASSA', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 8)),
                  const SizedBox(height: 8),
                  Container(width: 60, height: 3, decoration: BoxDecoration(color: const Color(0xFF00BCD4), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  const Text('AFIT Shuttle Service App', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xCCFFFFFF), letterSpacing: 1.5)),
                ]),
              ),
            ]),
          ),
          Positioned(
            bottom: 48, left: 0, right: 0,
            child: AnimatedBuilder(
              animation: _textController,
              builder: (context, child) => FadeTransition(opacity: _textOpacity, child: child),
              child: const Column(children: [
                Text('Your campus ride, simplified.', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0x99FFFFFF), letterSpacing: 0.5)),
                SizedBox(height: 8),
                Text('Air Force Institute of Technology', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0x66FFFFFF), letterSpacing: 0.3)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.03)..strokeWidth = 1;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    for (double y = 0; y < size.height; y += spacing) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}