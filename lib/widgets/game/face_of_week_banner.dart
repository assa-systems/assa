import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';

// ════════════════════════════════════════════════════════════════════
// FACE OF THE WEEK BANNER
//
// Reusable widget that fetches and displays the current week's winner.
// Used on:
//   • Game Hub (hero banner at top)
//   • User Dashboard (recognition card)
//
// Shows winner's photo, name, department, and a fun fact.
// If no winner yet, shows "Be the first!" placeholder.
// ════════════════════════════════════════════════════════════════════

class FaceOfWeekBanner extends StatelessWidget {
  final bool compact; // false = full card, true = small badge
  const FaceOfWeekBanner({super.key, this.compact = false});

  static String get _weekKey {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final week = ((monday.difference(DateTime(monday.year, 1, 1)).inDays +
        DateTime(monday.year, 1, 1).weekday - 1) ~/ 7) + 1;
    return '${monday.year}-W$week';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('winners')
          .doc(_weekKey)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 100,
            child: Center(
                child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildEmptyState();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final winner = WinnerData.fromMap(data);

        if (compact) {
          return _buildCompactCard(winner);
        } else {
          return _buildFullCard(winner);
        }
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1F2E), Color(0xFF0D1117)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A3040)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
            ),
            child: const Center(
                child: Icon(Icons.emoji_events_rounded,
                    color: Colors.white38, size: 32)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FACE OF THE WEEK',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
                const SizedBox(height: 4),
                const Text('No winner yet!',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Play games to become the Face of the Week!',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullCard(WinnerData winner) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Winner photo
            ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: CachedNetworkImage(
                imageUrl: winner.photoUrl,
                width: 70,
                height: 70,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 70,
                  height: 70,
                  color: Colors.white24,
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white54, size: 36),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 70,
                  height: 70,
                  color: Colors.white24,
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white54, size: 36),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Winner info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🏆 FACE OF THE WEEK',
                      style: TextStyle(
                          color: Color(0xFF3E2000),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(winner.userName,
                      style: const TextStyle(
                          color: Color(0xFF3E2000),
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  Text(winner.department,
                      style: const TextStyle(
                          color: Color(0xFF5D3200), fontSize: 12)),
                  const SizedBox(height: 4),
                  if (winner.waitingHabit.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.timer_rounded,
                            color: Color(0xFF5D3200), size: 12),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(winner.waitingHabit,
                              style: const TextStyle(
                                  color: Color(0xFF5D3200),
                                  fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Icon(Icons.emoji_events_rounded,
                color: Color(0xFF3E2000), size: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCard(WinnerData winner) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CachedNetworkImage(
              imageUrl: winner.photoUrl,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: 32,
                height: 32,
                color: Colors.white24,
                child: const Icon(Icons.person_rounded,
                    color: Colors.white54, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏆 FACE OF THE WEEK',
                  style: TextStyle(
                      color: Color(0xFF3E2000),
                      fontSize: 8,
                      fontWeight: FontWeight.w800)),
              Text(winner.userName,
                  style: const TextStyle(
                      color: Color(0xFF3E2000),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class WinnerData {
  final String userId;
  final String userName;
  final String userEmail;
  final String photoUrl;
  final String department;
  final String matricNumber;
  final String hobbies;
  final String waitingHabit;
  final int totalScore;
  final Map<String, int> gameScores;

  WinnerData({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.photoUrl,
    required this.department,
    required this.matricNumber,
    required this.hobbies,
    required this.waitingHabit,
    required this.totalScore,
    required this.gameScores,
  });

  factory WinnerData.fromMap(Map<String, dynamic> map) {
    return WinnerData(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userEmail: map['userEmail'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
      department: map['department'] ?? '',
      matricNumber: map['matricNumber'] ?? '',
      hobbies: map['hobbies'] ?? '',
      waitingHabit: map['waitingHabit'] ?? '',
      totalScore: map['totalScore'] ?? 0,
      gameScores: Map<String, int>.from(map['gameScores'] ?? {}),
    );
  }
}