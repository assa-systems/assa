import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/services/offline_request_store.dart';

class RatingDialog extends StatefulWidget {
  final String shuttleId; // The shuttleId / public ID
  final String requestId; // Request document ID or Pickup ID
  final bool isOffline;

  const RatingDialog({
    super.key,
    required this.shuttleId,
    required this.requestId,
    this.isOffline = false,
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _rating = 5;
  bool _submitting = false;
  final TextEditingController _commentController = TextEditingController();
  final Set<String> _selectedChips = {};

  final List<String> _feedbackOptions = [
    'Punctual Driver',
    'Safe Driving',
    'Clean Shuttle',
    'Polite Service',
    'Smooth Ride',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRatingAndCompleteRide() async {
    setState(() => _submitting = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final publicShuttle = Esp32Service.getPublicShuttleId(widget.shuttleId);

    try {
      if (widget.isOffline) {
        // ── OFFLINE COMPLETION & RATING ────────────────────────────────────
        await OfflineRequestStore.instance.updateStatus(
          widget.requestId,
          OfflineStatus.completed,
          shuttleId: publicShuttle,
        );

        // Notify ESP32 AP if connected over WiFi
        try {
          await Esp32Service.instance.sendOfflineStatusUpdateToEsp32(
            bookingId: widget.requestId,
            status: 6, // Completed
            shuttleId: publicShuttle,
          );
        } catch (_) {}

        if (mounted) Navigator.pop(context, true);
        return;
      }

      // ── ONLINE COMPLETION & RATING (FIRESTORE) ─────────────────────────
      // 1. Mark request doc as completed and rated (Primary User Operation)
      await FirebaseFirestore.instance.collection('ride_requests').doc(widget.requestId).update({
        'status': 4,
        'statusName': 'Completed',
        'isCompletedByUser': true,
        'completedAt': FieldValue.serverTimestamp(),
        'isRated': true,
        'rating': _rating,
        'ratingComment': _commentController.text.trim(),
        'ratingTags': _selectedChips.toList(),
      });

      // 2. Add to ride_ratings collection for admin analytics (Secondary Operation)
      try {
        await FirebaseFirestore.instance.collection('ride_ratings').add({
          'requestId': widget.requestId,
          'shuttleId': publicShuttle.isNotEmpty ? publicShuttle : widget.shuttleId,
          'userId': uid,
          'rating': _rating,
          'tags': _selectedChips.toList(),
          'comment': _commentController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Analytics rating collection write error (non-fatal): $e');
      }

      // 3. Update driver's total and average rating if driver document exists (Secondary Operation)
      if (widget.shuttleId.isNotEmpty) {
        try {
          final q = await FirebaseFirestore.instance
              .collection('drivers')
              .where('shuttleId', isEqualTo: widget.shuttleId)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            final docRef = q.docs.first.reference;
            await FirebaseFirestore.instance.runTransaction((tx) async {
              final snap = await tx.get(docRef);
              if (!snap.exists) return;

              final data = snap.data()!;
              final currentTotal = data['totalRatings'] as int? ?? 0;
              final currentAvg = (data['averageRating'] as num?)?.toDouble() ?? 0.0;

              final newTotal = currentTotal + 1;
              final newAvg = ((currentAvg * currentTotal) + _rating) / newTotal;

              tx.update(docRef, {
                'totalRatings': newTotal,
                'averageRating': newAvg,
              });
            });
          }
        } catch (e) {
          debugPrint('Driver rating aggregation error (non-fatal): $e');
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete ride: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shuttleDisplay = Esp32Service.getPublicShuttleId(widget.shuttleId);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
            ),
            const SizedBox(height: 12),
            Text(
              'Acknowledge & Complete Ride',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              shuttleDisplay.isNotEmpty
                  ? 'Shuttle Unit: $shuttleDisplay • How was your ride?'
                  : 'Please rate your AFIT KEKE ride experience',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF8B949E) : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Star rating row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final isStarSelected = index < _rating;
                return GestureDetector(
                  onTap: () => setState(() => _rating = index + 1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      isStarSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: isStarSelected ? Colors.amber : (isDark ? Colors.grey[600] : Colors.grey[400]),
                      size: 38,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            // Quick feedback chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _feedbackOptions.map((chipText) {
                final isSelected = _selectedChips.contains(chipText);
                return FilterChip(
                  label: Text(chipText, style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppColors.textPrimary),
                  )),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: isDark ? const Color(0xFF21262D) : Colors.grey[100],
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedChips.add(chipText);
                      } else {
                        _selectedChips.remove(chipText);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Optional comment textfield
            TextField(
              controller: _commentController,
              maxLines: 2,
              style: TextStyle(color: isDark ? Colors.white : AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Add an optional note or review...',
                hintStyle: TextStyle(color: isDark ? const Color(0xFF8B949E) : AppColors.textHint, fontSize: 12),
                fillColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF5F7FF),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _submitting
                ? const CircularProgressIndicator(color: AppColors.primary)
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                          ),
                          child: Text(
                            'Later',
                            style: TextStyle(color: isDark ? Colors.white70 : AppColors.textSecondary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submitRatingAndCompleteRide,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Complete Ride',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
