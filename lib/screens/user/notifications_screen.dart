import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/screens/user/report_screen.dart';
import 'package:assa/services/firestore_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Keep stream subscription alive so it doesn't restart and blink
  late final Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    // Create stream once and reuse it — prevents blinking/reset on rebuild
    // No orderBy — avoids composite index requirement. Sort client-side.
    _stream = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .limit(50)
        .snapshots();
  }

  Future<void> _markAllRead() async {
    try {
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
      if (mounted) Helpers.showSuccessSnackBar(context, 'All notifications marked as read.');
    } catch (_) {}
  }

  Future<void> _deleteNotification(String docId) async {
    try {
      await FirestoreService.instance.deleteNotification(docId);
    } catch (_) {}
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
    try {
      await FirestoreService.instance.deleteAllUserNotifications(uid);
      if (mounted) Helpers.showSuccessSnackBar(context, 'All notifications cleared.');
    } catch (_) {
      if (mounted) Helpers.showErrorSnackBar(context, 'Failed to clear notifications.');
    }
  }

  void _openNotification(Map<String, dynamic> data, String docId) {
    // Mark as read
    if (!(data['read'] ?? false)) {
      FirebaseFirestore.instance.collection('notifications').doc(docId).update({'read': true});
    }
    // Admin chat notifications open the User Inbox for direct reply
    if (data['type'] == 'admin_chat') {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => const ReportScreen()));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _NotificationDetailSheet(data: data, docId: docId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2FF),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _stream,
              builder: (context, snapshot) {
                // Show data if available, even if still loading new data
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.userColor));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }
                final docs = [...snapshot.data!.docs];
                docs.sort((a, b) {
                  final at = (a.data() as Map)['createdAt'];
                  final bt = (b.data() as Map)['createdAt'];
                  if (at == null && bt == null) return 0;
                  if (at == null) return 1;
                  if (bt == null) return -1;
                  return (bt as Timestamp).compareTo(at as Timestamp);
                });
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final doc = docs[i];
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
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete_rounded,
                            color: Colors.white, size: 26),
                      ),
                      onDismissed: (_) => _deleteNotification(doc.id),
                      child: _NotificationCard(
                        data: data,
                        docId: doc.id,
                        onTap: () => _openNotification(data, doc.id),
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
            colors: [Color(0xFF1A237E), Color(0xFF283593)]),
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
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 22),
            tooltip: 'Clear all'),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.notifications_none_rounded, size: 64, color: AppColors.textHint),
        const SizedBox(height: 16),
        const Text('No notifications', style: TextStyle(fontSize: 16,
            fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        const Text("You're all caught up!",
            style: TextStyle(fontSize: 13, color: AppColors.textHint)),
      ]),
    );
  }
}

// ── Notification Card ──────────────────────────────────────────────────
class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final VoidCallback onTap;
  const _NotificationCard({required this.data, required this.docId, required this.onTap});

  static IconData _getIcon(String? type) {
    switch (type) {
      case 'arrival': return Icons.directions_bus_rounded;
      case 'approval': return Icons.check_circle_rounded;
      case 'rejection': return Icons.cancel_rounded;
      case 'booking': return Icons.receipt_long_rounded;
      case 'general': return Icons.campaign_rounded;
      case 'admin_chat': return Icons.admin_panel_settings_rounded;
      case 'lost_found': return Icons.search_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  static Color _getColor(String? type) {
    switch (type) {
      case 'arrival': return AppColors.primary;
      case 'approval': return AppColors.success;
      case 'rejection': return AppColors.error;
      case 'booking': return AppColors.accent;
      case 'general': return AppColors.adminColor;
      case 'admin_chat': return const Color(0xFF6A1B9A);
      case 'lost_found': return const Color(0xFF00897B);
      default: return AppColors.textSecondary;
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
          boxShadow: [BoxShadow(
              color: AppColors.shadow, blurRadius: 4, offset: const Offset(0, 1))],
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
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
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
              Text(type == 'admin_chat' ? 'Tap to reply' : 'Tap to read',
                  style: TextStyle(fontSize: 10,
                      color: type == 'admin_chat'
                          ? const Color(0xFF6A1B9A) : AppColors.primary,
                      fontWeight: FontWeight.w600)),
              Icon(Icons.chevron_right_rounded, size: 14,
                  color: type == 'admin_chat'
                      ? const Color(0xFF6A1B9A) : AppColors.primary),
            ]),
          ])),
        ]),
      ),
    );
  }
}

// ── Full Notification Detail Sheet ─────────────────────────────────────
class _NotificationDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _NotificationDetailSheet({required this.data, required this.docId});

  static IconData _getIcon(String? type) {
    switch (type) {
      case 'arrival': return Icons.directions_bus_rounded;
      case 'approval': return Icons.check_circle_rounded;
      case 'rejection': return Icons.cancel_rounded;
      case 'booking': return Icons.receipt_long_rounded;
      case 'general': return Icons.campaign_rounded;
      case 'admin_chat': return Icons.admin_panel_settings_rounded;
      case 'lost_found': return Icons.search_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  static Color _getColor(String? type) {
    switch (type) {
      case 'arrival': return AppColors.primary;
      case 'approval': return AppColors.success;
      case 'rejection': return AppColors.error;
      case 'booking': return AppColors.accent;
      case 'general': return AppColors.adminColor;
      case 'admin_chat': return const Color(0xFF6A1B9A);
      case 'lost_found': return const Color(0xFF00897B);
      default: return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String?;
    final color = _getColor(type);
    DateTime createdAt = DateTime.now();
    if (data['createdAt'] != null) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    }
    final linkUrl = data['linkUrl'] ?? data['link'] ?? '';

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
            child: Icon(_getIcon(type), color: color, size: 32)),
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
        if (linkUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: linkUrl));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Link copied: $linkUrl'),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                ));
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white),
              label: const Text('Copy Link', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              try {
                await FirestoreService.instance.deleteNotification(docId);
              } catch (_) {}
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