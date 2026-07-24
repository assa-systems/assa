import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/auth_service.dart';
import 'package:assa/services/firestore_service.dart';
import 'package:assa/widgets/common/common_widgets.dart';
import 'package:assa/screens/auth/login_screen.dart';
import 'package:assa/screens/admin/manage_drivers_screen.dart';
import 'package:assa/screens/admin/manage_locations_screen.dart';
import 'package:assa/screens/admin/manage_bookings_screen.dart';
import 'package:assa/screens/admin/manage_ads_screen.dart';
import 'package:assa/screens/admin/admin_chat_screen.dart';
import 'package:assa/screens/admin/send_notification_screen.dart';
import 'package:assa/screens/admin/data_export_screen.dart';
import 'package:assa/screens/admin/admin_reports_screen.dart';
import 'package:assa/screens/admin/admin_notifications_screen.dart';
import 'package:assa/screens/admin/manage_admins_screen.dart';
import 'package:assa/screens/admin/lost_found_admin_screen.dart';
import 'package:assa/screens/admin/manage_puzzle_screen.dart';
import 'package:assa/screens/admin/manage_game_questions_screen.dart';
import 'package:assa/screens/shared/settings_screen.dart';
import 'package:assa/screens/shared/about_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  Map<String, dynamic>? _adminData;
  bool _isLoading = true;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (mounted) {
        setState(() {
          _adminData = doc.data();
          _isLoading = false;
        });
      }
      _listenToNotifications(uid);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _listenToNotifications(String uid) {
    FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _unreadNotifications = snap.docs.length);
    });
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (r) => false);
    }
  }

  void _navigate(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx2, sc) => _AdminSettingsSheet(
          adminData: _adminData,
          onLogout: _logout,
          onProfileUpdated: _loadData,
          scrollController: sc,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: AppColors.adminColor)));
    }
    final name = _adminData?['name'] ?? 'Admin';
    final pendingDrivers = (_adminData?['pendingDrivers'] ?? 0) as int;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.adminColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(name, pendingDrivers),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pendingDrivers > 0) ...[
                        _buildPendingAlert(pendingDrivers),
                        const SizedBox(height: 16)
                      ],
                      const SizedBox(height: 8),
                      _buildQuickStats(),
                      const SizedBox(height: 20),
                      _buildLivePanels(),
                      const SizedBox(height: 24),
                      const Text('Manage',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      _buildActionsGrid(pendingDrivers),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String name, int pendingDrivers) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.adminColor, AppColors.adminColor.withOpacity(0.8)]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.white.withOpacity(0.2)),
            child: Center(
                child: Text(Helpers.getInitials(name),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Helpers.getGreeting(),
                    style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13)),
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const Text('Administrator',
                    style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12)),
              ],
            ),
          ),
          Stack(
            children: [
              IconButton(
                  onPressed: () => _navigate(const ManageDriversScreen()),
                  icon: const Icon(Icons.person_add_rounded,
                      color: Colors.white, size: 24)),
              if (pendingDrivers > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                        child: Text('$pendingDrivers',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700))),
                  ),
                ),
            ],
          ),
          Stack(
            children: [
              IconButton(
                onPressed: () => _navigate(const AdminNotificationsScreen()),
                icon: const Icon(Icons.notifications_rounded,
                    color: Colors.white, size: 26),
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                        child: Text('$_unreadNotifications',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700))),
                  ),
                ),
            ],
          ),
          IconButton(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded,
                  color: Colors.white, size: 26)),
        ],
      ),
    );
  }

  Widget _buildPendingAlert(int count) {
    return GestureDetector(
      onTap: () => _navigate(const ManageDriversScreen()),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.pendingLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.pendingColor.withOpacity(0.4))),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.pendingColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  '$count driver ${count == 1 ? 'application' : 'applications'} awaiting review',
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.pendingColor,
                      fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.pendingColor),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Live Overview',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatCard(
          label: 'Active Rides',
          icon: Icons.directions_bus_rounded,
          color: AppColors.success,
          stream: FirebaseFirestore.instance
              .collection('ride_requests')
              .where('status', whereIn: [0, 1, 2, 3])
              .snapshots(),
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(
          label: 'Today\'s Rides',
          icon: Icons.today_rounded,
          color: AppColors.primary,
          stream: FirebaseFirestore.instance
              .collection('ride_requests')
              .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
              .snapshots(),
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatCard(
          label: 'Total Drivers',
          icon: Icons.drive_eta_rounded,
          color: AppColors.driverColor,
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'driver')
              .where('status', isEqualTo: 'approved')
              .snapshots(),
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(
          label: 'Open Reports',
          icon: Icons.report_rounded,
          color: AppColors.error,
          stream: FirebaseFirestore.instance
              .collection('reports')
              .where('status', isEqualTo: 'open')
              .snapshots(),
        )),
      ]),
    ]);
  }

  Widget _buildLivePanels() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Recent Reports',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const Spacer(),
            GestureDetector(
              onTap: () => _navigate(const AdminReportsScreen()),
              child: const Text('See all',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.adminColor,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('reports')
              .where('status', isEqualTo: 'open')
              .limit(3)
              .snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder)),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: AppColors.success, size: 20),
                    SizedBox(width: 10),
                    Text('No open reports',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              );
            }
            return Column(
              children: snap.data!.docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return GestureDetector(
                  onTap: () => _navigate(const AdminReportsScreen()),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withOpacity(0.2))),
                    child: Row(
                      children: [
                        Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.1),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.report_rounded,
                                color: AppColors.error, size: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d['reporterName'] ?? 'User',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                              Text(
                                  'Shuttle: ${d['shuttleId'] ?? '-'} · ${d['category'] ?? ''}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6)),
                          child: const Text('Open',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text('Notifications',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const Spacer(),
            GestureDetector(
              onTap: () => _navigate(const AdminNotificationsScreen()),
              child: const Text('See all',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.adminColor,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('notifications')
              .where('userId', isEqualTo: uid)
              .limit(3)
              .snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder)),
                child: const Row(
                  children: [
                    Icon(Icons.notifications_none_rounded,
                        color: AppColors.textHint, size: 20),
                    SizedBox(width: 10),
                    Text("You're all caught up!",
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              );
            }
            return Column(
              children: snap.data!.docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final isRead = d['read'] ?? false;
                return GestureDetector(
                  onTap: () => _navigate(const AdminNotificationsScreen()),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: isRead
                            ? AppColors.surface
                            : AppColors.adminColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isRead
                                ? AppColors.cardBorder
                                : AppColors.adminColor.withOpacity(0.25))),
                    child: Row(
                      children: [
                        Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color: AppColors.adminColor.withOpacity(0.1),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.notifications_rounded,
                                color: AppColors.adminColor, size: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d['title'] ?? '',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight:
                                      isRead ? FontWeight.w500 : FontWeight.w700,
                                      color: AppColors.textPrimary)),
                              Text(d['body'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        if (!isRead)
                          Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: AppColors.adminColor,
                                  shape: BoxShape.circle)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionsGrid(int pendingDrivers) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _AdminActionCard(
          title: 'Manage Drivers',
          subtitle: pendingDrivers > 0 ? '$pendingDrivers pending' : 'Approve & manage',
          icon: Icons.drive_eta_rounded,
          color: AppColors.driverColor,
          badge: pendingDrivers > 0 ? '$pendingDrivers' : null,
          onTap: () => _navigate(const ManageDriversScreen()),
        ),
        _AdminActionCard(
          title: 'Locations',
          subtitle: 'Add & remove stops',
          icon: Icons.location_on_rounded,
          color: AppColors.primary,
          onTap: () => _navigate(const ManageLocationsScreen()),
        ),
        _AdminActionCard(
          title: 'All Bookings',
          subtitle: 'View requests',
          icon: Icons.receipt_long_rounded,
          color: AppColors.accent,
          onTap: () => _navigate(const ManageBookingsScreen()),
        ),
        _AdminActionCard(
          title: 'Manage Admins',
          subtitle: 'Add & remove admins',
          icon: Icons.admin_panel_settings_rounded,
          color: AppColors.adminColor,
          onTap: () => _navigate(const ManageAdminsScreen()),
        ),
        _AdminActionCard(
          title: 'Manage Ads',
          subtitle: 'Upload & control',
          icon: Icons.campaign_rounded,
          color: AppColors.warning,
          onTap: () => _navigate(const ManageAdsScreen()),
        ),
        _AdminActionCard(
          title: 'Private Messages',
          subtitle: 'Chat · Warn · Reward users',
          icon: Icons.chat_rounded,
          color: const Color(0xFF7B1FA2),
          onTap: () => _navigate(const AdminChatScreen()),
        ),
        _AdminActionCard(
          title: 'Send Notification',
          subtitle: 'Broadcast message',
          icon: Icons.notifications_rounded,
          color: AppColors.success,
          onTap: () => _navigate(const SendNotificationScreen()),
        ),
        _AdminActionCard(
          title: 'Reports',
          subtitle: 'User reports inbox',
          icon: Icons.report_rounded,
          color: AppColors.error,
          onTap: () => _navigate(const AdminReportsScreen()),
        ),
        _AdminActionCard(
          title: 'Lost & Found',
          subtitle: 'Review claims & fines',
          icon: Icons.volunteer_activism_rounded,
          color: const Color(0xFF00897B),
          onTap: () => _navigate(const AdminLostFoundScreen()),
        ),
        _AdminActionCard(
          title: 'Manage Puzzle',
          subtitle: 'Upload images · Leaderboard',
          icon: Icons.extension_rounded,
          color: const Color(0xFF6A1B9A),
          onTap: () => _navigate(const ManagePuzzleScreen()),
        ),
        _AdminActionCard(
          title: 'Export Data',
          subtitle: 'Download & analyse',
          icon: Icons.analytics_rounded,
          color: AppColors.textSecondary,
          onTap: () => _navigate(const DataExportScreen()),
        ),
        _AdminActionCard(
          title: 'About ASSA',
          subtitle: 'Meet team & project info',
          icon: Icons.info_outline_rounded,
          color: const Color(0xFF1565C0),
          onTap: () => _navigate(const AboutScreen()),
        ),
      ],
    );
  }
}

// ============================================================================
// ADMIN ACTION CARD
// ============================================================================
class _AdminActionCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _AdminActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Color.fromARGB(
      255,
      (color.red * 0.65).round().clamp(0, 255),
      (color.green * 0.65).round().clamp(0, 255),
      (color.blue * 0.65).round().clamp(0, 255),
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.28),
                blurRadius: 12,
                offset: const Offset(0, 5))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, dark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Positioned(
                right: -16,
                top: -16,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.09)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Icon(icon, color: Colors.white, size: 22),
                        ),
                        if (badge != null) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.4)),
                            ),
                            child: Text(badge!,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withOpacity(0.8))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// STAT CARD
// ============================================================================
class _StatCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Stream<QuerySnapshot> stream;
  const _StatCard({required this.label, required this.icon, required this.color, required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (ctx, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              snap.connectionState == ConnectionState.waiting
                  ? SizedBox(width: 20, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                  : Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            ]),
          ]),
        );
      },
    );
  }
}

// ============================================================================
// ADMIN SETTINGS SHEET
// ============================================================================
class _AdminSettingsSheet extends StatefulWidget {
  final Map<String, dynamic>? adminData;
  final VoidCallback onLogout;
  final VoidCallback onProfileUpdated;
  final ScrollController? scrollController;

  const _AdminSettingsSheet({
    required this.adminData,
    required this.onLogout,
    required this.onProfileUpdated,
    this.scrollController,
  });

  @override
  State<_AdminSettingsSheet> createState() => _AdminSettingsSheetState();
}

class _AdminSettingsSheetState extends State<_AdminSettingsSheet> {
  String? _activePanel;
  bool _isSaving = false;
  late TextEditingController _nameCtrl;
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _currentPincodeCtrl = TextEditingController();
  final _newPincodeCtrl = TextEditingController();
  final _confirmPincodeCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();
  final _emailPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.adminData?['name'] ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _currentPincodeCtrl.dispose();
    _newPincodeCtrl.dispose();
    _confirmPincodeCtrl.dispose();
    _newEmailCtrl.dispose();
    _emailPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'name': _nameCtrl.text.trim()});
        widget.onProfileUpdated();
        if (mounted) {
          setState(() {
            _isSaving = false;
            _activePanel = null;
          });
          Helpers.showSuccessSnackBar(context, 'Name updated!');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _changePassword() async {
    if (_currentPassCtrl.text.isEmpty) {
      Helpers.showErrorSnackBar(context, 'Enter your current password.');
      return;
    }
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      Helpers.showErrorSnackBar(context, 'Passwords do not match.');
      return;
    }
    if (_newPassCtrl.text.length < 6) {
      Helpers.showErrorSnackBar(
          context, 'Password must be at least 6 characters.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPassCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_newPassCtrl.text);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _activePanel = null;
        });
        _currentPassCtrl.clear();
        _newPassCtrl.clear();
        _confirmPassCtrl.clear();
        Helpers.showSuccessSnackBar(context, 'Password changed successfully!');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          Helpers.showErrorSnackBar(context, 'Current password is incorrect.');
        } else if (e.code == 'requires-recent-login') {
          Helpers.showErrorSnackBar(context,
              'Session expired. Please log out and log back in, then try again.');
        } else if (e.code == 'weak-password') {
          Helpers.showErrorSnackBar(
              context, 'New password is too weak. Use at least 6 characters.');
        } else {
          Helpers.showErrorSnackBar(
              context, e.message ?? 'Failed to change password.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        Helpers.showErrorSnackBar(context, 'Failed to change password. Try again.');
      }
    }
  }

  Future<void> _changePasscode() async {
    if (_newPincodeCtrl.text.length != 4 ||
        _confirmPincodeCtrl.text.length != 4) {
      Helpers.showErrorSnackBar(context, 'Passcode must be exactly 4 digits.');
      return;
    }
    if (_newPincodeCtrl.text != _confirmPincodeCtrl.text) {
      Helpers.showErrorSnackBar(context, 'Passcodes do not match.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final authService = AuthService();
        final valid = await authService.verifyAdminPasscode(
            uid: uid, passcode: _currentPincodeCtrl.text);
        if (!valid) {
          if (mounted) {
            setState(() => _isSaving = false);
            Helpers.showErrorSnackBar(context, 'Current passcode is incorrect.');
          }
          return;
        }
        await authService.setAdminPasscode(
            uid: uid, passcode: _newPincodeCtrl.text);
        if (mounted) {
          setState(() {
            _isSaving = false;
            _activePanel = null;
          });
          _currentPincodeCtrl.clear();
          _newPincodeCtrl.clear();
          _confirmPincodeCtrl.clear();
          Helpers.showSuccessSnackBar(context, 'Passcode updated!');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        Helpers.showErrorSnackBar(
            context, 'Failed to update passcode. Try again.');
      }
    }
  }

  Future<void> _changeEmail() async {
    final newEmail = _newEmailCtrl.text.trim();
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      Helpers.showErrorSnackBar(context, 'Please enter a valid email.');
      return;
    }
    if (_emailPassCtrl.text.isEmpty) {
      Helpers.showErrorSnackBar(context, 'Enter your current password.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: _emailPassCtrl.text);
      await user.reauthenticateWithCredential(cred);
      await user.verifyBeforeUpdateEmail(newEmail);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'email': newEmail});
      if (mounted) {
        setState(() {
          _isSaving = false;
          _activePanel = null;
        });
        _newEmailCtrl.clear();
        _emailPassCtrl.clear();
        Helpers.showSuccessSnackBar(context,
            'Verification link sent to $newEmail. Check your inbox.');
        widget.onProfileUpdated();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          Helpers.showErrorSnackBar(context, 'Current password is incorrect.');
        } else if (e.code == 'email-already-in-use') {
          Helpers.showErrorSnackBar(context, 'This email is already in use.');
        } else if (e.code == 'requires-recent-login') {
          Helpers.showErrorSnackBar(context,
              'Session expired. Please log out and log back in, then try again.');
        } else if (e.code == 'invalid-email') {
          Helpers.showErrorSnackBar(context, 'Invalid email address.');
        } else {
          Helpers.showErrorSnackBar(
              context, e.message ?? 'Failed to update email.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        Helpers.showErrorSnackBar(context, 'Failed to update email. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.adminData?['name'] ?? 'Admin';
    final email = widget.adminData?['email'] ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.adminColor.withOpacity(0.12)),
                  child: Center(
                      child: Text(Helpers.getInitials(name),
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.adminColor))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      Text(email,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const Text('Administrator',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.adminColor,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.divider),
            const SizedBox(height: 8),
            if (_activePanel == 'profile') ...[
              _SubPanelHeader('Edit Name',
                  onClose: () => setState(() => _activePanel = null)),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Full Name',
                hint: 'Enter your name',
                controller: _nameCtrl,
                prefixIcon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 16),
              _ActionButtons(
                onCancel: () => setState(() => _activePanel = null),
                onSave: _saveName,
                isLoading: _isSaving,
              ),
            ] else if (_activePanel == 'password') ...[
              _SubPanelHeader('Change Password',
                  onClose: () => setState(() => _activePanel = null)),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Current Password',
                hint: '••••••••',
                controller: _currentPassCtrl,
                isPassword: true,
                prefixIcon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: 10),
              CustomTextField(
                label: 'New Password',
                hint: '••••••••',
                controller: _newPassCtrl,
                isPassword: true,
                prefixIcon: Icons.lock_rounded,
              ),
              const SizedBox(height: 10),
              CustomTextField(
                label: 'Confirm New Password',
                hint: '••••••••',
                controller: _confirmPassCtrl,
                isPassword: true,
                prefixIcon: Icons.lock_rounded,
              ),
              const SizedBox(height: 16),
              _ActionButtons(
                onCancel: () => setState(() => _activePanel = null),
                onSave: _changePassword,
                isLoading: _isSaving,
                saveLabel: 'Change Password',
              ),
            ] else if (_activePanel == 'passcode') ...[
              _SubPanelHeader('Reset Passcode',
                  onClose: () => setState(() => _activePanel = null)),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Current 4-digit Passcode',
                hint: '••••',
                controller: _currentPincodeCtrl,
                isPassword: true,
                prefixIcon: Icons.pin_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              CustomTextField(
                label: 'New Passcode',
                hint: '••••',
                controller: _newPincodeCtrl,
                isPassword: true,
                prefixIcon: Icons.pin_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              CustomTextField(
                label: 'Confirm New Passcode',
                hint: '••••',
                controller: _confirmPincodeCtrl,
                isPassword: true,
                prefixIcon: Icons.pin_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _ActionButtons(
                onCancel: () => setState(() => _activePanel = null),
                onSave: _changePasscode,
                isLoading: _isSaving,
                saveLabel: 'Update Passcode',
              ),
            ] else if (_activePanel == 'email') ...[
              _SubPanelHeader('Change Email',
                  onClose: () => setState(() => _activePanel = null)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3))),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.warning, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            'A verification link will be sent to your new email.',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textSecondary))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'New Email Address',
                hint: 'Enter new email',
                controller: _newEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
              ),
              const SizedBox(height: 10),
              CustomTextField(
                label: 'Current Password (to confirm)',
                hint: '••••••••',
                controller: _emailPassCtrl,
                isPassword: true,
                prefixIcon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: 16),
              _ActionButtons(
                onCancel: () => setState(() => _activePanel = null),
                onSave: _changeEmail,
                isLoading: _isSaving,
                saveLabel: 'Update Email',
              ),
            ] else ...[
              _SettingTile(
                icon: Icons.person_outline_rounded,
                label: 'Edit Profile',
                subtitle: 'Change your display name',
                onTap: () => setState(() => _activePanel = 'profile'),
              ),
              _SettingTile(
                icon: Icons.lock_outline_rounded,
                label: 'Change Password',
                subtitle: 'Update your login password',
                onTap: () => setState(() => _activePanel = 'password'),
              ),
              _SettingTile(
                icon: Icons.pin_rounded,
                label: 'Reset Passcode',
                subtitle: 'Change your 4-digit admin pin',
                onTap: () => setState(() => _activePanel = 'passcode'),
              ),
              _SettingTile(
                icon: Icons.email_outlined,
                label: 'Change Email',
                subtitle: 'Update your email address',
                onTap: () => setState(() => _activePanel = 'email'),
              ),
              _SettingTile(
                icon: Icons.tune_rounded,
                label: 'App Settings',
                subtitle: 'Theme & about ASSA',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()));
                },
              ),
              _SettingTile(
                icon: Icons.logout_rounded,
                label: 'Logout',
                subtitle: 'Sign out of admin account',
                color: AppColors.error,
                onTap: () {
                  Navigator.pop(context);
                  widget.onLogout();
                },
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SubPanelHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  const _SubPanelHeader(this.title, {required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 18)),
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final bool isLoading;
  final String saveLabel;
  const _ActionButtons({
    required this.onCancel,
    required this.onSave,
    required this.isLoading,
    this.saveLabel = 'Save',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: OutlinedButton(onPressed: onCancel, child: const Text('Cancel'))),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: isLoading ? null : onSave,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.adminColor),
            child: isLoading
                ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : Text(saveLabel, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color? color;
  final VoidCallback onTap;
  const _SettingTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: c, size: 18)),
      title: Text(label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}
