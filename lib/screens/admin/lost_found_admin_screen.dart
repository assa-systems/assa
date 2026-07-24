// lost_found_admin_screen.dart (full file with fixes)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';

class AdminLostFoundScreen extends StatefulWidget {
  const AdminLostFoundScreen({super.key});
  @override
  State<AdminLostFoundScreen> createState() => _AdminLostFoundScreenState();
}

class _AdminLostFoundScreenState extends State<AdminLostFoundScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          Container(
            color: const Color(0xFF00695C),
            child: TabBar(
              controller:           _tab,
              indicatorColor:       Colors.white,
              labelColor:           Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: 'Pending Claims'),
                Tab(text: 'All Active'),
                Tab(text: 'History'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildPendingClaims(),
                _buildAllActive(),
                _buildHistory(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF00897B), Color(0xFF00695C)]),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      child: Row(children: [
        IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white)),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Lost & Found — Admin',
                style: TextStyle(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w700)),
            Text('Review claims · Set fines · Issue ride credits',
                style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 11)),
          ]),
        ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('lost_found')
              .where('status', isEqualTo: 'Pending Claim')
              .snapshots(),
          builder: (_, snap) {
            final count = snap.data?.docs.length ?? 0;
            if (count == 0) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.error, borderRadius: BorderRadius.circular(12)),
              child: Text('$count pending',
                  style: const TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w700)),
            );
          },
        ),
      ]),
    );
  }

  // ── Tab 1: Pending Claims ────────────────────────────────────────────
  Widget _buildPendingClaims() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lost_found')
          .where('status', isEqualTo: 'Pending Claim')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(
              color: Color(0xFF00897B)));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle_rounded, size: 60, color: AppColors.success),
            SizedBox(height: 12),
            Text('No pending claims',
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
            SizedBox(height: 6),
            Text('New claims appear here when owners tap "This is Mine".',
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
                textAlign: TextAlign.center),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _ClaimCard(
              data:  data,
              docId: docId,
            );
          },
        );
      },
    );
  }

  // ── Tab 2: All Active items ──────────────────────────────────────────
  Widget _buildAllActive() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lost_found')
          .where('is_active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = (snapshot.data?.docs ?? [])..sort((a, b) {
          final at = (a.data() as Map)['timestamp'];
          final bt = (b.data() as Map)['timestamp'];
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return (bt as Timestamp).compareTo(at as Timestamp);
        });
        if (docs.isEmpty) {
          return const Center(child: Text('No active items',
              style: TextStyle(color: AppColors.textSecondary)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _AdminItemCard(data: data, docId: docId);
          },
        );
      },
    );
  }

  // ── Tab 3: History (recovered + removed) ────────────────────────────
  Widget _buildHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lost_found')
          .snapshots(),
      builder: (context, snapshot) {
        final all  = snapshot.data?.docs ?? [];
        final docs = all.where((d) {
          final status = (d.data() as Map)['status'];
          return status == 'Recovered' || status == 'Removed';
        }).toList()..sort((a, b) {
          final at = (a.data() as Map)['updatedAt'] ??
              (a.data() as Map)['timestamp'];
          final bt = (b.data() as Map)['updatedAt'] ??
              (b.data() as Map)['timestamp'];
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return (bt as Timestamp).compareTo(at as Timestamp);
        });
        if (docs.isEmpty) {
          return const Center(child: Text('No history yet',
              style: TextStyle(color: AppColors.textSecondary)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _AdminItemCard(data: data, docId: docId, isHistory: true);
          },
        );
      },
    );
  }
}

// ── Claim Card ──────────────────────────────────────────────────────────
class _ClaimCard extends StatefulWidget {
  final Map<String, dynamic>  data;
  final String                docId;
  const _ClaimCard({required this.data, required this.docId});
  @override
  State<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends State<_ClaimCard> {
  bool _processing = false;

  Future<void> _approveClaim() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve Claim?'),
        content: const Text(
          'This confirms the item has been returned to its owner at no charge.\n\n'
              'You can privately message the finder afterwards to congratulate '
              'and reward them if you choose.',
          style: TextStyle(fontSize: 13, height: 1.6,
              color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B)),
            child: const Text('Approve — Item Returned',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _processing = true);
    try {
      await FirebaseFirestore.instance
          .collection('lost_found').doc(widget.docId)
          .update({
        'status':    'Recovered',
        'is_active': false,
        'finePaid':  false,
        'fineAmount': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Notify finder + claimant so it surfaces in Notifications + Dashboard
      final finderId = widget.data['finderUserId'] as String? ?? widget.data['userId'] as String?;
      final ownerId  = widget.data['ownerUserId'] as String?;
      final itemDesc = widget.data['description'] as String? ?? 'item';
      final notifyBatch = FirebaseFirestore.instance.batch();
      if (finderId != null && finderId.isNotEmpty) {
        final ref = FirebaseFirestore.instance.collection('notifications').doc();
        notifyBatch.set(ref, {
          'userId':      finderId,
          'title':       '✅ Item Returned',
          'body':        'The $itemDesc you found has been returned to its owner. Thank you!',
          'type':        'lost_found',
          'lostFoundId': widget.docId,
          'read':        false,
          'createdAt':   FieldValue.serverTimestamp(),
        });
      }
      if (ownerId != null && ownerId.isNotEmpty) {
        final ref = FirebaseFirestore.instance.collection('notifications').doc();
        notifyBatch.set(ref, {
          'userId':      ownerId,
          'title':       '✅ Claim Approved',
          'body':        'Your claim for "$itemDesc" was approved. It has been marked returned.',
          'type':        'lost_found',
          'lostFoundId': widget.docId,
          'read':        false,
          'createdAt':   FieldValue.serverTimestamp(),
        });
      }
      await notifyBatch.commit();

      if (mounted) {
        setState(() => _processing = false);
        _snack('Item marked as recovered. Contact the finder privately to reward them.');
      }
    } catch (_) {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : const Color(0xFF00897B),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final d        = widget.data;
    final category = d['category'] ?? 'Item';
    final ts       = d['timestamp'];
    final date     = ts != null
        ? Helpers.formatDateTime((ts as Timestamp).toDate()) : '';
    final recovered = d['status'] == 'Recovered';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: AppColors.warning.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: AppColors.shadow,
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warningLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Icon(Icons.pending_actions_rounded,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            const Text('PENDING CLAIM',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                    color: AppColors.warning, letterSpacing: 1)),
            const Spacer(),
            Text(date, style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoRow('Category', category),
            const SizedBox(height: 6),
            _InfoRow('Description', d['description'] ?? ''),
            const SizedBox(height: 6),
            _InfoRow('Location', d['locationName'] ?? ''),
            const SizedBox(height: 6),
            _InfoRow('Finder (will receive credit)', d['userName'] ?? ''),
            if ((d['contactInfo'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              _InfoRow('Finder Contact', d['contactInfo'] ?? ''),
            ],
            const Divider(height: 24, color: AppColors.divider),
            if (!recovered) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: const Text(
                  'The owner is claiming this item. Verify their identity and '
                      'return the item at no charge. You can then privately message '
                      'the finder to congratulate and reward them.',
                  style: TextStyle(fontSize: 12,
                      color: AppColors.textSecondary, height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _processing ? null : _approveClaim,
                  icon: _processing
                      ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded,
                      size: 18, color: Colors.white),
                  label: const Text('Approve — Item Returned',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Item recovered and returned to owner. '
                        'Remember to privately message the finder to reward them.',
                    style: TextStyle(fontSize: 12,
                        color: AppColors.success, fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _forceRemove(context),
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 15, color: AppColors.error),
                label: const Text('Remove listing',
                    style: TextStyle(color: AppColors.error, fontSize: 12)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _forceRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Listing?'),
        content: const Text('This hides the item from all listings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('lost_found').doc(widget.docId)
          .update({'is_active': false, 'status': 'Removed',
        'updatedAt': FieldValue.serverTimestamp()});
    }
  }
}

// ── Admin Item Card (All Active / History) ─────────────────────────────
class _AdminItemCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool   isHistory;
  const _AdminItemCard({required this.data, required this.docId,
    this.isHistory = false});

  @override
  Widget build(BuildContext context) {
    final status    = data['status']   ?? '';
    final isLost    = data['itemType'] == 'Lost';
    final typeColor = isLost ? AppColors.error : const Color(0xFF00897B);
    final ts        = data['timestamp'];
    final date      = ts != null
        ? Helpers.formatDateTime((ts as Timestamp).toDate()) : '';
    final imageUrl  = data['imageUrl'] ?? '';   // raw field, no conversion

    return GestureDetector(
      onTap: () => _showDetailSheet(context, typeColor, date, imageUrl),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: AppColors.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:        typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(data['itemType'] ?? '',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: typeColor)),
            ),
            const SizedBox(width: 6),
            Text(data['category'] ?? '',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const Spacer(),
            Text(status,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: status == 'Recovered'
                        ? AppColors.success : AppColors.textSecondary)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.textHint),
          ]),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl.startsWith('data:image')
                  ? Image.memory(base64Decode(imageUrl.split(',').last),
                  height: 120, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const SizedBox.shrink())
                  : Image.network(imageUrl,
                  height: 120, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const SizedBox.shrink()),
            ),
          ],
          const SizedBox(height: 8),
          Text(data['description'] ?? '',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on_rounded, size: 12,
                color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Expanded(child: Text(data['locationName'] ?? '',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
            Text(date, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          ]),
          const SizedBox(height: 4),
          Text('By: ${data['userName'] ?? ''}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          if (status == 'Recovered') ...[
            const SizedBox(height: 6),
            const Row(children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: 12, color: AppColors.success),
              SizedBox(width: 4),
              Text('Returned to owner', style: TextStyle(
                  fontSize: 11, color: AppColors.success,
                  fontWeight: FontWeight.w600)),
            ]),
          ],
          if (!isHistory) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('lost_found').doc(docId)
                      .update({'is_active': false, 'status': 'Removed',
                    'updatedAt': FieldValue.serverTimestamp()});
                },
                icon: const Icon(Icons.visibility_off_rounded,
                    size: 14, color: AppColors.error),
                label: const Text('Remove',
                    style: TextStyle(color: AppColors.error, fontSize: 12)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  void _showDetailSheet(BuildContext ctx, Color typeColor, String date, String imageUrl) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.96,
        minChildSize: 0.5,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            Center(child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(data['itemType'] == 'Found'
                        ? Icons.volunteer_activism_rounded
                        : Icons.search_rounded,
                        color: typeColor, size: 14),
                    const SizedBox(width: 5),
                    Text(data['itemType'] ?? '',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: typeColor)),
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(data['category'] ?? '',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (data['status'] == 'Recovered'
                        ? AppColors.success : AppColors.warning).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text((data['status'] ?? '').toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                          color: data['status'] == 'Recovered'
                              ? AppColors.success : AppColors.warning)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  if (imageUrl.isNotEmpty) ...[
                    ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: imageUrl.startsWith('data:image')
                            ? Image.memory(base64Decode(imageUrl.split(',').last),
                            width: double.infinity, fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => Container(
                                height: 200, color: Colors.grey.shade100,
                                child: const Center(child: Text('Image unavailable',
                                    style: TextStyle(color: Colors.grey)))))
                            : Image.network(imageUrl,
                            width: double.infinity, fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => Container(
                                height: 200, color: Colors.grey.shade100,
                                child: const Center(child: Text('Image unavailable',
                                    style: TextStyle(color: Colors.grey)))))
                    ),
                    const SizedBox(height: 20),
                  ],
                  _detailRow('DESCRIPTION', data['description'] ?? ''),
                  const SizedBox(height: 14),
                  _detailRow('LOCATION', data['locationName'] ?? ''),
                  const SizedBox(height: 14),
                  _detailRow('POSTED BY', data['userName'] ?? ''),
                  const SizedBox(height: 14),
                  _detailRow('DATE', date),
                  if ((data['contactInfo'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _detailRow('CONTACT', data['contactInfo'] ?? ''),
                  ],
                  if ((data['ownerUserId'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _detailRow('CLAIMED BY (UID)', data['ownerUserId'] ?? ''),
                  ],
                  const SizedBox(height: 24),
                  if (!isHistory)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await FirebaseFirestore.instance
                              .collection('lost_found').doc(docId)
                              .update({'is_active': false, 'status': 'Removed',
                            'updatedAt': FieldValue.serverTimestamp()});
                        },
                        icon: const Icon(Icons.visibility_off_rounded,
                            size: 16, color: AppColors.error),
                        label: const Text('Remove Listing',
                            style: TextStyle(color: AppColors.error,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10,
          fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.8)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 14,
          color: Color(0xFF1A1A2E), height: 1.4)),
    ],
  );
}

// ── Helper widgets ─────────────────────────────────────────────────────
Widget _InfoRow(String label, String value) {
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(
      width: 150,
      child: Text('$label:',
          style: const TextStyle(fontSize: 12,
              color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
    ),
    Expanded(child: Text(value,
        style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
  ]);
}