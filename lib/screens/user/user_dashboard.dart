import 'package:assa/services/connectivity_service.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/services/offline_request_store.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/auth_service.dart';
import 'package:assa/services/notification_service.dart';
import 'package:assa/screens/auth/login_screen.dart';
import 'package:assa/screens/user/my_requests_screen.dart';
import 'package:assa/screens/user/request_screen.dart';
import 'package:assa/screens/user/notifications_screen.dart';
import 'package:assa/screens/user/user_settings_screen.dart';
import 'package:assa/screens/user/report_screen.dart';
import 'package:assa/screens/user/lost_found_screen.dart';
import 'package:assa/screens/user/game_hub_screen.dart';
import 'package:assa/screens/user/tracking_screen.dart';
import 'package:assa/screens/shared/about_screen.dart';
import 'package:assa/widgets/common/ad_overlay.dart';
import 'package:assa/widgets/common/rating_dialog.dart';
import 'package:assa/widgets/common/driver_of_the_week_banner.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});
  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final _auth = AuthService();
  final _connectivity = ConnectivityService();
  bool _isOnline = true;
  bool _isEsp32Reachable = false;
  OfflineRequest? _offlinePending;
  Timer? _offlinePoller;

  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  int _unreadNotifications = 0;
  Map<String, dynamic>? _lostFoundNotif;
  bool _lostFoundBannerDismissed = false;
  int _availableCredits = 0;
  bool _adShown = false;

  // Active ride from Firebase
  StreamSubscription? _activeSub;
  Map<String, dynamic>? _activeRide;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _listenConnectivity();
    _startOfflinePoller();
  }

  void _listenConnectivity() {
    _connectivity.checkConnectivity().then((v) {
      if (mounted) setState(() {
        _isOnline = _connectivity.hasInternet;
        _isEsp32Reachable = _connectivity.isEsp32Reachable;
      });
    });
    _connectivity.connectionStream.listen((online) {
      if (mounted) setState(() {
        _isOnline = _connectivity.hasInternet;
        _isEsp32Reachable = _connectivity.isEsp32Reachable;
      });
    });
  }

  void _startOfflinePoller() {
    _offlinePoller = Timer.periodic(const Duration(seconds: 3), (_) => _pollOfflineStatus());
    _pollOfflineStatus();
  }

  Future<void> _pollOfflineStatus() async {
    try {
      final reqs = await OfflineRequestStore.instance.getAll();
      final pending = reqs.where((r) =>
        r.status == OfflineStatus.pending ||
        r.status == OfflineStatus.accepted ||
        r.status == OfflineStatus.confirmed
      ).toList();
      if (mounted) {
        setState(() {
          _offlinePending = pending.isNotEmpty ? pending.first : null;
        });
      }
      if (_offlinePending != null && _offlinePending!.status == OfflineStatus.pending) {
        final res = await Esp32Service.instance.pollRequestStatus(_offlinePending!.pid);
        final st = res['status'] as String? ?? 'PENDING';
        final sh = res['shuttle'] as String? ?? '';
        if (st == 'ACCEPTED') {
          await OfflineRequestStore.instance.updateStatus(_offlinePending!.pid, OfflineStatus.accepted, shuttleId: sh);
          if (mounted) _pollOfflineStatus();
        } else if (st == 'REJECTED') {
          await OfflineRequestStore.instance.updateStatus(_offlinePending!.pid, OfflineStatus.rejected);
          if (mounted) _pollOfflineStatus();
        }
      }
    } catch (_) {}
  }


  @override
  void dispose() {
    _activeSub?.cancel();
    _offlinePoller?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      Map<String, dynamic>? data = snap.data();
      if (data != null && (data['pickupId'] == null || (data['pickupId'] as String).isEmpty)) {
        final pid = _generatePickupId(uid);
        data = {...data, 'pickupId': pid};
        FirebaseFirestore.instance.collection('users').doc(uid).update({'pickupId': pid}).catchError((_) {});
      }
      if (mounted) {
        setState(() {
          _userData = data;
          _isLoading = false;
        });
      }
      _listenToNotifications(uid);
      _listenToCredits(uid);
      _listenToActiveRide(uid);
      NotificationService.instance.attachRideListener(uid);
      if (!_adShown) {
        _adShown = true;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) showFullScreenAd(context);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _generatePickupId(String uid) {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    final hash = uid.codeUnits.fold(0, (a, b) => a * 31 + b);
    final letter = letters[hash.abs() % letters.length];
    final digits = (hash.abs() % 100).toString().padLeft(2, '0');
    return '$letter$digits';
  }

  void _listenToNotifications(String uid) {
    FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final lostFoundDocs = snap.docs
          .where((d) => (d.data())['type'] == 'lost_found')
          .toList()
        ..sort((a, b) {
          final at = a.data()['createdAt'] as Timestamp?;
          final bt = b.data()['createdAt'] as Timestamp?;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      setState(() {
        _unreadNotifications = snap.docs.length;
        _lostFoundNotif = lostFoundDocs.isNotEmpty
            ? {'id': lostFoundDocs.first.id, ...lostFoundDocs.first.data()}
            : null;
      });
    });
  }

  void _listenToCredits(String uid) {
    FirebaseFirestore.instance
        .collection('ride_credits')
        .where('userId', isEqualTo: uid)
        .where('used', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        final total = snap.docs.fold<int>(0, (s, d) => s + ((d.data())['amount'] as int? ?? 0));
        setState(() => _availableCredits = total);
      }
    });
  }

  void _listenToActiveRide(String uid) {
    _activeSub = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('userId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'accepted', 'confirmed'])
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _activeRide = snap.docs.isNotEmpty
            ? {'id': snap.docs.first.id, ...snap.docs.first.data()}
            : null;
      });
    });
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => UserSettingsScreen(userData: _userData, onLogout: _logout),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          backgroundColor: Color(0xFF0F172A),
          body: Center(child: CircularProgressIndicator(color: Color(0xFF10B981))));
    }
    final name = _userData?['name'] ?? 'User';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadUserData,
          color: const Color(0xFF10B981),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                                _buildHeader(name),
                if (_offlinePending != null) _buildOfflineBookingBanner(),
                if (_activeRide != null && _offlinePending == null) _buildActiveRideBanner(uid),
                if (_availableCredits > 0) _buildCreditsStrip(),
                if (_lostFoundNotif != null && !_lostFoundBannerDismissed)
                  _buildLostFoundBanner(),
                const DriverOfTheWeekBanner(),
                const SizedBox(height: 16),
                _buildQuickActions(),
                const SizedBox(height: 16),
                _buildAdBanner(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String name) {
    final pickupId = (_userData?['pickupId'] as String?) ?? '---';
    final h = DateTime.now().hour;
    final greeting = h < 12 ? 'Good morning,' : h < 18 ? 'Good afternoon,' : 'Good evening,';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
        ),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.15),
                    border: Border.all(color: Colors.white30, width: 1.5)),
                child: Center(
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting,
                        style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Stack(
                children: [
                  IconButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                    icon: const Icon(Icons.notifications_rounded, color: Colors.white, size: 24),
                  ),
                  if (_unreadNotifications > 0)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                        child: Center(child: Text('$_unreadNotifications',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
                      ),
                    ),
                ],
              ),
              IconButton(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 24)),
            ],
          ),
          const SizedBox(height: 16),
          // Connection Mode Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isOnline ? const Color(0xFF10B981) : (_isEsp32Reachable ? const Color(0xFF0EA5E9) : const Color(0xFFF59E0B)),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isOnline ? 'Online • Cloud Active' : (_isEsp32Reachable ? 'ASSA-AP • Offline Active' : 'Offline Mode'),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Pickup ID badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.badge_rounded, color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('YOUR PICKUP ID',
                        style: TextStyle(
                            color: Color(0x99FFFFFF),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                    Text(pickupId,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6)),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: pickupId));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pickup ID copied'), duration: Duration(seconds: 1)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('COPY', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBookingBanner() {
    final r = _offlinePending!;
    final isAccepted = r.status == OfflineStatus.accepted || r.status == OfflineStatus.confirmed;
    final publicShuttle = r.shuttleId.isNotEmpty ? Esp32Service.getPublicShuttleId(r.shuttleId) : '';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRequestsScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_rounded, size: 12, color: Color(0xFF0284C7)),
                      SizedBox(width: 4),
                      Text('ASSA-AP (Offline)', style: TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('PID: ${r.pid}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isAccepted ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAccepted ? 'ACCEPTED' : 'WAITING SHUTTLE',
                    style: TextStyle(
                      color: isAccepted ? const Color(0xFF065F46) : const Color(0xFF92400E),
                      fontSize: 10, fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.circle, color: Color(0xFF10B981), size: 10),
                const SizedBox(width: 6),
                Expanded(child: Text(r.pickupLocation, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey)),
                const Icon(Icons.location_on_rounded, color: Color(0xFFEF4444), size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(r.destination, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis)),
              ],
            ),
            if (publicShuttle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('🚌 Assigned Shuttle: $publicShuttle',
                  style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.w800, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRideBanner(String uid) {
    final r = _activeRide!;
    final status = r['status'] as String? ?? 'pending';
    final pickup = r['pickupLocation'] ?? 'Unknown';
    final dest = r['destination'] ?? 'Unknown';
    final shuttleId = r['shuttleId'] ?? r['shuttleIdFeedback'] ?? '';
    final isPending = status == 'pending';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRequestsScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2563EB).withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: isPending ? const Color(0xFFFEF3C7) : const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    isPending ? '⏳ Searching...' : '✅ ${status.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800,
                      color: isPending ? const Color(0xFF92400E) : const Color(0xFF065F46),
                    ),
                  ),
                ),
                const Spacer(),
                const Text('Active Ride ›', style: TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.circle, color: Color(0xFF10B981), size: 10),
                const SizedBox(width: 8),
                Expanded(child: Text(pickup, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey)),
                const Icon(Icons.location_on_rounded, color: Color(0xFFEF4444), size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(dest, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis)),
              ],
            ),
            if (shuttleId.toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('🚌 Shuttle: $shuttleId',
                  style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w800, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCreditsStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF10B981),
          borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('You have \$$_availableCredits in ride credits!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildLostFoundBanner() {
    return GestureDetector(
      onTap: () {
        setState(() => _lostFoundBannerDismissed = true);
        Navigator.push(context, MaterialPageRoute(builder: (_) => const UserLostFoundScreen()));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Text('🔍', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Lost & Found Alert', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(_lostFoundNotif?['message'] ?? 'Someone reported a lost item',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _lostFoundBannerDismissed = true),
              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _ActionItem('🚌', 'Request Ride', const Color(0xFF2563EB),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RequestScreen()))),
      _ActionItem('🗺️', 'Track Shuttle', const Color(0xFF0EA5E9),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackingScreen()))),
      _ActionItem('📋', 'My Requests', const Color(0xFF7C3AED),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRequestsScreen()))),
      _ActionItem('🔔', 'Notifications', const Color(0xFFF59E0B),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
      _ActionItem('🔍', 'Lost & Found', const Color(0xFF10B981),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserLostFoundScreen()))),
      _ActionItem('🎮', 'Games', const Color(0xFFEF4444),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GameHubScreen()))),
      _ActionItem('📊', 'Reports', const Color(0xFF6366F1),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen()))),
      _ActionItem('ℹ️', 'About ASSA', const Color(0xFF0F172A),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()))),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quick Actions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: actions.map((a) => _buildActionCard(a)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(_ActionItem item) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: item.color.withOpacity(0.12),
                  shape: BoxShape.circle),
              child: Center(child: Text(item.icon, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(height: 6),
            Text(item.label,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildAdBanner() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .where('active', isEqualTo: true)
          .limit(1)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final ad = snap.data!.docs.first.data() as Map<String, dynamic>;
        final imageUrl = ad['imageUrl'] as String? ?? '';
        final link = ad['link'] as String? ?? '';
        if (imageUrl.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 100,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10)]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(imageUrl: imageUrl, width: double.infinity, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

class _ActionItem {
  final String icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _ActionItem(this.icon, this.label, this.color, this.onTap);
}