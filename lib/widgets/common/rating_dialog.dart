import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';

class RatingDialog extends StatefulWidget {
  final String shuttleId; // The shuttleIdFeedback of the request
  final String requestId; // The uid of the request so we can mark it as rated

  const RatingDialog({super.key, required this.shuttleId, required this.requestId});

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _rating = 5;
  bool _submitting = false;

  Future<void> _submitRating() async {
    setState(() => _submitting = true);
    try {
      final q = await FirebaseFirestore.instance.collection('drivers').where('shuttleId', isEqualTo: widget.shuttleId).limit(1).get();
      if (q.docs.isEmpty) {
        if (mounted) {
          Navigator.pop(context, false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver not found.'), backgroundColor: AppColors.error));
        }
        return;
      }
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
        
        // Also mark request as rated
        tx.update(FirebaseFirestore.instance.collection('ride_requests').doc(widget.requestId), {
          'isRated': true,
          'rating': _rating,
        });
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit rating: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Rate Your Driver',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            const Text(
              'How was your AFIT KEKE ride?',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: Colors.amber,
                    size: 40,
                  ),
                  onPressed: () => setState(() => _rating = index + 1),
                );
              }),
            ),
            const SizedBox(height: 24),
            _submitting
                ? const CircularProgressIndicator(color: AppColors.primary)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Skip', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _submitRating,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Submit', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
