import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';

class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  Future<void> _updateStatus(String docId, String status) async {
    await FirebaseFirestore.instance
        .collection('reports').doc(docId).update({'status': status});
  }

  // Copy report details to clipboard for forwarding
  void _copyReport(BuildContext context, Map<String, dynamic> data) {
    final text =
        'ASSA Report\n'
        '──────────────\n'
        'Reporter: ${data['reporterName'] ?? '-'} (${data['reporterRole'] ?? '-'})\n'
        'Shuttle ID: ${data['shuttleId'] ?? '-'}\n'
        'Category: ${data['category'] ?? '-'}\n'
        'Date: ${data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate().toString() : '-'}\n\n'
        'Description:\n${data['description'] ?? '-'}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Report copied to clipboard. Paste into email or message to forward.'),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F3FF),
        body: SafeArea(
          child: Column(children: [
            _buildHeader(context),
            const TabBar(
              labelColor: AppColors.adminColor,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.adminColor,
              isScrollable: true,
              tabs: [
                Tab(text: 'Open'),
                Tab(text: 'In Review'),
                Tab(text: 'Resolved'),
                Tab(text: '💬 Complaint Panel'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                _ReportList(status: 'open', onCopy: _copyReport, onStatus: _updateStatus),
                _ReportList(status: 'reviewing', onCopy: _copyReport, onStatus: _updateStatus),
                _ReportList(status: 'resolved', onCopy: _copyReport, onStatus: _updateStatus),
                const _ComplaintPanelList(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.adminColor, AppColors.adminColor.withOpacity(0.8)]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(children: [
        IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20)),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reports Inbox', style: TextStyle(fontSize: 18,
              fontWeight: FontWeight.w700, color: Colors.white)),
          Text('User-submitted shuttle reports',
              style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12)),
        ])),
        const Icon(Icons.report_rounded, color: Colors.white, size: 24),
      ]),
    );
  }
}

class _ReportList extends StatelessWidget {
  final String status;
  final void Function(BuildContext, Map<String, dynamic>) onCopy;
  final Future<void> Function(String, String) onStatus;
  const _ReportList({required this.status, required this.onCopy, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.adminColor));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle_outline_rounded,
                  size: 64, color: const Color(0xFFCCCCDD)),
              const SizedBox(height: 16),
              Text('No $status reports',
                  style: const TextStyle(fontSize: 16, color: AppColors.textSecondary)),
            ]),
          );
        }
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aT = (a.data() as Map)['createdAt'];
            final bT = (b.data() as Map)['createdAt'];
            if (aT == null || bT == null) return 0;
            return bT.compareTo(aT);
          });
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _ReportCard(
              docId: doc.id,
              data: data,
              onCopy: () => onCopy(context, data),
              onStatus: onStatus,
            );
          },
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onCopy;
  final Future<void> Function(String, String) onStatus;
  const _ReportCard({required this.docId, required this.data,
    required this.onCopy, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] ?? 'open';
    final shuttleId = data['shuttleId'] ?? '-';
    final description = data['description'] ?? '';
    final category = data['category'] ?? '';
    final reporterName = data['reporterName'] ?? 'Anonymous';
    final reporterRole = data['reporterRole'] ?? 'user';
    DateTime createdAt = DateTime.now();
    if (data['createdAt'] != null) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    }

    Color statusColor;
    switch (status) {
      case 'reviewing': statusColor = AppColors.warning; break;
      case 'resolved': statusColor = AppColors.success; break;
      default: statusColor = AppColors.error;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [BoxShadow(color: AppColors.shadow,
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.report_rounded,
                    color: AppColors.error, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(reporterName, style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14)),
              Row(children: [
                Icon(reporterRole == 'driver'
                    ? Icons.drive_eta_rounded : Icons.person_rounded,
                    size: 11, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(reporterRole, style: const TextStyle(
                    fontSize: 11, color: AppColors.textHint)),
              ]),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(status, style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w700, color: statusColor)),
              ),
              if (category.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(category, style: const TextStyle(
                    fontSize: 10, color: AppColors.textHint)),
              ],
            ]),
          ]),
        ),

        // Shuttle + time
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(children: [
            const Icon(Icons.directions_bus_rounded,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('Shuttle: $shuttleId',
                style: const TextStyle(fontSize: 12,
                    color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(Helpers.formatDateTime(createdAt),
                style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          ]),
        ),

        // Description
        if (description.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder)),
            child: Text(description, style: const TextStyle(
                fontSize: 13, color: AppColors.textPrimary, height: 1.4)),
          ),

        // Action buttons
        const Divider(height: 1, color: AppColors.divider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy & Forward', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
            const Spacer(),
            if (status == 'open')
              TextButton(
                onPressed: () => onStatus(docId, 'reviewing'),
                child: const Text('Mark Reviewing',
                    style: TextStyle(fontSize: 11, color: AppColors.warning)),
              ),
            if (status == 'reviewing')
              TextButton(
                onPressed: () => onStatus(docId, 'resolved'),
                child: const Text('Mark Resolved',
                    style: TextStyle(fontSize: 11, color: AppColors.success)),
              ),
          ]),
        ),
      ]),
    );
  }
}


// ── Complaint Panel tab - shows all support_chats ─────────────────────
class _ComplaintPanelList extends StatelessWidget {
  const _ComplaintPanelList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('support_chats').snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: AppColors.adminColor));
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.support_agent_rounded, size: 64, color: AppColors.textHint),
            SizedBox(height: 16),
            Text('No complaint panel chats yet',
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          ]),
        );
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final chatId = docs[i].id;
            final userId = chatId.replaceFirst('support_', '');
            return _ComplaintTile(chatId: chatId, userId: userId);
          },
        );
      },
    );
  }
}

class _ComplaintTile extends StatelessWidget {
  final String chatId, userId;
  const _ComplaintTile({required this.chatId, required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (_, uSnap) {
        final ud   = uSnap.data?.data() as Map<String, dynamic>?;
        final name = ud?['name']  ?? 'User';
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('support_chats').doc(chatId)
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .limit(1).snapshots(),
          builder: (_, mSnap) {
            final last = mSnap.data?.docs.isNotEmpty == true
                ? (mSnap.data!.docs.first.data() as Map)['text'] ?? '' : '';
            final isBot = mSnap.data?.docs.isNotEmpty == true
                ? (mSnap.data!.docs.first.data() as Map)['isBot'] == true : false;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8E8F0)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
                    blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Row(children: [
                Container(width: 44, height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      gradient: const LinearGradient(
                          colors: [Color(0xFF004D40), Color(0xFF00695C)])),
                  child: Center(child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w800, fontSize: 16),
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                  Text(isBot ? '🛡️ $last' : last,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.adminColor, size: 20),
              ]),
            );
          },
        );
      },
    );
  }
}