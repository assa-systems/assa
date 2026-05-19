import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/widgets/common/ad_overlay.dart';

class MyRequestsScreen extends StatelessWidget {
  const MyRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('ride_requests')
                  .where('userId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState(context);
                }
                final docs = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final ad = (a.data() as Map)['timestamp'] ??
                        (a.data() as Map)['bookedAt'];
                    final bd = (b.data() as Map)['timestamp'] ??
                        (b.data() as Map)['bookedAt'];
                    if (ad == null && bd == null) return 0;
                    if (ad == null) return 1;
                    if (bd == null) return -1;
                    return (bd as Timestamp).compareTo(ad as Timestamp);
                  });

                // Ad injected after 2nd card when 2+ bookings exist
                final showAd = docs.length >= 2;
                final itemCount = docs.length + (showAd ? 1 : 0);

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: itemCount,
                  itemBuilder: (ctx, i) {
                    if (showAd && i == 2) return const _InlineAdBanner();
                    final realIndex = (showAd && i > 2) ? i - 1 : i;
                    if (realIndex >= docs.length) return const SizedBox.shrink();
                    final data = docs[realIndex].data() as Map<String, dynamic>;
                    final docId = docs[realIndex].id;
                    return _RequestCard(data: data, docId: docId);
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
        gradient: const LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1976D2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0D47A1).withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white, size: 20)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My Requests',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('Track your ride history',
                style: TextStyle(
                    color: Color(0xAAFFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.receipt_long_rounded,
              size: 56, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        const Text('No requests yet',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        const Text('Your booking history will appear here',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Book a Ride'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
        ),
      ]),
    );
  }
}

class _InlineAdBanner extends StatefulWidget {
  const _InlineAdBanner();
  @override
  State<_InlineAdBanner> createState() => _InlineAdBannerState();
}

class _InlineAdBannerState extends State<_InlineAdBanner> {
  Map<String, dynamic>? _ad;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ads')
          .where('isActive', isEqualTo: true)
          .get();
      final active = snap.docs
          .map((d) => {'_id': d.id, ...d.data()})
          .where((a) => (a['title'] ?? '').toString().trim().isNotEmpty)
          .toList();
      if (active.isEmpty || !mounted) return;
      active.shuffle();
      final ad = active.first;
      setState(() => _ad = ad);
      FirebaseFirestore.instance.collection('ads').doc(ad['_id'] as String).update({
        'impressions': FieldValue.increment(1),
        'lastSeen': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _ad == null) return const SizedBox.shrink();
    final title = (_ad!['title'] ?? '').toString();
    final body = (_ad!['body'] ?? '').toString();
    final linkUrl = (_ad!['linkUrl'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0D47A1).withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: linkUrl.isEmpty
              ? null
              : () {
                  FirebaseFirestore.instance
                      .collection('ads')
                      .doc(_ad!['_id'] as String)
                      .update({
                    'taps': FieldValue.increment(1),
                    'lastTap': FieldValue.serverTimestamp(),
                  }).catchError((_) {});
                  openAdLink(linkUrl);
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.campaign_rounded,
                    color: Colors.white70, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('AD',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                    ),
                    const SizedBox(height: 4),
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (body.isNotEmpty)
                      Text(body,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ])),
              GestureDetector(
                onTap: () => setState(() => _dismissed = true),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.6), size: 18),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _RequestCard({required this.data, required this.docId});

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _RequestDetailSheet(data: data, docId: docId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawStatus = data['status'];
    final statusCode = rawStatus is int ? rawStatus : 0;
    final statusName =
        data['statusName'] ?? Esp32Service.getStatusName(statusCode);

    final rideTypeName = data['rideTypeName'] ?? data['rideType'] ?? 'Shared';
    final origin = data['pickupLocation'] ?? data['origin'] ?? '';
    final destination = data['destination'] ?? '';
    final shuttleId = data['shuttleIdFeedback'] ??
        (data['shuttle_id'] != null && data['shuttle_id'] != 0
            ? '${data['shuttle_id']}'
            : '');

    DateTime createdAt = DateTime.now();
    final ts = data['timestamp'] ?? data['bookedAt'];
    if (ts != null) createdAt = (ts as Timestamp).toDate();

    final statusColor = _statusColor(statusCode);

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusColor.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: statusColor.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4)),
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 1)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Status badge
          Row(children: [
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  statusColor.withOpacity(0.15),
                  statusColor.withOpacity(0.08)
                ]),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _statusIcon(statusCode, size: 14, color: statusColor),
                  const SizedBox(width: 6),
                  Text(
                    statusName.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),

          // Route info
          Row(children: [
            const Icon(Icons.radio_button_checked_rounded,
                color: AppColors.success, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(origin,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 7, top: 6, bottom: 6),
            child:
                Container(width: 2, height: 10, color: AppColors.divider),
          ),
          Row(children: [
            const Icon(Icons.location_on_rounded,
                color: AppColors.error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(destination,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
          ]),
          const SizedBox(height: 12),

          // Footer info
          Row(children: [
            Text(
              '$rideTypeName • ${Helpers.formatDateTime(createdAt)}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            const Spacer(),
            if (shuttleId.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.driverColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.driverColor.withOpacity(0.3))),
                child: Text('Shuttle: $shuttleId',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.driverColor)),
              ),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('Tap for details',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.primary),
          ]),
        ]),
      ),
    );
  }

  Color _statusColor(int code) {
    switch (code) {
      case 0:
        return AppColors.pendingColor;
      case 1:
        return AppColors.primary;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.teal;
      case 4:
        return AppColors.success;
      case 5:
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _statusIcon(int code,
      {double size = 14, Color color = Colors.black}) {
    IconData icon;
    switch (code) {
      case 0:
        icon = Icons.pending_rounded;
        break;
      case 1:
        icon = Icons.assignment_turned_in_rounded;
        break;
      case 2:
        icon = Icons.directions_bus_rounded;
        break;
      case 3:
        icon = Icons.airline_seat_recline_extra_rounded;
        break;
      case 4:
        icon = Icons.check_circle_rounded;
        break;
      case 5:
        icon = Icons.cancel_rounded;
        break;
      default:
        icon = Icons.help_rounded;
    }
    return Icon(icon, size: size, color: color);
  }
}

class _RequestDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _RequestDetailSheet({required this.data, required this.docId});

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Request?',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: const Text('Are you sure you want to cancel this booking?',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Cancel',
                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('ride_requests')
          .doc(docId)
          .update({'status': 5, 'statusName': 'Cancelled'});
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text('Request cancelled'),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ride_requests')
          .doc(docId)
          .snapshots(),
      builder: (context, snapshot) {
        final liveData = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!.data() as Map<String, dynamic>
            : data;

        final rawStatus = liveData['status'];
        final statusCode = rawStatus is int ? rawStatus : 0;
        final statusName =
            liveData['statusName'] ?? Esp32Service.getStatusName(statusCode);
        final origin = liveData['pickupLocation'] ?? liveData['origin'] ?? '';
        final destination = liveData['destination'] ?? '';
        final rideTypeName =
            liveData['rideTypeName'] ?? liveData['rideType'] ?? 'Shared';
        final shuttleId = liveData['shuttleIdFeedback'] ??
            (liveData['shuttle_id'] != null && liveData['shuttle_id'] != 0
                ? '${liveData['shuttle_id']}'
                : '');

        final ts = liveData['timestamp'] ?? liveData['bookedAt'];
        final createdAt =
            ts != null ? (ts as Timestamp).toDate() : DateTime.now();

        final statusColor = _statusColor(statusCode);
        final statusIcon = _statusIcon(statusCode);

        return Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(statusIcon, color: statusColor, size: 36),
              ),
              const SizedBox(height: 16),
              Text(statusName,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: statusColor)),
              Text(_statusSubtext(statusCode, shuttleId: shuttleId),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Live updates',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder, width: 1)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailRow(Icons.radio_button_checked_rounded,
                            AppColors.success, 'From', origin),
                        const SizedBox(height: 14),
                        _DetailRow(Icons.location_on_rounded, AppColors.error,
                            'To', destination),
                        const Divider(
                            height: 20, color: AppColors.divider, thickness: 1),
                        _DetailRow(Icons.directions_bus_rounded,
                            AppColors.primary, 'Ride Type', rideTypeName),
                        const SizedBox(height: 14),
                        _DetailRow(
                            Icons.access_time_rounded,
                            AppColors.textSecondary,
                            'Submitted',
                            Helpers.formatDateTime(createdAt)),
                        if (shuttleId.isNotEmpty) ...[  
                          const SizedBox(height: 14),
                          _DetailRow(Icons.confirmation_number_rounded,
                              AppColors.driverColor, 'Shuttle ID', shuttleId),
                        ],
                      ]),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildStatusStepper(statusCode),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  if (statusCode == 0) ...[  
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _cancel(context),
                        icon: const Icon(Icons.cancel_outlined,
                            size: 18, color: AppColors.error),
                        label: const Text('Cancel This Request',
                            style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppColors.error, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600))),
                ]),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildStatusStepper(int currentStatus) {
    final steps = [
      {'code': 0, 'label': 'Pending'},
      {'code': 1, 'label': 'Assigned'},
      {'code': 2, 'label': 'Arriving'},
      {'code': 3, 'label': 'Picked Up'},
      {'code': 4, 'label': 'Completed'},
    ];

    if (currentStatus == 5) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withOpacity(0.2), width: 1.5),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cancel_rounded, color: AppColors.error, size: 18),
          SizedBox(width: 8),
          Text('This request was cancelled',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.error,
                  fontWeight: FontWeight.w700)),
        ]),
      );
    }

    return Row(
      children: steps.asMap().entries.map((entry) {
        final i = entry.key;
        final step = entry.value;
        final code = step['code'] as int;
        final label = step['label'] as String;
        final isDone = currentStatus > code;
        final isCurrent = currentStatus == code;

        return Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.success
                        : isCurrent
                            ? AppColors.primary
                            : AppColors.divider,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : Icons.circle,
                    size: isDone ? 16 : 8,
                    color: (isDone || isCurrent) ? Colors.white : AppColors.textHint,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent
                          ? AppColors.primary
                          : isDone
                              ? AppColors.success
                              : AppColors.textHint),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
            if (i < steps.length - 1)
              Container(
                  width: 2,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  color: isDone ? AppColors.success : AppColors.divider),
          ]),
        );
      }).toList(),
    );
  }

  Color _statusColor(int code) {
    switch (code) {
      case 0:
        return AppColors.pendingColor;
      case 1:
        return AppColors.primary;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.teal;
      case 4:
        return AppColors.success;
      case 5:
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _statusIcon(int code) {
    switch (code) {
      case 0:
        return Icons.pending_rounded;
      case 1:
        return Icons.assignment_turned_in_rounded;
      case 2:
        return Icons.directions_bus_rounded;
      case 3:
        return Icons.airline_seat_recline_extra_rounded;
      case 4:
        return Icons.check_circle_rounded;
      case 5:
        return Icons.cancel_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  String _statusSubtext(int code, {String shuttleId = ''}) {
    switch (code) {
      case 0:
        return 'Waiting for a driver to accept';
      case 1:
        return 'A driver is on the way';
      case 2:
        return shuttleId.isNotEmpty
            ? 'Shuttle $shuttleId is arriving soon'
            : 'Your shuttle is on the way';
      case 3:
        return 'You are on board. Enjoy your ride!';
      case 4:
        return 'Ride complete. Thank you for using ASSA!';
      case 5:
        return 'This request was cancelled';
      default:
        return '';
    }
  }
}

Widget _DetailRow(
    IconData icon, Color color, String label, String value) {
  return Row(children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 10),
    Text('$label: ',
        style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600)),
    Expanded(
      child: Text(value,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
    ),
  ]);
}
