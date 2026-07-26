import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../admin/admin_passcode_screen.dart';
import '../user/user_dashboard.dart';
import '../driver/driver_dashboard.dart';
import '../driver/driver_pending_screen.dart';
import 'register_user_screen.dart';
import 'register_driver_screen.dart';
import 'otp_screen.dart';
import 'email_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  bool _isGoogleLoading = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
            CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic));
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────
  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => screen));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  // ── Handle any auth result ──────────────────────────────────────────
  void _handleAuthResult(Map<String, dynamic> result, {String email = ''}) {
    if (!mounted) return;
    if (result['success'] == true) {
      final role = result['role'] as String;
      final uid  = result['uid']  as String;
      switch (role) {
        case 'admin':  _goTo(AdminPasscodeScreen(uid: uid)); break;
        case 'user':   _goTo(const UserDashboard());         break;
        case 'driver': _goTo(const DriverDashboard());       break;
        default:       _goTo(const LoginScreen());
      }
    } else {
      final error = result['error'] ?? '';
      if (error == 'email_not_verified') {
        _goTo(EmailVerificationScreen(email: result['email'] ?? email));
      } else if (error == 'pending') {
        _goTo(const DriverPendingScreen(status: 'pending'));
      } else if (error == 'rejected') {
        _goTo(const DriverPendingScreen(status: 'rejected'));
      } else {
        _showError(error.isNotEmpty ? error : 'Login failed. Please try again.');
      }
    }
  }

  // ── Google Sign-In ──────────────────────────────────────────────────
  Future<void> _googleSignIn() async {
    setState(() => _isGoogleLoading = true);
    final result = await _authService.signInWithGoogle();
    if (!mounted) return;
    setState(() => _isGoogleLoading = false);

    // New user via Google → show role picker before registering
    if (result['success'] == true && result['isNewUser'] == true) {
      _showRolePicker(
        uid:       result['uid']   as String,
        name:      result['name']  as String? ?? '',
        email:     result['email'] as String? ?? '',
        googleUid: result['uid']   as String,
      );
      return;
    }
    _handleAuthResult(result);
  }

  // ── Role picker for new Google users ───────────────────────────────
  void _showRolePicker({required String uid, String name = '', String email = '', String googleUid = ''}) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          const Text('One more step',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                  color: Color(0xFF0D47A1))),
          const SizedBox(height: 8),
          Text('How will you be using ASSA?',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: _RoleOption(
              icon: Icons.person_rounded,
              label: 'I\'m a User',
              subtitle: 'Book shuttle rides',
              color: const Color(0xFF1565C0),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushReplacement(context,
                    MaterialPageRoute(
                        builder: (_) => RegisterUserScreen(
                          googleName: name,
                          googleEmail: email,
                          googleUid: uid,
                        )));
              },
            )),
            const SizedBox(width: 16),
            Expanded(child: _RoleOption(
              icon: Icons.drive_eta_rounded,
              label: 'I\'m a Driver',
              subtitle: 'Drive the shuttle',
              color: const Color(0xFF00897B),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushReplacement(context,
                    MaterialPageRoute(
                        builder: (_) => RegisterDriverScreen(
                          googleName: name,
                          googleEmail: email,
                          googleUid: uid,
                        )));
              },
            )),
          ]),
        ]),
      ),
    );
  }

  // ── Phone login ────────────────────────────────────────────────────
  void _showPhoneLogin() {
    final phoneCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) {
          bool loading = false;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 20, 24, MediaQuery.of(ctx2).viewInsets.bottom + 36),
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 24),
                  const Text('Sign in with phone',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                          color: Color(0xFF0D47A1))),
                  const SizedBox(height: 4),
                  Text('We will send an OTP to verify your number',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                  const SizedBox(height: 24),
                  CustomTextField(
                      label: 'Phone Number', hint: '080 0000 0000 or +234 800 000 0000',
                      controller: phoneCtrl, keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: loading ? null : () async {
                        final phone = phoneCtrl.text.trim();
                        if (phone.isEmpty || phone.length < 10) {
                          _showError('Enter a valid phone number'); return;
                        }
                        setSt(() => loading = true);
                        String? vId;
                        await _authService.sendPhoneOtp(
                          phoneNumber: phone,
                          onCodeSent: (id) { vId = id; },
                          onFailed: (err) { if (mounted) _showError(err); },
                        );
                        setSt(() => loading = false);
                        if (vId != null && mounted) {
                          Navigator.pop(ctx2);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => OtpScreen(
                              verificationId: vId!,
                              phoneNumber: phone,
                              mode: OtpMode.login,
                            ),
                          ));
                        }
                      },
                      child: loading
                          ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                          : const Text('Send OTP',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
          );
        },
      ),
    );
  }

  // ── Email login bottom sheet ────────────────────────────────────────
  void _showEmailLogin() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => _EmailLoginSheet(
        authService: _authService,
        onResult: (result, email) {
          Navigator.pop(ctx);
          _handleAuthResult(result, email: email);
        },
        onForgotPassword: () {
          Navigator.pop(ctx);
          _showForgotPassword();
        },
      ),
    );
  }

  // ── Forgot password ─────────────────────────────────────────────────
  void _showForgotPassword() {
    final emailCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 36),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              const Text('Reset password',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: Color(0xFF0D47A1))),
              const SizedBox(height: 8),
              Text('Enter your email and we\'ll send a reset link.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 24),
              CustomTextField(label: 'Email Address', hint: 'your@email.com',
                  controller: emailCtrl, keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty || !email.contains('@')) {
                      _showError('Please enter a valid email address.');
                      return;
                    }
                    final result = await _authService.sendPasswordReset(email);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (result['success'] == true) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: const Text('Reset link sent — check your inbox.'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))));
                    } else {
                      _showError(result['error'] ?? 'Failed to send reset email.');
                    }
                  },
                  child: const Text('Send reset link',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // ── Logo ──────────────────────────────────────────
                  Center(
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      width: 140,
                      height: 140,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Welcome text ──────────────────────────────────
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome',
                            style: TextStyle(fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0D47A1))),
                        const SizedBox(height: 6),
                        Text('Sign in to continue to ASSA',
                            style: TextStyle(fontSize: 15,
                                color: Colors.grey.shade500)),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Buttons ───────────────────────────────────────
                  // Continue with Google
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isGoogleLoading ? null : _googleSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 17),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _isGoogleLoading
                          ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                          : Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 22, height: 22,
                                child: CustomPaint(
                                    painter: _GoogleLogoPainter(
                                        onDark: true))),
                            const SizedBox(width: 12),
                            const Text('Continue with Google',
                                style: TextStyle(fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Continue with Phone — Coming Soon
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade400,
                            side: BorderSide(color: Colors.grey.shade300, width: 1.8),
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            disabledForegroundColor: Colors.grey.shade400,
                          ),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.phone_outlined, size: 20,
                                    color: Colors.grey.shade400),
                                const SizedBox(width: 12),
                                Text('Continue with Phone',
                                    style: TextStyle(fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade400)),
                              ]),
                        ),
                      ),
                      Positioned(
                        top: -10, right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFA000),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Coming Soon',
                              style: TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Continue with Email
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _showEmailLogin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1565C0),
                        side: const BorderSide(
                            color: Color(0xFF1565C0), width: 1.8),
                        padding: const EdgeInsets.symmetric(vertical: 17),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.email_outlined, size: 20),
                            SizedBox(width: 12),
                            Text('Continue with Email',
                                style: TextStyle(fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Sign up link ───────────────────────────────────
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Don\'t have an account? ',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade600)),
                    GestureDetector(
                      onTap: _showRegisterPicker,
                      child: const Text('Sign up',
                          style: TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1565C0))),
                    ),
                  ]),

                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'By continuing you agree to ASSA\'s Terms of Use and Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400,
                          height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showRegisterPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          const Text('Create an account',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                  color: Color(0xFF0D47A1))),
          const SizedBox(height: 8),
          Text('Choose your role to get started',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: _RoleOption(
              icon: Icons.person_rounded,
              label: 'User',
              subtitle: 'Book shuttle rides',
              color: const Color(0xFF1565C0),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterUserScreen()));
              },
            )),
            const SizedBox(width: 16),
            Expanded(child: _RoleOption(
              icon: Icons.drive_eta_rounded,
              label: 'Driver',
              subtitle: 'Drive the shuttle',
              color: const Color(0xFF00897B),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const RegisterDriverScreen()));
              },
            )),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ── Email login bottom sheet ────────────────────────────────────────────
class _EmailLoginSheet extends StatefulWidget {
  final AuthService authService;
  final void Function(Map<String, dynamic> result, String email) onResult;
  final VoidCallback onForgotPassword;
  const _EmailLoginSheet({
    required this.authService,
    required this.onResult,
    required this.onForgotPassword,
  });
  @override
  State<_EmailLoginSheet> createState() => _EmailLoginSheetState();
}

class _EmailLoginSheetState extends State<_EmailLoginSheet> {
  final _formKey  = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final result = await widget.authService.login(
        email: _emailCtrl.text, password: _passwordCtrl.text);
    if (!mounted) return;
    setState(() => _isLoading = false);
    widget.onResult(result, _emailCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 36),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            const Text('Sign in',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                    color: Color(0xFF0D47A1))),
            const SizedBox(height: 4),
            Text('Enter your email and password',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 24),
            Form(key: _formKey, child: Column(children: [
              CustomTextField(
                  label: 'Email Address', hint: 'your@email.com',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  validator: Validators.email),
              const SizedBox(height: 14),
              CustomTextField(
                  label: 'Password', hint: 'Your password',
                  controller: _passwordCtrl,
                  isPassword: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  validator: Validators.password),
            ])),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onForgotPassword,
                child: const Text('Forgot password?',
                    style: TextStyle(color: Color(0xFF1565C0),
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                    : const Text('Sign in',
                    style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
    );
  }
}

// ── Role option card ────────────────────────────────────────────────────
class _RoleOption extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _RoleOption({required this.icon, required this.label,
    required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.25), width: 1.5),
        ),
        child: Column(children: [
          Container(width: 52, height: 52,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 26)),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(fontSize: 15,
              fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 11,
              color: Colors.grey.shade500), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ── Google G logo painter ───────────────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  final bool onDark;
  const _GoogleLogoPainter({this.onDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r  = w / 2;

    void arc(Color c, double start, double sweep) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.62),
        start, sweep, false,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.35
          ..strokeCap = StrokeCap.butt,
      );
    }

    arc(const Color(0xFF4285F4), -0.26, 1.83);
    arc(const Color(0xFF34A853),  1.57, 1.05);
    arc(const Color(0xFFFBBC05),  2.62, 0.95);
    arc(const Color(0xFFEA4335),  3.57, 1.02);

    final barColor = onDark ? Colors.white : Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(cx - 0.04 * w, cy - r * 0.18, r * 1.04, r * 0.36),
      Paint()..color = barColor..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - r * 0.18, r * 0.62, r * 0.36),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}