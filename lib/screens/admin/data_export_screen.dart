import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/firestore_service.dart';

// ======================================================================
// ADMIN: DATA EXPORT + ANALYTICS
//
// Tabs:
//   Overview   — live stats + bar charts (rides/day, status breakdown)
//   Export     — CSV copy-to-clipboard for bookings, users, drivers
// ======================================================================

class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});
  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen>
    with SingleTickerProviderStateMixin {
  final _firestore = FirestoreService();
  late TabController _tab;

  bool _exportingBookings = false;
  bool _exportingUsers    = false;
  bool _exportingDrivers  = false;

  // Analytics data
  bool _loadingAnalytics = true;
  Map<String, int> _statusBreakdown  = {};
  Map<String, int> _ridesPerDay      = {};
  Map<String, int> _routePopularity  = {};
  int _totalUsers = 0, _totalDrivers = 0,
      _totalBookings = 0, _completedRides = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAnalytics();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  // ── Load all analytics from Firestore ──────────────────────────────
  Future<void> _loadAnalytics() async {
    setState(() => _loadingAnalytics = true);
    try {
      final db = FirebaseFirestore.instance;
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      final results = await Future.wait([
        db.collection('users').where('role', isEqualTo: 'user').get(),
        db.collection('users').where('role', isEqualTo: 'driver')
            .where('status', isEqualTo: 'approved').get(),
        db.collection('ride_requests').get(),
        db.collection('ride_requests')
            .where('timestamp', isGreaterThan: Timestamp.fromDate(sevenDaysAgo))
            .get(),
      ]);

      final allBookings  = results[2].docs;
      final recentRides  = results[3].docs;

      // Status breakdown
      final statusMap = <String, int>{};
      for (final d in allBookings) {
        final data   = d.data() as Map<String, dynamic>;
        final status = data['status'] as int? ?? 0;
        final label  = _statusLabel(status);
        statusMap[label] = (statusMap[label] ?? 0) + 1;
      }

      // Rides per day (last 7 days)
      final perDay = <String, int>{};
      for (int i = 6; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        perDay[_dayLabel(day)] = 0;
      }
      for (final d in recentRides) {
        final data = d.data() as Map<String, dynamic>;
        final ts   = data['timestamp'];
        if (ts == null) continue;
        final date = (ts as Timestamp).toDate();
        final key  = _dayLabel(date);
        if (perDay.containsKey(key)) perDay[key] = (perDay[key] ?? 0) + 1;
      }

      // Route popularity (top destinations)
      final routeMap = <String, int>{};
      for (final d in allBookings) {
        final data = d.data() as Map<String, dynamic>;
        final dest = data['destination']?.toString() ?? 'Unknown';
        if (dest.isNotEmpty && dest != 'Unknown') {
          routeMap[dest] = (routeMap[dest] ?? 0) + 1;
        }
      }
      // Keep top 5
      final sortedRoutes = routeMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top5 = Map.fromEntries(sortedRoutes.take(5));

      final completed = allBookings.where((d) =>
      (d.data() as Map)['status'] == 4).length;

      if (mounted) setState(() {
        _totalUsers      = results[0].docs.length;
        _totalDrivers    = results[1].docs.length;
        _totalBookings   = allBookings.length;
        _completedRides  = completed;
        _statusBreakdown = statusMap;
        _ridesPerDay     = perDay;
        _routePopularity = top5;
        _loadingAnalytics = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAnalytics = false);
    }
  }

  String _dayLabel(DateTime d) =>
      '${_weekday(d.weekday)} ${d.day}/${d.month}';
  String _weekday(int w) =>
      ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][w - 1];

  String _statusLabel(int s) {
    switch (s) {
      case 0: return 'Pending';
      case 1: return 'Assigned';
      case 2: return 'Arriving';
      case 3: return 'Picked Up';
      case 4: return 'Completed';
      case 5: return 'Cancelled';
      default: return 'Unknown';
    }
  }

  Color _statusColor(String label) {
    switch (label) {
      case 'Pending':   return AppColors.textHint;
      case 'Assigned':  return AppColors.primary;
      case 'Arriving':  return AppColors.warning;
      case 'Picked Up': return AppColors.accent;
      case 'Completed': return AppColors.success;
      case 'Cancelled': return AppColors.error;
      default:          return AppColors.textHint;
    }
  }

  // ── CSV helpers ────────────────────────────────────────────────────
  String _toCsv(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return 'No data available.';
    final headers = data.first.keys.toList();
    final rows = <String>[headers.join(',')];
    for (final row in data) {
      final values = headers.map((h) {
        final val     = row[h]?.toString() ?? '';
        final escaped = val.replaceAll('"', '""');
        return (val.contains(',') || val.contains('\n') || val.contains('"'))
            ? '"$escaped"' : escaped;
      }).toList();
      rows.add(values.join(','));
    }
    return rows.join('\n');
  }

  Future<void> _exportBookings() async {
    setState(() => _exportingBookings = true);
    try {
      final data = await _firestore.exportBookingsData();
      if (mounted) {
        setState(() => _exportingBookings = false);
        if (data.isEmpty) { Helpers.showErrorSnackBar(context, 'No bookings found.'); return; }
        _showExportDialog('Bookings & Requests', _toCsv(data), data.length);
      }
    } catch (e) {
      if (mounted) { setState(() => _exportingBookings = false);
      Helpers.showErrorSnackBar(context, 'Export failed.'); }
    }
  }

  Future<void> _exportUsers() async {
    setState(() => _exportingUsers = true);
    try {
      final data = await _firestore.exportUsersData();
      if (mounted) {
        setState(() => _exportingUsers = false);
        if (data.isEmpty) { Helpers.showErrorSnackBar(context, 'No users found.'); return; }
        _showExportDialog('Registered Users', _toCsv(data), data.length);
      }
    } catch (_) {
      if (mounted) setState(() => _exportingUsers = false);
    }
  }

  Future<void> _exportDrivers() async {
    setState(() => _exportingDrivers = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users').where('role', isEqualTo: 'driver').get();
      final data = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m.remove('password'); m.remove('fcmToken');
        return m;
      }).toList();
      if (mounted) {
        setState(() => _exportingDrivers = false);
        if (data.isEmpty) { Helpers.showErrorSnackBar(context, 'No drivers found.'); return; }
        _showExportDialog('Drivers', _toCsv(data), data.length);
      }
    } catch (_) {
      if (mounted) setState(() => _exportingDrivers = false);
    }
  }

  void _showExportDialog(String title, String csv, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('$title ($count records)',
              style: const TextStyle(fontSize: 15))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(10)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Text(csv.length > 2000
                  ? '${csv.substring(0, 2000)}\n... (${csv.length - 2000} more chars)'
                  : csv,
                  style: const TextStyle(fontSize: 10,
                      color: Colors.greenAccent,
                      fontFamily: 'monospace')),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: csv));
                Navigator.pop(ctx);
                Helpers.showSuccessSnackBar(context,
                    'CSV copied! Paste into Excel or Google Sheets.');
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.adminColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              icon: const Icon(Icons.copy_rounded,
                  size: 16, color: Colors.white),
              label: const Text('Copy CSV to Clipboard',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: SafeArea(child: Column(children: [
        _buildHeader(context),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder)),
          child: TabBar(
            controller: _tab,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            indicator: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  Color(0xFF4A148C), Color(0xFF7B1FA2)]),
                borderRadius: BorderRadius.circular(10)),
            tabs: const [Tab(text: '📊  Overview'), Tab(text: '📥  Export')],
          ),
        ),
        Expanded(child: TabBarView(controller: _tab, children: [
          _buildOverviewTab(),
          _buildExportTab(),
        ])),
      ])),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.adminColor, AppColors.adminColor.withOpacity(0.8)]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(children: [
        IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white, size: 20)),
        const Expanded(child: Text('Analytics & Export',
            style: TextStyle(color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w700))),
        IconButton(onPressed: _loadAnalytics,
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white, size: 22)),
      ]),
    );
  }

  // ── Overview Tab ─────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    if (_loadingAnalytics) {
      return const Center(child: CircularProgressIndicator(
          color: AppColors.adminColor));
    }
    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      color: AppColors.adminColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Summary cards ──────────────────────────────────────
              GridView.count(
                crossAxisCount: 2, shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12, mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _SummaryCard('Total Users',    '$_totalUsers',
                      Icons.people_rounded,        AppColors.primary),
                  _SummaryCard('Active Drivers', '$_totalDrivers',
                      Icons.drive_eta_rounded,     AppColors.driverColor),
                  _SummaryCard('Total Bookings', '$_totalBookings',
                      Icons.receipt_long_rounded,  AppColors.accent),
                  _SummaryCard('Completed',      '$_completedRides',
                      Icons.check_circle_rounded,  AppColors.success),
                ],
              ),
              const SizedBox(height: 24),

              // ── Rides per day (last 7 days) ────────────────────────
              _SectionTitle('Rides — Last 7 Days'),
              const SizedBox(height: 12),
              _BarChart(
                data:      _ridesPerDay,
                barColor:  AppColors.primary,
                emptyMsg:  'No rides in the last 7 days',
              ),
              const SizedBox(height: 24),

              // ── Status breakdown ───────────────────────────────────
              _SectionTitle('Booking Status Breakdown'),
              const SizedBox(height: 12),
              _HorizontalBarChart(
                data:       _statusBreakdown,
                colorFn:    _statusColor,
                total:      _totalBookings,
                emptyMsg:   'No bookings yet',
              ),
              const SizedBox(height: 24),

              // ── Top destinations ───────────────────────────────────
              if (_routePopularity.isNotEmpty) ...[
                _SectionTitle('Top Destinations'),
                const SizedBox(height: 12),
                _HorizontalBarChart(
                  data:     _routePopularity,
                  colorFn:  (_) => AppColors.accent,
                  total:    _routePopularity.values.fold(0, (a, b) => a + b),
                  emptyMsg: 'No destination data',
                ),
                const SizedBox(height: 20),
              ],
            ]),
      ),
    );
  }

  // ── Export Tab ───────────────────────────────────────────────────
  Widget _buildExportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle('Export to CSV'),
        const SizedBox(height: 4),
        const Text('Tap any export to copy CSV — paste into Excel or Google Sheets.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        _ExportCard(
          title:    'Bookings & Ride Requests',
          subtitle: 'All ride history — online, offline, credit rides',
          icon:     Icons.receipt_long_rounded,
          color:    AppColors.accent,
          loading:  _exportingBookings,
          onTap:    _exportBookings,
        ),
        const SizedBox(height: 12),
        _ExportCard(
          title:    'Registered Users',
          subtitle: 'Student accounts — name, matric, email',
          icon:     Icons.people_rounded,
          color:    AppColors.primary,
          loading:  _exportingUsers,
          onTap:    _exportUsers,
        ),
        const SizedBox(height: 12),
        _ExportCard(
          title:    'Drivers',
          subtitle: 'Driver profiles — shuttle ID, status, contact',
          icon:     Icons.drive_eta_rounded,
          color:    AppColors.driverColor,
          loading:  _exportingDrivers,
          onTap:    _exportDrivers,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2))),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded,
                color: AppColors.primary, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text(
              'CSV exports include all fields from Firestore. '
                  'Sensitive fields like FCM tokens are excluded from driver exports.',
              style: TextStyle(fontSize: 11,
                  color: AppColors.textSecondary, height: 1.5),
            )),
          ]),
        ),
      ]),
    );
  }
}

// ── Summary Card ───────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SummaryCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    final dark = Color.fromARGB(255,
        (color.red * 0.65).round().clamp(0, 255),
        (color.green * 0.65).round().clamp(0, 255),
        (color.blue * 0.65).round().clamp(0, 255));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, dark],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3),
              blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Icon(icon, color: Colors.white.withOpacity(0.8), size: 22),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontSize: 26,
                  fontWeight: FontWeight.w900, color: Colors.white)),
              Text(label, style: TextStyle(fontSize: 11,
                  color: Colors.white.withOpacity(0.8))),
            ]),
          ]),
    );
  }
}

// ── Bar Chart (rides per day) ──────────────────────────────────────────
class _BarChart extends StatelessWidget {
  final Map<String, int> data;
  final Color barColor;
  final String emptyMsg;
  const _BarChart({required this.data, required this.barColor,
    required this.emptyMsg});

  @override
  Widget build(BuildContext context) {
    final maxVal = data.values.isEmpty ? 1
        : data.values.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder)),
        child: Center(child: Text(emptyMsg,
            style: const TextStyle(color: AppColors.textHint, fontSize: 13))),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [BoxShadow(color: AppColors.shadow,
              blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.entries.map((e) {
            final frac = maxVal == 0 ? 0.0 : e.value / maxVal;
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(children: [
                Text('${e.value}', style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: e.value > 0 ? barColor : AppColors.textHint)),
                const SizedBox(height: 4),
                Container(
                  height: (frac * 80).clamp(4.0, 80.0),
                  decoration: BoxDecoration(
                      color: e.value > 0
                          ? barColor : AppColors.cardBorder,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4))),
                ),
              ]),
            ));
          }).toList(),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppColors.divider),
        const SizedBox(height: 8),
        Row(
          children: data.keys.map((k) => Expanded(
            child: Text(k.split(' ').first, // Just Mon/Tue/etc
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10,
                    color: AppColors.textHint)),
          )).toList(),
        ),
      ]),
    );
  }
}

// ── Horizontal Bar Chart (status breakdown / routes) ──────────────────
class _HorizontalBarChart extends StatelessWidget {
  final Map<String, int> data;
  final Color Function(String) colorFn;
  final int total;
  final String emptyMsg;
  const _HorizontalBarChart({required this.data, required this.colorFn,
    required this.total, required this.emptyMsg});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder)),
        child: Center(child: Text(emptyMsg,
            style: const TextStyle(color: AppColors.textHint, fontSize: 13))),
      );
    }
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [BoxShadow(color: AppColors.shadow,
              blurRadius: 6, offset: const Offset(0, 2))]),
      child: Column(
        children: sorted.map((e) {
          final frac = e.value / total;
          final pct  = (frac * 100).round();
          final col  = colorFn(e.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(e.key,
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary))),
                    Text('${e.value} ($pct%)',
                        style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700, color: col)),
                  ]),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value:            frac,
                      backgroundColor:  col.withOpacity(0.12),
                      valueColor:       AlwaysStoppedAnimation(col),
                      minHeight:        8,
                    ),
                  ),
                ]),
          );
        }).toList(),
      ),
    );
  }
}

// ── Export Card ────────────────────────────────────────────────────────
class _ExportCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;
  const _ExportCard({required this.title, required this.subtitle,
    required this.icon, required this.color, required this.loading,
    required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
            boxShadow: [BoxShadow(color: AppColors.shadow,
                blurRadius: 6, offset: const Offset(0, 2))]),
        child: Row(children: [
          Container(width: 46, height: 46,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment:
          CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text(subtitle, style: const TextStyle(fontSize: 11,
                color: AppColors.textSecondary)),
          ])),
          loading
              ? SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: color))
              : Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(10)),
            child: const Text('Export',
                style: TextStyle(color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

// ── Section Title ──────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary));
}