import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/models/driver_model.dart';

class DriverOfTheWeekBanner extends StatelessWidget {
  const DriverOfTheWeekBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        // Defensive client-side sort by averageRating & totalRatings
        final drivers = snapshot.data!.docs.map((doc) => DriverModel.fromDocument(doc)).toList();
        drivers.sort((a, b) {
          final ratingCmp = b.averageRating.compareTo(a.averageRating);
          if (ratingCmp != 0) return ratingCmp;
          return b.totalRatings.compareTo(a.totalRatings);
        });

        final topDriver = drivers.first;
        if (topDriver.averageRating == 0 && topDriver.totalRatings == 0) {
          return const SizedBox.shrink();
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4C1D95), Color(0xFF6D28D9), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6D28D9).withOpacity(0.4),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6),
                  ],
                ),
                child: Center(
                  child: Text(
                    Helpers.getInitials(topDriver.name),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF4C1D95),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'DRIVER OF THE WEEK',
                          style: TextStyle(
                            color: Colors.amber[300],
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      topDriver.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Rating: ${topDriver.averageRating.toStringAsFixed(1)} ★ (${topDriver.totalRatings} ratings)',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.star_rounded, color: Colors.amber, size: 32),
            ],
          ),
        );
      },
    );
  }
}
