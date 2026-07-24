import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/widgets/common/common_widgets.dart';
import 'package:assa/widgets/common/ad_overlay.dart';

// ════════════════════════════════════════════════════════════════════
// BLOCK ARRANGE SCREEN
//
// A 4x4 grid of numbered blocks (1-16) in random order. Tap two blocks
// to swap their positions — no adjacency/blank-tile restriction, unlike
// the sliding Puzzle game. Goal: arrange all 16 blocks in ascending
// order (top-left to bottom-right) in as few swaps as possible.
//
// Scoring mirrors the Puzzle game: fewer swaps = higher score, saved to
// game_scores/{uid}.block_weeklyPoints and game_leaderboard for the
// Game Hub weekly totals.
// ════════════════════════════════════════════════════════════════════

class BlockArrangeScreen extends StatefulWidget {
  const BlockArrangeScreen({super.key});
  @override
  State<BlockArrangeScreen> createState() => _BlockArrangeScreenState();
}

class _BlockArrangeScreenState extends State<BlockArrangeScreen> {
  static const int gridSize = 4;
  static const int tileCount = gridSize * gridSize;
  static const int baseBlockPoints = 1000;

  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  String _userName = '';

  List<int> _blocks = [];
  int? _selectedIndex;
  int _swaps = 0;
  int _seconds = 0;
  bool _started = false;
  bool _solved = false;
  bool _submitting = false;
  Timer? _timer;

  static String get _weekKey {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final week = ((monday.difference(DateTime(monday.year, 1, 1)).inDays +
        DateTime(monday.year, 1, 1).weekday -
        1) ~/
        7) +
        1;
    return '${monday.year}-W$week';
  }

  static String get _monthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _newGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    if (_uid.isEmpty) return;
    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      if (mounted) setState(() => _userName = doc.data()?['name'] ?? 'User');
    } catch (_) {}
  }

  void _newGame() {
    final rng = Random();
    List<int> b;
    do {
      b = List.generate(tileCount, (i) => i + 1)..shuffle(rng);
    } while (_isSolved(b));
    _timer?.cancel();
    setState(() {
      _blocks = b;
      _selectedIndex = null;
      _swaps = 0;
      _seconds = 0;
      _solved = false;
      _started = true;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  bool _isSolved(List<int> blocks) {
    for (int i = 0; i < blocks.length; i++) {
      if (blocks[i] != i + 1) return false;
    }
    return true;
  }

  void _onBlockTap(int index) {
    if (!_started || _solved) return;
    if (_selectedIndex == null) {
      setState(() => _selectedIndex = index);
      return;
    }
    if (_selectedIndex == index) {
      setState(() => _selectedIndex = null);
      return;
    }
    setState(() {
      final a = _selectedIndex!;
      final tmp = _blocks[a];
      _blocks[a] = _blocks[index];
      _blocks[index] = tmp;
      _swaps++;
      _selectedIndex = null;
    });
    if (_isSolved(_blocks)) {
      _timer?.cancel();
      setState(() => _solved = true);
      Future.delayed(const Duration(milliseconds: 250), _onSolved);
    }
  }

  int _calculateScore() {
    if (_swaps == 0) return baseBlockPoints;
    final score =
    (baseBlockPoints / _swaps * 8).clamp(10.0, baseBlockPoints.toDouble());
    return score.round().clamp(1, baseBlockPoints);
  }

  Future<void> _onSolved() async {
    final score = _calculateScore();
    setState(() => _submitting = true);
    if (_uid.isNotEmpty) {
      try {
        final wk = _weekKey;
        final mk = _monthKey;
        await FirebaseFirestore.instance
            .collection('game_scores')
            .doc(_uid)
            .set({
          'userId': _uid,
          'userName': _userName,
          'block_weeklyPoints': FieldValue.increment(score),
          'block_monthlyPoints': FieldValue.increment(score),
          'block_weekKey': wk,
          'block_monthKey': mk,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final lbRef = FirebaseFirestore.instance
            .collection('game_leaderboard')
            .doc('block_${wk}_$_uid');
        await lbRef.set({
          'userId': _uid,
          'userName': _userName,
          'gameType': 'block',
          'points': FieldValue.increment(score),
          'weekKey': wk,
          'monthKey': mk,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _submitting = false);
      _showSolvedDialog(score);
    }
  }

  void _showSolvedDialog(int score) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              const Text('Blocks Arranged!',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Text('Swaps: $_swaps  ·  Score: $score pts',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              CustomButton(
                text: 'Play Again',
                onPressed: () {
                  Navigator.pop(ctx);
                  _newGame();
                },
                icon: Icons.replay_rounded,
                backgroundColor: const Color(0xFF00897B),
              ),
              const SizedBox(height: 8),
              CustomButton(
                text: 'Done',
                onPressed: () async {
                  await showFullScreenAd(context);
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  }
                },
                isOutlined: true,
                backgroundColor: Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(int secs) {
    final m = secs ~/ 60, s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildStatsBar(),
                    const SizedBox(height: 16),
                    _buildGrid(),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _newGame,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('New Game'),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF00897B)),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                    const SizedBox(height: 20),
                    _buildHowToPlay(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF00897B), Color(0xFF00695C)]),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Block Arrange',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                Text('Tap two blocks to swap them into order',
                    style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatChip(Icons.swap_horiz_rounded, 'Swaps', '$_swaps',
              const Color(0xFF00897B)),
          Container(width: 1, height: 36, color: AppColors.divider),
          _StatChip(Icons.timer_outlined, 'Time', _fmt(_seconds),
              AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final screenW = MediaQuery.of(context).size.width - 32;
    final size = screenW;
    final tileSize = size / gridSize;

    return SizedBox(
      width: size,
      height: size,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridSize,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: tileCount,
        itemBuilder: (context, index) {
          final value = _blocks[index];
          final isSelected = _selectedIndex == index;
          final isCorrect = value == index + 1;
          return GestureDetector(
            onTap: () => _onBlockTap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isSelected
                      ? [const Color(0xFF64B5F6), const Color(0xFF1976D2)]
                      : isCorrect
                      ? [const Color(0xFF66BB6A), const Color(0xFF2E7D32)]
                      : [const Color(0xFF00897B), const Color(0xFF00695C)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(1, 2)),
                ],
              ),
              child: Center(
                child: Text('$value',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: tileSize * 0.32,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHowToPlay() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How to Play',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
            '• Tap a block to select it, then tap another to swap them\n'
                '• Arrange all 16 blocks from 1 to 16, left to right, top to bottom\n'
                '• Green blocks are already in the correct spot\n'
                '• Fewer swaps = higher score',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _StatChip(this.icon, this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(value,
            style:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
      ],
    );
  }
}