import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/esp32_service.dart';

// ======================================================================
// ADMIN: ALL BOOKINGS — READ-ONLY MONITOR
// The ESP32 gateway is the ONLY system that assigns shuttles and updates
// ride statuses. Admin monitors here — no manual assignment allowed.
// Admin can cancel a pending ride in an emergency only.
// ======================================================================

class ManageBookingsScreen extends StatefulWidget {
  const ManageBookingsScreen({super.key});
  @override
  State<ManageBookingsScreen> createState() => _ManageBookingsScreenState();
}

class _ManageBookingsScreenState extends State<ManageBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: SafeArea(child: Column(children: [
        _buildHeader(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search by name or location...',
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppColors.textHint, size: 20),
              filled: true, fillColor: AppColors.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.inputBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.inputBorder)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
            ),
          ),
        ),
        _LiveStatsRow(),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: TabBar(
            controller: _tab,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700),
            indicator: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(10)),
            tabs: const [Tab(text: 'Online'), Tab(text: 'Offline'),
              Tab(text: 'Credit')],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: TabBarView(controller: _tab, children: [
          _BookingList(type: 'online',  search: _search),
          _BookingList(type: 'offline', search: _search),
          _BookingList(type: 'credit',  search: _search),
        ])),
      ])),
    );
  }

  Widget _buildHeader(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
          colors: [AppColors.adminColor, Color(0xFF1565C0)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    child: Row(children: [
      GestureDetector(onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 22)),
      const SizedBox(width: 12),
      const Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('All Bookings', style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.w800, color: Colors.white)),
        Text('Gateway-managed · Read-only monitor',
            style: TextStyle(fontSize: 11, color: Colors.white70)),
      ])),
      const Icon(Icons.monitor_rounded, color: Colors.white, size: 24),
    ]),
  );
}

// ── Live summary stats ─────────────────────────────────────────────────
class _LiveStatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('ride_requests').snapshots(),
      builder: (_, snap) {
        final docs    = snap.data?.docs ?? [];
        final total   = docs.length;
        final pending = docs.where((d) => (d.data() as Map)['status'] == 0).length;
        final active  = docs.where((d) {
          final s = (d.data() as Map)['status'];
          return s == 1 || s == 2 || s == 3;
        }).length;
        final done    = docs.where((d) => (d.data() as Map)['status'] == 4).length;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _StatChip('Total',   '$total',   AppColors.primary),
            const SizedBox(width: 8),
            _StatChip('Pending', '$pending', AppColors.pendingColor),
            const SizedBox(width: 8),
            _StatChip('Active',  '$active',  AppColors.success),
            const SizedBox(width: 8),
            _StatChip('Done',    '$done',    AppColors.textSecondary),
          ]),
        );
      },
    );
  }
}

Widget _StatChip(String label, String value, Color color) => Expanded(
  child: Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 16,
          fontWeight: FontWeight.w800, color: color)),
      Text(label, style: const TextStyle(fontSize: 10,
          color: AppColors.textSecondary)),
    ]),
  ),
);

// ── Booking list ───────────────────────────────────────────────────────
class _BookingList extends StatelessWidget {
  final String type, search;
  const _BookingList({required this.type, required this.search});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ride_requests')
          .where('requestType', isEqualTo: type)
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: AppColors.adminColor));
        final allDocs = snap.data!.docs.toList()
          ..sort((a, b) {
            final at = (a.data() as Map)['timestamp'];
            final bt = (b.data() as Map)['timestamp'];
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
        final docs = allDocs.where((d) {
          if (search.isEmpty) return true;
          final data = d.data() as Map<String, dynamic>;
          final name = (data['userName'] ?? '').toString().toLowerCase();
          final pick = (data['pickupLocation'] ?? '').toString().toLowerCase();
          final dest = (data['destination'] ?? '').toString().toLowerCase();
          return name.contains(search) || pick.contains(search) ||
              dest.contains(search);
        }).toList();

        if (docs.isEmpty) return Center(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_rounded,
              size: 48, color: AppColors.textHint.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text('No $type requests',
              style: const TextStyle(color: AppColors.textHint)),
        ]));

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return _BookingCard(docId: docs[i].id, data: data);
          },
        );
      },
    );
  }
}

// ── Booking card ───────────────────────────────────────────────────────
class _BookingCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  const _BookingCard({required this.docId, required this.data});

  Color _statusColor(int code) {
    switch (code) {
      case 0: return AppColors.pendingColor;
      case 1: return AppColors.primary;
      case 2: return AppColors.accent;
      case 3: return AppColors.success;
      case 4: return AppColors.textSecondary;
      case 5: return AppColors.error;
      default: return AppColors.textHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawStatus  = data['status'];
    final statusCode = rawStatus is int ? rawStatus
        : int.tryParse(rawStatus?.toString() ?? '') ?? 0;
    final statusName  = Esp32Service.getStatusName(statusCode);
    final statusColor = _statusColor(statusCode);
    final name    = data['userName'] ?? 'Unknown';
    final pickup  = data['pickupLocation'] ?? data['origin'] ?? '—';
    final dest    = data['destination'] ?? '—';
    final shuttle = data['shuttleIdFeedback'] ?? '';
    final rideType = data['rideTypeName'] ?? 'Shared';
    final pax     = data['passengerCount'] ?? 1;
    final ts      = data['timestamp'] as Timestamp?;
    final time    = ts != null ? Helpers.formatDateTime(ts.toDate()) : '—';

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _DetailSheet(docId: docId, data: data,
            statusCode: statusCode, statusColor: statusColor,
            statusName: statusName),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [BoxShadow(color: AppColors.shadow,
              blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(statusName, style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.radio_button_checked_rounded,
                color: AppColors.success, size: 13),
            const SizedBox(width: 4),
            Expanded(child: Text(pickup, style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary))),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.location_on_rounded,
                color: AppColors.error, size: 13),
            const SizedBox(width: 4),
            Expanded(child: Text(dest, style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _Tag(rideType == 'Chartered'
                ? '🚌 Chartered' : '🚐 Shared · $pax pax', AppColors.primary),
            if (shuttle.isNotEmpty) ...[ const SizedBox(width: 6),
              _Tag('🚌 $shuttle', AppColors.driverColor)],
            const Spacer(),
            Text(time, style: const TextStyle(
                fontSize: 10, color: AppColors.textHint)),
          ]),
        ]),
      ),
    );
  }
}

Widget _Tag(String label, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8)),
  child: Text(label, style: TextStyle(fontSize: 10,
      fontWeight: FontWeight.w600, color: color)),
);

// ── Detail bottom sheet ────────────────────────────────────────────────
class _DetailSheet extends StatelessWidget {
  final String docId, statusName;
  final Map<String, dynamic> data;
  final int statusCode;
  final Color statusColor;
  const _DetailSheet({required this.docId, required this.data,
    required this.statusCode, required this.statusColor,
    required this.statusName});

  IconData _statusIcon(int code) {
    switch (code) {
      case 0: return Icons.hourglass_empty_rounded;
      case 1: return Icons.directions_bus_rounded;
      case 2: return Icons.near_me_rounded;
      case 3: return Icons.airline_seat_recline_normal_rounded;
      case 4: return Icons.check_circle_rounded;
      case 5: return Icons.cancel_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Ride?'),
        content: const Text('This will cancel the request. Use only in emergencies.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false),
              child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(_, true),
              child: const Text('Yes, Cancel',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('ride_requests').doc(docId)
          .update({'status': 5, 'statusName': 'Cancelled'});
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name     = data['userName'] ?? '—';
    final pickup   = data['pickupLocation'] ?? data['origin'] ?? '—';
    final dest     = data['destination'] ?? '—';
    final rideType = data['rideTypeName'] ?? 'Shared';
    final pax      = data['passengerCount'] ?? 1;
    final shuttle  = data['shuttleIdFeedback'] ?? '';
    final type     = data['requestType'] ?? 'online';
    final pCode    = data['pickup_code'];
    final dCode    = data['destination_code'];
    final rCode    = data['ride_type'];
    final sCode    = data['shuttle_id'];
    final uid      = data['userId'] ?? '—';
    final ts       = data['timestamp'] as Timestamp?;
    final time     = ts != null ? Helpers.formatDateTime(ts.toDate()) : '—';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.divider,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Container(width: 60, height: 60,
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1),
                shape: BoxShape.circle),
            child: Center(child: Icon(_statusIcon(statusCode),
                color: statusColor, size: 30))),
        const SizedBox(height: 8),
        Text(statusName, style: TextStyle(fontSize: 16,
            fontWeight: FontWeight.w800, color: statusColor)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(
              color: AppColors.success, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          const Text('Live from Firebase', style: TextStyle(fontSize: 10,
              color: AppColors.success, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder)),
          child: Column(children: [
            _DRow(Icons.person_rounded, AppColors.primary, 'Passenger', name),
            const SizedBox(height: 10),
            _DRow(Icons.fingerprint_rounded, AppColors.textHint, 'User ID',
                uid.length > 14 ? '${uid.substring(0, 14)}...' : uid),
            const Divider(height: 20, color: AppColors.divider),
            _DRow(Icons.radio_button_checked_rounded, AppColors.success,
                'From', pCode != null ? '$pickup (code $pCode)' : pickup),
            const SizedBox(height: 10),
            _DRow(Icons.location_on_rounded, AppColors.error,
                'To', dCode != null ? '$dest (code $dCode)' : dest),
            const Divider(height: 20, color: AppColors.divider),
            _DRow(Icons.directions_bus_rounded, AppColors.primary, 'Ride Type',
                rCode != null ? '$rideType (code $rCode)' : rideType),
            const SizedBox(height: 10),
            _DRow(Icons.people_rounded, AppColors.accent, 'Passengers', '$pax'),
            if (shuttle.isNotEmpty) ...[ const SizedBox(height: 10),
              _DRow(Icons.confirmation_number_rounded, AppColors.driverColor,
                  'Shuttle', sCode != null
                      ? '$shuttle (code $sCode)' : shuttle)],
            const SizedBox(height: 10),
            _DRow(Icons.wifi_rounded,
                type == 'online' ? AppColors.userColor : AppColors.pendingColor,
                'Type', type == 'online' ? 'Online (Firebase)'
                    : type == 'offline' ? 'Offline (ESP32 LoRa)' : 'Credit Ride'),
            const SizedBox(height: 10),
            _DRow(Icons.access_time_rounded, AppColors.textSecondary,
                'Submitted', time),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.pendingColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.pendingColor.withOpacity(0.2))),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded,
                color: AppColors.pendingColor, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Shuttle assignment and status updates are managed '
                  'automatically by the ESP32 gateway. No manual assignment needed.',
              style: TextStyle(fontSize: 11,
                  color: AppColors.textSecondary, height: 1.5),
            )),
          ]),
        ),
        if (statusCode == 0) ...[ const SizedBox(height: 16),
          SizedBox(width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _cancel(context),
              icon: const Icon(Icons.cancel_outlined,
                  size: 16, color: AppColors.error),
              label: const Text('Cancel (Emergency Only)',
                  style: TextStyle(color: AppColors.error, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ),
        ],
      ])),
    );
  }
}

Widget _DRow(IconData icon, Color color, String label, String value) =>
    Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 8),
      Text('$label: ', style: const TextStyle(
          fontSize: 12, color: AppColors.textSecondary)),
      Expanded(child: Text(value, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
    ]);