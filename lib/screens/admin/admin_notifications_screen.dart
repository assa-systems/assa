import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});
  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .limit(50)
        .snapshots();
  }

  Future<void> _markAllRead() async {
    final unread = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
    if (mounted) Helpers.showSuccessSnackBar(context, 'All marked as read.');
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All?'),
        content: const Text('Delete all notifications? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete All', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    // TRUE DELETE — permanently removes every matching document (not a
    // soft/is_active flag).
    final snap = await FirebaseFirestore.instance
        .collection('notifications').where('userId', isEqualTo: uid).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) batch.delete(doc.reference);
    await batch.commit();
    if (mounted) Helpers.showSuccessSnackBar(context, 'All notifications cleared.');
  }

  void _openDetail(Map<String, dynamic> data, String docId) {
    if (!(data['read'] ?? false)) {
      FirebaseFirestore.instance
          .collection('notifications').doc(docId).update({'read': true});
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AdminNotifDetailSheet(data: data, docId: docId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.adminColor));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.notifications_none_rounded,
                          size: 64, color: AppColors.textHint),
                      const SizedBox(height: 16),
                      const Text('No notifications',
                          style: TextStyle(fontSize: 16,
                              fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      const Text("You're all caught up!",
                          style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                    ]),
                  );
                }
                final sortedDocs = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final aTs = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                    final bTs = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                    if (aTs == null && bTs == null) return 0;
                    if (aTs == null) return 1;
                    if (bTs == null) return -1;
                    return bTs.compareTo(aTs);
                  });
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedDocs.length,
                  itemBuilder: (ctx, i) {
                    final doc = sortedDocs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return Dismissible(
                      key: Key(doc.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.delete_rounded,
                            color: Colors.white, size: 26),
                      ),
                      onDismissed: (_) => FirebaseFirestore.instance
                          .collection('notifications').doc(doc.id).delete(),
                      child: _AdminNotifCard(
                        data: data,
                        onTap: () => _openDetail(data, doc.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.adminColor, AppColors.adminColor.withOpacity(0.85)]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
      child: Row(children: [
        IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white)),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Notifications', style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
          Text('Tap to read · Swipe left to delete',
              style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12)),
        ])),
        TextButton(onPressed: _markAllRead,
            child: const Text('Mark all read',
                style: TextStyle(color: Colors.white, fontSize: 12))),
        IconButton(onPressed: _deleteAll,
            icon: const Icon(Icons.delete_sweep_rounded,
                color: Colors.white, size: 22)),
      ]),
    );
  }
}

class _AdminNotifCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _AdminNotifCard({required this.data, required this.onTap});

  static IconData _getIcon(String? type) {
    switch (type) {
      case 'lost_found': return Icons.volunteer_activism_rounded;
      case 'driver_approved': return Icons.check_circle_rounded;
      case 'driver_rejected': return Icons.cancel_rounded;
      default: return Icons.chevron_right_rounded;
    }
  }

  static Color _getColor(String? type) {
    switch (type) {
      case 'lost_found': return const Color(0xFF00897B);
      case 'driver_approved': return AppColors.success;
      case 'driver_rejected': return AppColors.error;
      default: return AppColors.adminColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRead = data['read'] ?? false;
    final type = data['type'] as String?;
    final color = _getColor(type);
    DateTime createdAt = DateTime.now();
    if (data['createdAt'] != null) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? AppColors.surface : color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isRead ? AppColors.cardBorder : color.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4,
              offset: const Offset(0, 1))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 42, height: 42,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(_getIcon(type), color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(data['title'] ?? '',
                  style: TextStyle(fontSize: 13,
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                      color: AppColors.textPrimary))),
              if (!isRead)
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 4),
            Text(data['body'] ?? '',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(children: [
              Text(Helpers.formatDateTime(createdAt),
                  style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
              const Spacer(),
              Text('Tap to read',
                  style: TextStyle(fontSize: 10, color: color,
                      fontWeight: FontWeight.w500)),
              Icon(Icons.chevron_right_rounded,
                  size: 14, color: color),
            ]),
          ])),
        ]),
      ),
    );
  }
}

class _AdminNotifDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _AdminNotifDetailSheet({required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    DateTime createdAt = DateTime.now();
    if (data['createdAt'] != null) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    }
    final type = data['type'] as String?;
    final color = _AdminNotifCard._getColor(type);
    final icon = _AdminNotifCard._getIcon(type);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.divider,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Container(width: 64, height: 64,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 32)),
        const SizedBox(height: 16),
        Text(data['title'] ?? '',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(Helpers.formatDateTime(createdAt),
            style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder)),
          child: Text(data['body'] ?? '',
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.6)),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('notifications').doc(docId).delete();
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete Notification'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppColors.textSecondary))),
        const SizedBox(height: 8),
      ]),
    );
  }
}
