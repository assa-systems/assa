import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/widgets/common/common_widgets.dart';
import 'package:assa/widgets/common/ad_overlay.dart';

// ════════════════════════════════════════════════════════════════════
// TAP CHALLENGE SCREEN
// A target circle moves around the screen for 30 seconds.
// Tapping it scores points (faster target = more points per tap).
// Target shrinks and speeds up as time progresses.
// After game: show score + optional ad boost.
// ════════════════════════════════════════════════════════════════════

class TapChallengeScreen extends StatefulWidget {
  const TapChallengeScreen({super.key});
  @override
  State<TapChallengeScreen> createState() => _TapChallengeScreenState();
}

class _TapChallengeScreenState extends State<TapChallengeScreen>
    with SingleTickerProviderStateMixin {

  final String _uid      = FirebaseAuth.instance.currentUser?.uid ?? '';
  String       _userName = '';

  // Game state
  bool   _gameStarted = false;
  bool   _gameOver    = false;
  int    _timeLeft    = 30;
  int    _tapCount    = 0;
  int    _roundScore  = 0;
  Timer? _gameTimer;

  // Target position
  double _targetX     = 100;
  double _targetY     = 200;
  double _targetSize  = 72;
  Timer? _moveTimer;
  final  _rng = Random();

  // Play area size — set on first layout
  double _areaW = 300;
  double _areaH = 400;

  // Ad boost
  int  _adBoostsUsed = 0;
  bool _adLoading    = false;

  // Pulse animation for target
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  static const int _maxBoostsPerDay = 4;
  static const int _boostPoints     = 50;
  static const int _gameDuration    = 30;

  static String get _weekKey {
    final now    = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final week   = ((monday.difference(DateTime(monday.year, 1, 1)).inDays +
        DateTime(monday.year, 1, 1).weekday - 1) ~/ 7) + 1;
    return '${monday.year}-W$week';
  }

  static String get _monthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadUserData();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _moveTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(_uid).get();
      _userName = userDoc.data()?['name'] ?? 'User';

      final scoreDoc = await FirebaseFirestore.instance
          .collection('game_scores').doc(_uid).get();
      final data = scoreDoc.data() ?? {};
      final boostDate = data['adBoostDate'] as String? ?? '';
      if (mounted) {
        setState(() {
          _adBoostsUsed = boostDate == _todayKey
              ? (data['adBoostsToday'] as int? ?? 0) : 0;
        });
      }
    } catch (_) {}
  }

  void _startGame() {
    setState(() {
      _gameStarted = true;
      _gameOver    = false;
      _timeLeft    = _gameDuration;
      _tapCount    = 0;
      _roundScore  = 0;
      _targetSize  = 72;
    });
    _moveTarget();
    _startGameTimer();
  }

  void _startGameTimer() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _timeLeft--);
      // Speed up and shrink target every 10s
      if (_timeLeft == 20) {
        setState(() => _targetSize = 60);
        _startMoveTimer(intervalMs: 600);
      } else if (_timeLeft == 10) {
        setState(() => _targetSize = 48);
        _startMoveTimer(intervalMs: 400);
      }
      if (_timeLeft <= 0) {
        t.cancel();
        _moveTimer?.cancel();
        _endGame();
      }
    });
  }

  void _moveTarget() => _startMoveTimer(intervalMs: 800);

  void _startMoveTimer({required int intervalMs}) {
    _moveTimer?.cancel();
    _moveTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted) return;
      final maxX = (_areaW - _targetSize).clamp(0.0, double.infinity);
      final maxY = (_areaH - _targetSize).clamp(0.0, double.infinity);
      setState(() {
        _targetX = _rng.nextDouble() * maxX;
        _targetY = _rng.nextDouble() * maxY;
      });
    });
  }

  void _onTap() {
    if (!_gameStarted || _gameOver) return;
    // Points: more for faster speed (less timeLeft = further from start)
    final elapsed = _gameDuration - _timeLeft;
    final pts = elapsed < 10 ? 3 : elapsed < 20 ? 5 : 8;
    setState(() {
      _tapCount++;
      _roundScore += pts;
    });
    // Brief target jump on tap
    _jumpTarget();
  }

  void _jumpTarget() {
    final maxX = (_areaW - _targetSize).clamp(0.0, double.infinity);
    final maxY = (_areaH - _targetSize).clamp(0.0, double.infinity);
    setState(() {
      _targetX = _rng.nextDouble() * maxX;
      _targetY = _rng.nextDouble() * maxY;
    });
  }

  Future<void> _endGame() async {
    setState(() => _gameOver = true);
    await _saveScore();
  }

  Future<void> _saveScore() async {
    if (_uid.isEmpty || _roundScore == 0) return;
    try {
      await FirebaseFirestore.instance
          .collection('game_scores').doc(_uid).set({
        'userId':              _uid,
        'userName':            _userName,
        'tap_weeklyPoints':    FieldValue.increment(_roundScore),
        'tap_monthlyPoints':   FieldValue.increment(_roundScore),
        'tap_weekKey':         _weekKey,
        'tap_monthKey':        _monthKey,
        'lastUpdated':         FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final lbRef = FirebaseFirestore.instance
          .collection('game_leaderboard')
          .doc('tap_${_weekKey}_$_uid');
      await lbRef.set({
        'userId':    _uid,
        'userName':  _userName,
        'gameType':  'tap',
        'points':    FieldValue.increment(_roundScore),
        'weekKey':   _weekKey,
        'monthKey':  _monthKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _watchAdBoost() async {
    if (_adBoostsUsed >= _maxBoostsPerDay || !mounted) return;
    setState(() => _adLoading = true);
    await showFullScreenAd(context);
    if (!mounted) return;
    setState(() { _adBoostsUsed++; _roundScore += _boostPoints; _adLoading = false; });

    try {
      final ref = FirebaseFirestore.instance.collection('game_scores').doc(_uid);
      await ref.set({
        'adBoostsToday':     _adBoostsUsed,
        'adBoostDate':       _todayKey,
        'tap_weeklyPoints':  FieldValue.increment(_boostPoints),
        'tap_monthlyPoints': FieldValue.increment(_boostPoints),
        'lastUpdated':       FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final lbRef = FirebaseFirestore.instance
          .collection('game_leaderboard')
          .doc('tap_${_weekKey}_$_uid');
      await lbRef.set({
        'points':    FieldValue.increment(_boostPoints),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🎉 +50 bonus points added!'),
        backgroundColor: Color(0xFF00897B),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A14),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: !_gameStarted
                ? _buildStartScreen()
                : _gameOver
                ? _buildResults()
                : _buildGame(),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0A1A14),
        border: Border(bottom: BorderSide(color: Color(0xFF1A2820))),
      ),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        ),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tap Challenge', style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w800)),
          Text('Tap the target as fast as you can!',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        if (_gameStarted && !_gameOver)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _timeLeft <= 10
                  ? AppColors.error.withOpacity(0.2)
                  : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _timeLeft <= 10 ? AppColors.error : Colors.transparent,
              ),
            ),
            child: Text('$_timeLeft s',
                style: TextStyle(
                    color: _timeLeft <= 10 ? AppColors.error : Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w900)),
          ),
      ]),
    );
  }

  Widget _buildStartScreen() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('👆', style: TextStyle(fontSize: 72)),
        const SizedBox(height: 24),
        const Text('Tap Challenge',
            style: TextStyle(color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        const Text(
          'A target will appear on screen.\nTap it as many times as you can in 30 seconds!\n\nThe target shrinks and speeds up over time.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 32),
        CustomButton(
          text: 'Start Game',
          onPressed: _startGame,
          backgroundColor: const Color(0xFF00897B),
          icon: Icons.play_arrow_rounded,
        ),
      ]),
    ));
  }

  Widget _buildGame() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        _areaW = constraints.maxWidth;
        _areaH = constraints.maxHeight;
        return Stack(children: [
          // Background tap area (misses don't count)
          GestureDetector(
            onTap: () {}, // absorb miss taps
            child: Container(color: const Color(0xFF0A1A14)),
          ),

          // Stats overlay
          Positioned(
            top: 8, left: 16, right: 16,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _StatChip('Taps', '$_tapCount', const Color(0xFF00C853)),
              _StatChip('Score', '$_roundScore pts', const Color(0xFFFFD700)),
            ]),
          ),

          // Target
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            left: _targetX,
            top:  _targetY,
            child: GestureDetector(
              onTap: _onTap,
              child: ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: _targetSize,
                  height: _targetSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(colors: [
                      Color(0xFF69F0AE),
                      Color(0xFF00897B),
                    ]),
                    boxShadow: [BoxShadow(
                        color: const Color(0xFF00897B).withOpacity(0.6),
                        blurRadius: 20, spreadRadius: 4)],
                  ),
                  child: const Center(child: Text('👆',
                      style: TextStyle(fontSize: 28))),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildResults() {
    final boostsLeft = _maxBoostsPerDay - _adBoostsUsed;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        const Text('Time\'s Up! ⏱️',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 24,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 28),

        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2820),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2A3830)),
          ),
          child: Column(children: [
            _ResultStatTap('Total Taps',  '$_tapCount',         Icons.touch_app_rounded, const Color(0xFF00C853)),
            const SizedBox(height: 12),
            _ResultStatTap('Score',       '$_roundScore pts',   Icons.stars_rounded,     const Color(0xFFFFD700)),
            const SizedBox(height: 12),
            _ResultStatTap('Ad Boosts',   '$_adBoostsUsed / $_maxBoostsPerDay', Icons.play_circle_rounded, const Color(0xFF00897B)),
          ]),
        ),
        const SizedBox(height: 24),

        if (boostsLeft > 0) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00897B).withOpacity(0.4)),
            ),
            child: Column(children: [
              Row(children: [
                const Text('📺', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Boost your score!',
                      style: TextStyle(color: Colors.white,
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('$boostsLeft left today · +$_boostPoints pts each',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ])),
              ]),
              const SizedBox(height: 12),
              CustomButton(
                text:      _adLoading ? 'Loading ad...' : 'Watch Ad · +$_boostPoints pts',
                onPressed: _adLoading ? null : _watchAdBoost,
                isLoading: _adLoading,
                backgroundColor: const Color(0xFF00897B),
                icon: _adLoading ? null : Icons.play_arrow_rounded,
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        CustomButton(
          text:      'Play Again',
          onPressed: _startGame,
          backgroundColor: const Color(0xFF00897B),
          icon: Icons.replay_rounded,
        ),
        const SizedBox(height: 12),
        CustomButton(
          text:       'Done',
          onPressed:  () => Navigator.pop(context),
          isOutlined: true,
          backgroundColor: Colors.white54,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 18,
          fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
    ]),
  );
}

class _ResultStatTap extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _ResultStatTap(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 20),
    const SizedBox(width: 10),
    Expanded(child: Text(label,
        style: const TextStyle(color: Colors.white54, fontSize: 13))),
    Text(value, style: TextStyle(color: color, fontSize: 14,
        fontWeight: FontWeight.w800)),
  ]);
}