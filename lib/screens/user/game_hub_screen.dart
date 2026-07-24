import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/screens/user/puzzle_screen.dart';
import 'package:assa/screens/user/chess_screen.dart';
import 'package:assa/screens/user/block_arrange_screen.dart';
import 'package:assa/widgets/common/ad_overlay.dart';

// ════════════════════════════════════════════════════════════════════
// GAME HUB SCREEN
//
// Landing page for all games. Shows:
//   • Game cards → Puzzle / Quiz / Chess / Block Arrange
//   • Ad banner at bottom
// Games are purely for fun — no weekly winner or reward tracking.
//
// FIX (Part 3): Tap Challenge removed and replaced with Chess and
// Block Arrange. Unused dead-code helper _gameName() removed.
// ════════════════════════════════════════════════════════════════════

class GameHubScreen extends StatefulWidget {
  const GameHubScreen({super.key});
  @override
  State<GameHubScreen> createState() => _GameHubScreenState();
}

class _GameHubScreenState extends State<GameHubScreen> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  Map<String, dynamic>? _scores;
  bool _loading = true;
  bool _adDismissed = false;
  bool _adShownOnEntry = false;

  static const _games = [
    _GameMeta('puzzle', 'Puzzle', Icons.extension_rounded, const Color(0xFF6A1B9A)),
    _GameMeta('quiz', 'Quiz', Icons.quiz_rounded, const Color(0xFF1565C0)),
    _GameMeta('chess', 'Chess', Icons.grid_on_rounded, const Color(0xFF37474F)),
    _GameMeta('block', 'Block Arrange', Icons.view_module_rounded, const Color(0xFF00897B)),
  ];

  @override
  void initState() {
    super.initState();
    _showAdOnEntry();
    _loadData();
  }

  Future<void> _showAdOnEntry() async {
    // Small delay to allow screen to build first
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted && !_adShownOnEntry) {
      _adShownOnEntry = true;
      await showFullScreenAd(context);
    }
  }

  Future<void> _loadData() async {
    if (_uid.isEmpty) return;
    try {
      final scoreSnap = await FirebaseFirestore.instance
          .collection('game_scores')
          .doc(_uid)
          .get();

      if (mounted) {
        setState(() {
          _scores = scoreSnap.data();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _weekPoints(String game) => (_scores?['${game}_weeklyPoints'] as int?) ?? 0;

  int get _totalWeekPoints => _games.fold(0, (s, g) => s + _weekPoints(g.id));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                color: Colors.white,
                backgroundColor: const Color(0xFF1A1F2E),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    const SizedBox(height: 12),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: Center(
                            child: CircularProgressIndicator(color: Colors.white54)),
                      )
                    else ...[
                      _buildSectionLabel('Choose a Game'),
                      const SizedBox(height: 12),
                      ..._games.map((g) => _buildGameCard(g)),
                      // Ad banner
                      if (!_adDismissed) ...[
                        const SizedBox(height: 8),
                        _buildAdBanner(),
                      ],
                    ],
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
        gradient: LinearGradient(
          colors: [Color(0xFF1A1F2E), Color(0xFF0D1117)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: Color(0xFF2A3040))),
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
                Text('Game Hub',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                Text('Play for fun!',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          const Text('🎮', style: TextStyle(fontSize: 26)),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(label,
        style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5));
  }

  Widget _buildGameCard(_GameMeta g) {
    final pts = _weekPoints(g.id);
    final dark = Color.fromARGB(
        255,
        (g.color.red * 0.6).round().clamp(0, 255),
        (g.color.green * 0.6).round().clamp(0, 255),
        (g.color.blue * 0.6).round().clamp(0, 255));

    return GestureDetector(
      onTap: () {
        Widget screen;
        switch (g.id) {
          case 'puzzle':
            screen = const PuzzleScreen();
            break;
          case 'chess':
            screen = const ChessScreen();
            break;
          default:
            screen = const BlockArrangeScreen();
        }
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
            .then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [g.color, dark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: g.color.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 5))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(g.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('$pts pts this week',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.75), fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdBanner() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data!.docs.cast<DocumentSnapshot>().take(1).toList();
        if (docs.isEmpty) return const SizedBox.shrink();

        final ad = docs.first;
        final data = ad.data() as Map<String, dynamic>;
        return AdDashboardCard(
          ad: {'id': ad.id, ...data},
          onTap: () {
            FirebaseFirestore.instance.collection('ads').doc(ad.id)
                .update({'taps': FieldValue.increment(1)})
                .catchError((_) {});
          },
          onDismiss: () => setState(() => _adDismissed = true),
        );
      },
    );
  }
}

class _GameMeta {
  final String id, label;
  final IconData icon;
  final Color color;
  const _GameMeta(this.id, this.label, this.icon, this.color);
}