import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import 'admin_dashboard.dart';

class AdminPasscodeScreen extends StatefulWidget {
  final String uid;
  const AdminPasscodeScreen({super.key, required this.uid});
  @override
  State<AdminPasscodeScreen> createState() => _AdminPasscodeScreenState();
}

class _AdminPasscodeScreenState extends State<AdminPasscodeScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _code = ['', '', '', '', '', ''];   // 6-digit pad
  bool _isLoading = true;
  bool _passcodeSet = false;
  bool _isVerifying = false;
  bool _isNew = false;            // setting new passcode mode
  String _error = '';
  late AnimationController _shake;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween(begin: 0.0, end: 8.0)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shake);
    _checkPasscode();
  }

  @override
  void dispose() { _shake.dispose(); super.dispose(); }

  Future<void> _checkPasscode() async {
    final isSet = await _authService.isAdminPasscodeSet(widget.uid);
    setState(() { _passcodeSet = isSet; _isLoading = false; });
  }

  String get _entered => _code.join();
  bool get _complete => _code.every((c) => c.isNotEmpty);

  void _onDigit(String d) {
    final idx = _code.indexWhere((c) => c.isEmpty);
    if (idx == -1) return;
    setState(() { _code[idx] = d; _error = ''; });
    if (_complete) _onComplete();
  }

  void _onDelete() {
    final idx = _code.lastIndexWhere((c) => c.isNotEmpty);
    if (idx == -1) return;
    setState(() => _code[idx] = '');
  }

  void _onComplete() async {
    if (_entered.length < 6) return;
    setState(() => _isVerifying = true);
    if (_passcodeSet && !_isNew) {
      final valid = await _authService.verifyAdminPasscode(
          uid: widget.uid, passcode: _entered);
      if (!mounted) return;
      setState(() => _isVerifying = false);
      if (valid) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminDashboard()));
      } else {
        _shake.forward(from: 0);
        setState(() { _error = 'Wrong passcode'; _code.fillRange(0, 6, ''); });
      }
    } else {
      await _authService.setAdminPasscode(
          uid: widget.uid, passcode: _entered);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminDashboard()));
    }
  }

  Widget _buildDot(int i) {
    final filled = _code[i].isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: filled ? 20 : 16,
      height: filled ? 20 : 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? Colors.white : Colors.white.withOpacity(0.3),
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
        boxShadow: filled ? [BoxShadow(
            color: Colors.white.withOpacity(0.4),
            blurRadius: 8, spreadRadius: 1)] : [],
      ),
    );
  }

  Widget _padButton(String label, {bool isDelete = false, bool isEmpty = false}) {
    if (isEmpty) return const SizedBox();
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (isDelete) _onDelete(); else _onDigit(label);
      },
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDelete
              ? Colors.white.withOpacity(0.08)
              : Colors.white.withOpacity(0.15),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Center(child: isDelete
            ? const Icon(Icons.backspace_rounded,
            color: Colors.white, size: 22)
            : Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 24,
            fontWeight: FontWeight.w700))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(
        body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFF7B1FA2)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(child: Column(children: [
          const SizedBox(height: 40),
          // Shield icon
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.15),
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
            ),
            child: const Center(child: Icon(Icons.admin_panel_settings_rounded,
                color: Colors.white, size: 40)),
          ),
          const SizedBox(height: 20),
          Text(
            _passcodeSet && !_isNew ? 'Admin Passcode' : 'Create Passcode',
            style: const TextStyle(color: Colors.white, fontSize: 22,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            _passcodeSet && !_isNew
                ? 'Enter your 6-digit passcode'
                : 'Set a secure 6-digit passcode',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
          ),
          const SizedBox(height: 36),
          // Dots
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(_shakeAnim.value *
                  (_shake.status == AnimationStatus.forward ? 1 : -1), 0),
              child: child,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _buildDot(i)))),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error, style: const TextStyle(
                color: Color(0xFFFF8A80), fontSize: 13,
                fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 40),
          // Numpad
          if (_isVerifying)
            const CircularProgressIndicator(color: Colors.white)
          else
            Column(children: [
              for (final row in [
                ['1','2','3'], ['4','5','6'], ['7','8','9'], ['','0','del']
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: row.map((d) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: d == 'del'
                            ? _padButton('', isDelete: true)
                            : d.isEmpty
                            ? _padButton('', isEmpty: true)
                            : _padButton(d),
                      )).toList()),
                ),
            ]),
          if (_passcodeSet && !_isNew) ...[
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => setState(() { _isNew = true; _code.fillRange(0, 6, ''); }),
              child: Text('Forgot passcode?',
                  style: TextStyle(color: Colors.white.withOpacity(0.6),
                      fontSize: 13)),
            ),
          ],
        ])),
      ),
    );
  }
}