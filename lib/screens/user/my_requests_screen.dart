import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/services/offline_request_store.dart';
import 'package:assa/widgets/common/rating_dialog.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});
  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen>
    with WidgetsBindingObserver {

  List<Map<String, dynamic>> _offlineItems = [];
  bool _offlineLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOfflineRequests();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadOfflineRequests();
  }

  Future<void> _loadOfflineRequests() async {
    final requests = await OfflineRequestStore.instance.getAll();
    if (!mounted) return;
    setState(() {
      _offlineItems = requests.map((r) => <String, dynamic>{
        'id':                r.pid,
        'requestType':       'offline',
        'pickupId':          r.pid,
        'pickupLocation':    r.pickupLocation,
        'origin':            r.pickupLocation,
        'destination':       r.destination,
        'rideType':          r.rideType,
        'rideTypeName':      r.rideType,
        'passengerCount':    r.passengerCount,
        'status':            (r.status == OfflineStatus.accepted ||
            r.status == OfflineStatus.confirmed) ? 1
            : (r.status == OfflineStatus.rejected ||
            r.status == OfflineStatus.cancelled) ? 5
            : 0,
        'statusName':        r.status.label,
        'shuttleIdFeedback': r.shuttleId,
        'isSynced':          false,
        'timestamp':         null,
        'createdAt':         Timestamp.fromDate(r.createdAt),
        'isOfflineLocal':    true,
      }).toList();
      _offlineLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
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
                final onlineItems = snapshot.hasData
                    ? snapshot.data!.docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  data['id']          = d.id;
                  data['requestType'] = data['requestType'] ?? 'online';
                  return data;
                }).toList()
                    : <Map<String, dynamic>>[];

                // Deduplicate: If an offline request is now synced in Firestore, 
                // we use the live Firestore version and hide the local static one.
                final syncedOfflineIds = onlineItems
                    .where((item) => item['requestType'] == 'offline' && item['offlineUUID'] != null)
                    .map((item) => item['offlineUUID'] as String)
                    .toSet();

                final localOfflineItems = _offlineItems
                    .where((item) => !syncedOfflineIds.contains(item['id']))
                    .toList();

                final all = [...onlineItems, ...localOfflineItems];
                all.sort((a, b) {
                  final at = a['createdAt'] ?? a['timestamp'];
                  final bt = b['createdAt'] ?? b['timestamp'];
                  if (at == null && bt == null) return 0;
                  if (at == null) return 1;
                  if (bt == null) return -1;
                  if (at is Timestamp && bt is Timestamp) {
                    return bt.compareTo(at);
                  }
                  return 0; // Fallback if they are not Timestamps (e.g. FieldValue)
                });

                final isLoading = snapshot.connectionState ==
                    ConnectionState.waiting && !_offlineLoaded;
                if (isLoading) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary));
                }
                if (all.isEmpty) return _buildEmptyState(context);

                final showAd    = all.length >= 2;
                final itemCount = all.length + (showAd ? 1 : 0);

                return RefreshIndicator(
                  onRefresh: _loadOfflineRequests,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: itemCount,
                    itemBuilder: (ctx, i) {
                      if (showAd && i == 2) return const _InlineAdBanner();
                      final realIndex = (showAd && i > 2) ? i - 1 : i;
                      if (realIndex >= all.length) return const SizedBox.shrink();
                      final data      = all[realIndex];
                      final docId     = data['id'] ?? '';
                      final isOffline = data['requestType'] == 'offline';
                      return _RequestCard(
                        data:               data,
                        docId:              docId,
                        isOffline:          isOffline,
                        onOfflineCancelled: _loadOfflineRequests,
                      );
                    },
                  ),
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
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28)),
        boxShadow: [BoxShadow(color: const Color(0xFF0D47A1).withOpacity(0.35),
            blurRadius: 16, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(children: [
        IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white)),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My Requests',
                style: TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Tap a request to view details or cancel',
                style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_rounded, size: 64, color: AppColors.textHint),
        const SizedBox(height: 16),
        const Text('No requests yet',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        const Text('Your booking history will appear here',
            style: TextStyle(fontSize: 13, color: AppColors.textHint)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Book a Ride'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12)),
        ),
      ]),
    );
  }
}

// ── Inline ad banner — compact card between booking items ─────────────────
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
      FirebaseFirestore.instance
          .collection('ads').doc(ad['_id'] as String).set({
        'impressions': FieldValue.increment(1),
        'lastSeen':    FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((_) {});
    } catch (_) {}
  }

  Future<void> openAdLink(String url) async {
    try {
      String safeUrl = url.trim();
      if (!safeUrl.startsWith('http://') && !safeUrl.startsWith('https://')) {
        safeUrl = 'https://$safeUrl';
      }
      final uri = Uri.parse(safeUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _ad == null) return const SizedBox.shrink();
    final title   = (_ad!['title']   ?? '').toString();
    final body    = (_ad!['body']    ?? '').toString();
    final linkUrl = (_ad!['linkUrl'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: const Color(0xFF0D47A1).withOpacity(0.25),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: linkUrl.isEmpty ? null : () {
            FirebaseFirestore.instance
                .collection('ads').doc(_ad!['_id'] as String).update({
              'taps':    FieldValue.increment(1),
              'lastTap': FieldValue.serverTimestamp(),
            }).catchError((_) {});
            openAdLink(linkUrl);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.campaign_rounded,
                    color: Colors.white70, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('AD',
                      style: TextStyle(color: Colors.white70,
                          fontSize: 8, fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ),
                const SizedBox(height: 3),
                Text(title,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (body.isNotEmpty)
                  Text(body,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.75), fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              GestureDetector(
                onTap: () => setState(() => _dismissed = true),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.6), size: 16),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Request card (supports both online and offline requests) ──────────────
class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool isOffline;
  final VoidCallback? onOfflineCancelled;
  const _RequestCard({
    required this.data,
    required this.docId,
    this.isOffline = false,
    this.onOfflineCancelled,
  });

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context:         context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _RequestDetailSheet(data: data, docId: docId, isOffline: isOffline),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawStatus   = data['status'];
    final statusCode  = rawStatus is int ? rawStatus : 0;
    final statusName  = data['statusName'] ??
        (isOffline
            ? (data['isSynced'] == true ? 'Synced' : 'Pending (Offline)')
            : Esp32Service.getStatusName(statusCode));

    final rideTypeName  = data['rideTypeName'] ?? data['rideType'] ?? 'Shared';
    final origin        = data['pickupLocation'] ?? data['origin'] ?? '';
    final destination   = data['destination'] ?? '';
    final shuttleId     = data['shuttleIdFeedback'] ??
        (data['AFIT KEKE_id'] != null && data['AFIT KEKE_id'] != 0
            ? '${data['AFIT KEKE_id']}'
            : '');

    DateTime createdAt = DateTime.now();
    final ts = data['timestamp'] ?? data['bookedAt'] ?? data['createdAt'];
    if (ts != null) createdAt = (ts as Timestamp).toDate();

    final statusColor = _statusColor(statusCode, isOffline);

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        margin:  const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: statusColor.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(color: statusColor.withOpacity(0.1),
                blurRadius: 10, offset: const Offset(0, 4)),
            BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (isOffline)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.pendingColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('OFFLINE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        color: AppColors.pendingColor)),
              ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  statusColor.withOpacity(0.15),
                  statusColor.withOpacity(0.08)]),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withOpacity(0.4)),
              ),
              child: Text(
                statusName.toUpperCase(),
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: statusColor),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.radio_button_checked_rounded,
                color: AppColors.success, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(origin,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(width: 2, height: 8, color: AppColors.divider),
          ),
          Row(children: [
            const Icon(Icons.location_on_rounded,
                color: AppColors.error, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(destination,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text(
              '$rideTypeName • ${Helpers.formatDateTime(createdAt)}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            const Spacer(),
            if (shuttleId.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color:        AppColors.driverColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('shuttle: $shuttleId',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.driverColor)),
              ),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            const Text('Tap to view',
                style: TextStyle(fontSize: 10, color: AppColors.primary)),
            const Icon(Icons.chevron_right_rounded,
                size: 14, color: AppColors.primary),
          ]),
        ]),
      ),
    );
  }

  Color _statusColor(int code, bool isOffline) {
    if (isOffline) return AppColors.pendingColor;
    if (code == 0) return AppColors.pendingColor;
    if (code >= 4) return AppColors.success;
    if (code == 5) return AppColors.error;
    switch (code) {
      case 0: return AppColors.pendingColor;
      case 1: return AppColors.primary;
      case 2: return Colors.orange;
      case 3: return Colors.teal;
      case 4: return AppColors.success;
      case 5: return AppColors.error;
      default: return AppColors.textSecondary;
    }
  }
}

// ── Request detail bottom sheet (supports both online and offline) ────────
class _RequestDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool isOffline;
  const _RequestDetailSheet({required this.data, required this.docId, this.isOffline = false});

  Future<void> _cancel(BuildContext context) async {
    // For locally-stored offline requests, cancel in the local store
    if (isOffline || (data['isOfflineLocal'] == true)) {
      final pid = data['id'] as String? ?? data['pickupId'] as String? ?? '';
      if (pid.isEmpty) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title:   const Text('Cancel Request?'),
          content: const Text('Remove this offline request from your history?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Yes, Cancel',
                    style: TextStyle(color: AppColors.error))),
          ],
        ),
      );
      if (confirmed == true) {
        await OfflineRequestStore.instance.cancel(pid);
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Offline request removed.'),
                  backgroundColor: AppColors.success));
        }
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:   const Text('Cancel Request?'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Cancel',
                  style: TextStyle(color: AppColors.error))),
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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request cancelled.'),
                backgroundColor: AppColors.success));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // For offline requests, use static data (no live stream)
    if (isOffline) {
      return _buildStaticDetail(context);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ride_requests')
          .doc(docId)
          .snapshots(),
      builder: (context, snapshot) {
        final liveData = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!.data() as Map<String, dynamic>
            : data;

        return _buildDetailContent(context, liveData, docId, false);
      },
    );
  }

  Widget _buildStaticDetail(BuildContext context) {
    return _buildDetailContent(context, data, docId, true);
  }

  Widget _buildDetailContent(BuildContext context, Map<String, dynamic> liveData, String docId, bool isOffline) {
    final rawStatus    = liveData['status'];
    final statusCode   = rawStatus is int ? rawStatus : 0;
    final statusName   = liveData['statusName'] ??
        (isOffline
            ? (liveData['isSynced'] == true ? 'Synced' : 'Pending (Offline)')
            : Esp32Service.getStatusName(statusCode));
    final origin       = liveData['pickupLocation'] ?? liveData['origin'] ?? '';
    final destination  = liveData['destination'] ?? '';
    final rideTypeName = liveData['rideTypeName'] ?? liveData['rideType'] ?? 'Shared';
    final shuttleId    = liveData['shuttleIdFeedback'] ??
        (liveData['AFIT KEKE_id'] != null && liveData['AFIT KEKE_id'] != 0
            ? '${liveData['AFIT KEKE_id']}'
            : '');

    final ts = liveData['timestamp'] ?? liveData['bookedAt'] ?? liveData['createdAt'];
    final createdAt = ts != null
        ? (ts as Timestamp).toDate()
        : DateTime.now();

    final statusColor = _statusColor(statusCode, isOffline);
    final statusIcon  = _statusIcon(statusCode, isOffline);

    return Container(
      padding:    const EdgeInsets.all(24),
      decoration: const BoxDecoration(
          color:        AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
                color:  statusColor.withOpacity(0.1),
                shape:  BoxShape.circle),
            child: Icon(statusIcon, color: statusColor, size: 32),
          ),
          const SizedBox(height: 12),
          Text(statusName,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: statusColor)),
          Text(_statusSubtext(statusCode, shuttleId: shuttleId, isOffline: isOffline),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('Live updates',
                style: TextStyle(
                    fontSize: 10, color: AppColors.success,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 20),
          Container(
            width:      double.infinity,
            padding:    const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color:        AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: AppColors.cardBorder)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(Icons.radio_button_checked_rounded,
                      AppColors.success, 'From', origin),
                  const SizedBox(height: 10),
                  _DetailRow(Icons.location_on_rounded,
                      AppColors.error, 'To', destination),
                  const Divider(height: 20, color: AppColors.divider),
                  _DetailRow(Icons.directions_bus_rounded,
                      AppColors.primary, 'Ride Type', rideTypeName),
                  const SizedBox(height: 10),
                  _DetailRow(Icons.access_time_rounded,
                      AppColors.textSecondary, 'Submitted',
                      Helpers.formatDateTime(createdAt)),
                  if (shuttleId.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _DetailRow(Icons.confirmation_number_rounded,
                        AppColors.driverColor, 'AFIT KEKE ID', shuttleId),
                  ],
                  if (isOffline && liveData['isSynced'] == false) ...[
                    const SizedBox(height: 10),
                    _DetailRow(Icons.sync_rounded,
                        AppColors.pendingColor, 'Status', 'Waiting to sync with network'),
                  ],
                ]),
          ),
          const SizedBox(height: 20),
          _buildStatusStepper(statusCode, isOffline),
          const SizedBox(height: 20),
          if (statusCode == 4 && liveData['isRated'] != true && shuttleId.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => RatingDialog(
                      shuttleId: shuttleId,
                      requestId: docId,
                    ),
                  );
                },
                icon: const Icon(Icons.star_rounded, color: Colors.white),
                label: const Text('Rate Your Driver', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (statusCode < 4 && !isOffline) ...[
            SizedBox(
              width: double.infinity,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _cancel(context),
                      icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.error),
                      label: const Text('Cancel', style: TextStyle(color: AppColors.error)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.error),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('ride_requests')
                            .doc(docId)
                            .update({'status': 4, 'statusName': 'Completed'});
                        if (context.mounted && shuttleId.isNotEmpty) {
                          await showDialog(
                            context: context,
                            builder: (_) => RatingDialog(
                              shuttleId: shuttleId,
                              requestId: docId,
                            ),
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 18, color: Colors.white),
                      label: const Text('Complete', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close',
                  style: TextStyle(color: AppColors.textSecondary))),
        ]),
      ),
    );
  }

  Widget _buildStatusStepper(int currentStatus, bool isOffline) {
    if (isOffline) {
      final isSynced = data['isSynced'] == true;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSynced ? AppColors.successLight : AppColors.pendingLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSynced ? AppColors.success : AppColors.pendingColor),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(isSynced ? Icons.cloud_done_rounded : Icons.sync_problem_rounded,
              color: isSynced ? AppColors.success : AppColors.pendingColor, size: 16),
          const SizedBox(width: 6),
          Text(isSynced ? 'Request synced to cloud' : 'Pending network sync',
              style: TextStyle(fontSize: 12, color: isSynced ? AppColors.success : AppColors.pendingColor)),
        ]),
      );
    }

    if (currentStatus == 5) {
      return Container(
        padding:    const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: AppColors.error.withOpacity(0.2)),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cancel_rounded, color: AppColors.error, size: 16),
          SizedBox(width: 6),
          Text('This request was cancelled',
              style: TextStyle(
                  fontSize: 13, color: AppColors.error,
                  fontWeight: FontWeight.w600)),
        ]),
      );
    }

    // 3-step flow: Request Sent → Driver Accepted → Completed
    // Status codes 2,3 treated as step 1; 4+ treated as step 2 (but we already handled 5 above)
    final stepStatus = currentStatus >= 4 ? 2 : currentStatus >= 1 ? 1 : 0;
    final steps = [
      {'code': 0, 'label': 'Request Sent'},
      {'code': 1, 'label': 'Accepted'},
      {'code': 2, 'label': 'Completed'},
    ];

    return Row(
      children: steps.asMap().entries.map((entry) {
        final i         = entry.key;
        final step      = entry.value;
        final code      = step['code'] as int;
        final label     = step['label'] as String;
        final isDone    = stepStatus > code;
        final isCurrent = stepStatus == code;

        return Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                Container(
                  width: 24, height: 24,
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
                    size:  isDone ? 14 : 8,
                    color: (isDone || isCurrent) ? Colors.white : AppColors.textHint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: isCurrent
                          ? FontWeight.w700 : FontWeight.w400,
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
                  width: 2, height: 2,
                  color: isDone ? AppColors.success : AppColors.divider),
          ]),
        );
      }).toList(),
    );
  }

  Color _statusColor(int code, bool isOffline) {
    if (isOffline) return AppColors.pendingColor;
    if (code == 0) return AppColors.pendingColor;
    if (code >= 4) return AppColors.success;
    if (code == 5) return AppColors.error;
    switch (code) {
      case 0: return AppColors.pendingColor;
      case 1: return AppColors.primary;
      case 2: return Colors.orange;
      case 3: return Colors.teal;
      case 4: return AppColors.success;
      case 5: return AppColors.error;
      default: return AppColors.textSecondary;
    }
  }

  IconData _statusIcon(int code, bool isOffline) {
    if (isOffline) return Icons.wifi_rounded;
    switch (code) {
      case 0: return Icons.pending_rounded;
      case 1: return Icons.assignment_turned_in_rounded;
      case 2: return Icons.directions_bus_rounded;
      case 3: return Icons.airline_seat_recline_extra_rounded;
      case 4: return Icons.check_circle_rounded;
      case 5: return Icons.cancel_rounded;
      default: return Icons.help_rounded;
    }
  }

  String _statusSubtext(int code, {String shuttleId = '', bool isOffline = false}) {
    if (isOffline) return 'Your request will sync when you reconnect to the internet';
    switch (code) {
      case 0: return 'Waiting for a driver to accept';
      case 1: return 'An AFIT KEKE is on the way';
      case 2: return shuttleId.isNotEmpty
          ? 'AFIT KEKE $shuttleId is on the way — get ready!'
          : 'Your AFIT KEKE is on the way — get ready!';
      case 3: return 'You are on board. Enjoy your ride!';
      case 4: return 'Ride complete. Thank you for using ASSA!';
      case 5: return 'This request was cancelled';
      default: return '';
    }
  }
}

Widget _DetailRow(IconData icon, Color color, String label, String value) {
  return Row(children: [
    Icon(icon, color: color, size: 16),
    const SizedBox(width: 8),
    Text('$label: ', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    Expanded(
      child: Text(value,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
    ),
  ]);
}
