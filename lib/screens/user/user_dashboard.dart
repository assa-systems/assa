import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:assa/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/auth_service.dart';
import 'package:assa/services/connectivity_service.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/widgets/common/common_widgets.dart';
import 'package:assa/screens/auth/login_screen.dart';
import 'package:assa/screens/user/my_requests_screen.dart';
import 'package:assa/screens/user/request_screen.dart';
import 'package:assa/screens/user/notifications_screen.dart';
import 'package:assa/screens/user/user_settings_screen.dart';
import 'package:assa/screens/user/report_screen.dart';
import 'package:assa/screens/user/lost_found_screen.dart';
import 'package:assa/screens/user/game_hub_screen.dart';
import 'package:assa/widgets/common/ad_overlay.dart';
import 'package:assa/services/offline_request_store.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});
  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final _auth = AuthService();
  final _connectivity = ConnectivityService();
  Map<String, dynamic>? _userData;
  bool _isOnline = true;
  bool _isLoading = true;
  bool _bannerDismissed = false;
  bool _howToBookDismissed = false;
  int _unreadNotifications = 0;
  Map<String, dynamic>? _lostFoundNotif;
  bool _lostFoundBannerDismissed = false;
  int _availableCredits = 0;
  bool _adShown = false;

  // Offline pending request
  OfflineRequest? _offlinePending;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _listenToConnectivity();
    _startOfflinePoller();
  }

  void _startOfflinePoller() {
    Future.delayed(Duration.zero, _pollOfflineLoop);
  }

  Future<void> _pollOfflineLoop() async {
    while (mounted) {
      await _refreshOfflinePending();
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // Public method to force a refresh (can be called from outside)
  Future<void> _refreshOfflinePending() async {
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

    // ═══════════════════════════════════════════════════════════════════════
    //  POLL THE AP FOR STATUS UPDATES — save shuttle ID when accepted
    // ═══════════════════════════════════════════════════════════════════════
    if (_offlinePending != null && _offlinePending!.status == OfflineStatus.pending) {
      try {
        final result = await Esp32Service.instance.pollRequestStatus(_offlinePending!.pid);
        final status = result['status'] as String? ?? 'PENDING';
        final shuttleId = result['shuttle'] as String? ?? '';

        if (status == 'ACCEPTED') {
          await OfflineRequestStore.instance.updateStatus(
            _offlinePending!.pid,
            OfflineStatus.accepted,
            shuttleId: shuttleId,
          );
          // Refresh UI to show the shuttle name
          if (mounted) _refreshOfflinePending();
        } else if (status == 'REJECTED') {
          await OfflineRequestStore.instance.updateStatus(
            _offlinePending!.pid,
            OfflineStatus.rejected,
          );
          if (mounted) _refreshOfflinePending();
        } else if (status == 'CANCELLED') {
          await OfflineRequestStore.instance.updateStatus(
            _offlinePending!.pid,
            OfflineStatus.cancelled,
          );
          if (mounted) _refreshOfflinePending();
        }
      } catch (_) {
        // AP unreachable — will retry in 2 seconds
      }
    }
  }

  void _listenToConnectivity() {
    _connectivity.checkConnectivity().then((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _connectivity.connectionStream.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await ref
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        doc = await ref.get(const GetOptions(source: Source.cache));
      }
      Map<String, dynamic>? data = doc.data();
      if (data != null &&
          (data['pickupId'] == null || (data['pickupId'] as String).isEmpty)) {
        final pickupId = _generatePickupId(uid);
        if (_isOnline) {
          try {
            await ref.update({'pickupId': pickupId});
          } catch (_) {}
        }
        data = {...data, 'pickupId': pickupId};
      }
      if (mounted) {
        setState(() {
          _userData = data;
          _isLoading = false;
        });
      }
      _listenToNotifications(uid);
      _listenToCredits(uid);
      NotificationService.instance.attachRideListener(uid);
      if (_isOnline && !_adShown) {
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
      final lostFoundDocs = snap.docs.where((d) =>
      (d.data())['type'] == 'lost_found').toList()
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
        final total = snap.docs.fold<int>(
            0, (sum, d) => sum + ((d.data())['amount'] as int? ?? 0));
        setState(() => _availableCredits = total);
      }
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

  void _navigateToGameHub() async {
    await showFullScreenAd(context);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GameHubScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }
    final name = _userData?['name'] ?? 'User';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            if (!_isOnline) const OfflineBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshOfflinePending,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(name),
                      const SizedBox(height: 16),
                      _buildActiveBookingBanner(uid),
                      if (_availableCredits > 0) ...[
                        const SizedBox(height: 12),
                        _buildCreditsStrip(),
                      ],
                      if (_lostFoundNotif != null && !_lostFoundBannerDismissed) ...[
                        const SizedBox(height: 12),
                        _buildLostFoundBanner(),
                      ],
                      const SizedBox(height: 16),
                      _buildHowToBook(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Quick Actions',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 16),
                            _buildQuickActions(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                      _buildAdBanner(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String name) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)]),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                        style: const TextStyle(
                            color: Color(0xCCFFFFFF), fontSize: 13)),
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Stack(
                children: [
                  IconButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen())),
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
                                    fontSize: 9,
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
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isOnline ? Colors.greenAccent : Colors.orange)),
                const SizedBox(width: 6),
                Text(_isOnline ? 'Online' : 'Offline Mode',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Pickup ID Card (always visible) ──
  Widget _buildPickupIdCard() {
    final pickupId = (_userData?['pickupId'] as String?) ?? '---';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0D47A1).withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.badge_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('YOUR PICKUP ID',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(pickupId,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6)),
                const SizedBox(height: 2),
                const Text(
                    'Show this ID to your driver — or listen for it when the shuttle arrives',
                    style: TextStyle(color: Colors.white60, fontSize: 10, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Active Booking Banner (shows offline pending or online active) ──
  Widget _buildActiveBookingBanner(String uid) {
    // 1. Offline pending request – show offline banner
    if (_offlinePending != null) {
      final r = _offlinePending!;
      final statusName = r.status.label;
      String shuttleId = r.shuttleId;
      if (shuttleId.isNotEmpty) {
        shuttleId = Esp32Service.getPublicShuttleId(shuttleId);
      }
      return GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MyRequestsScreen())),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [
                  AppColors.pendingColor.withOpacity(0.85),
                  AppColors.pendingColor,
                ]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: AppColors.pendingColor.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.wifi_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Offline Ride',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(statusName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${r.pickupLocation} → ${r.destination}',
                        style: const TextStyle(
                            color: Color(0xDDFFFFFF), fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    // Pickup ID — shown prominently here too, matching the
                    // "YOUR PICKUP ID" card above and the boxed Shuttle ID
                    // treatment in the online banner below, so this offline
                    // request is visibly tied to the same PID the driver
                    // will see on the shuttle's LCD.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.confirmation_number_rounded,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text('PID: ${r.pid}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1)),
                        ],
                      ),
                    ),
                    if (shuttleId.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Shuttle: $shuttleId',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Cancel Offline Ride?'),
                      content: const Text('Remove this request?'),
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
                    await OfflineRequestStore.instance.cancel(r.pid);
                    await _refreshOfflinePending();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('Cancel',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Online active booking (Firestore)
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ride_requests')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: [0, 1, 2, 3])
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildPickupIdCard();
        }
        final docs = snapshot.data!.docs;
        docs.sort((a, b) {
          final at = (a.data() as Map)['timestamp'];
          final bt = (b.data() as Map)['timestamp'];
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return (bt as Timestamp).compareTo(at as Timestamp);
        });
        final data = docs.first.data() as Map<String, dynamic>;
        final docId = docs.first.id;
        final statusCode = data['status'] ?? 0;
        final statusName = data['statusName'] ?? 'Pending';
        final origin = data['pickupLocation'] ?? data['origin'] ?? '';
        final dest = data['destination'] ?? '';
        String shuttleId = data['shuttleIdFeedback'] ?? '';
        if (shuttleId.isNotEmpty) {
          shuttleId = Esp32Service.getPublicShuttleId(shuttleId);
        }
        final driverName = data['driverName'] ?? '';

        return GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MyRequestsScreen())),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF1B5E20).withOpacity(0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: icon + status badge + cancel
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.directions_bus_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🚌  Ride Active',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(statusName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Cancel Ride?'),
                            content: const Text(
                                'Are you sure you want to cancel?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('No')),
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Yes, Cancel',
                                      style:
                                      TextStyle(color: AppColors.error))),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await FirebaseFirestore.instance
                              .collection('ride_requests')
                              .doc(docId)
                              .update(
                              {'status': 5, 'statusName': 'Cancelled'});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Ride cancelled.'),
                                    backgroundColor: AppColors.error));
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Text('Cancel',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Route
                Row(
                  children: [
                    const Icon(Icons.radio_button_checked,
                        color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('$origin  →  $dest',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.confirmation_number_rounded,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text('PID: ${(_userData?['pickupId'] as String?) ?? '---'}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1)),
                    ],
                  ),
                ),
                if (shuttleId.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  // Shuttle ID — bold and prominent
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                                Icons.confirmation_number_rounded,
                                color: Colors.white,
                                size: 18),
                            const SizedBox(width: 8),
                            Text('Shuttle ID:  $shuttleId',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5)),
                          ],
                        ),
                        if (driverName.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.person_rounded,
                                  color: Colors.white70, size: 16),
                              const SizedBox(width: 8),
                              Text('Driver: $driverName',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Text('Tap to view full details',
                    style: TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreditsStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF00897B), Color(0xFF00695C)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF00897B).withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.stars_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ride Credits Available',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                Text('$_availableCredits pts',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const UserLostFoundScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('View',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdBanner() {
    if (_bannerDismissed) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data!.docs.cast<DocumentSnapshot>().take(5).toList();
        return Stack(
          children: [
            _AdCarousel(docs: docs),
            Positioned(
              top: 8,
              right: 24,
              child: GestureDetector(
                onTap: () => setState(() => _bannerDismissed = true),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLostFoundBanner() {
    final title = (_lostFoundNotif?['title'] as String?) ?? 'Lost & Found Update';
    final body  = (_lostFoundNotif?['body']  as String?) ?? '';
    final notifId = _lostFoundNotif?['id'] as String?;
    return GestureDetector(
      onTap: () {
        if (notifId != null) {
          FirebaseFirestore.instance
              .collection('notifications').doc(notifId)
              .update({'read': true}).catchError((_) {});
        }
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const UserLostFoundScreen()));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF00897B), Color(0xFF00695C)]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: const Color(0xFF00897B).withOpacity(0.28),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w700)),
                if (body.isNotEmpty)
                  Text(body,
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _lostFoundBannerDismissed = true),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  color: Colors.white.withOpacity(0.8), size: 16),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHowToBook() {
    if (_howToBookDismissed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Tap "Book a Ride" to request a shuttle. '
                  'Use Online mode when connected, or Offline mode via campus hotspot.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _howToBookDismissed = true),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, size: 16, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _ActionCard(
          title: 'Book a Ride',
          subtitle: 'Request a shuttle',
          icon: Icons.airport_shuttle_rounded,
          color: AppColors.primary,
          onTap: () {
            // Navigate to RequestScreen and refresh offline pending on return
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RequestScreen()),
            ).then((_) => _refreshOfflinePending());
          },
        ),
        _ActionCard(
          title: 'My Requests',
          subtitle: 'View history',
          icon: Icons.list_alt_rounded,
          color: AppColors.accent,
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const MyRequestsScreen())),
        ),
        _ActionCard(
          title: 'Game Hub',
          subtitle: 'Play · Puzzle · Quiz · Tap',
          icon: Icons.sports_esports_rounded,
          color: const Color(0xFF6A1B9A),
          onTap: _navigateToGameHub,
        ),
        _ActionCard(
          title: 'Lost & Found',
          subtitle: _availableCredits > 0
              ? '$_availableCredits credits available'
              : 'Earn ride credits',
          icon: Icons.volunteer_activism_rounded,
          color: const Color(0xFF00897B),
          badge: _availableCredits > 0 ? '$_availableCredits pts' : null,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const UserLostFoundScreen())),
        ),
        _ActionCard(
          title: 'Notifications',
          subtitle: _unreadNotifications > 0
              ? '$_unreadNotifications unread'
              : 'All caught up',
          icon: Icons.notifications_active_rounded,
          color: AppColors.warning,
          badge: _unreadNotifications > 0 ? '$_unreadNotifications' : null,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        ),
        _ActionCard(
          title: 'Complaint Panel',
          subtitle: 'Chat with support',
          icon: Icons.support_agent_rounded,
          color: AppColors.error,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => ReportScreen(userData: _userData))),
        ),
      ],
    );
  }
}

// ── _ActionCard ──
class _ActionCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? badge;
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.badge,
  });

  Color get _dark => Color.fromARGB(
    255,
    (color.red * 0.65).round().clamp(0, 255),
    (color.green * 0.65).round().clamp(0, 255),
    (color.blue * 0.65).round().clamp(0, 255),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.28),
                blurRadius: 14,
                offset: const Offset(0, 6)),
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 4,
                offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, _dark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Positioned(
                right: -18,
                top: -18,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.10),
                  ),
                ),
              ),
              Positioned(
                left: -10,
                bottom: -20,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.07),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3), width: 1.5),
                          ),
                          child: Icon(icon, color: Colors.white, size: 26),
                        ),
                        const Spacer(),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
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
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black26, blurRadius: 4)
                                ])),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.white.withOpacity(0.80),
                                height: 1.3)),
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

// ── _AdCarousel and _AdBillboard (unchanged) ──
class _AdCarousel extends StatefulWidget {
  final List<DocumentSnapshot> docs;
  const _AdCarousel({required this.docs});
  @override
  State<_AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<_AdCarousel> {
  late final PageController _ctrl;
  int _page = 0;

  static const _grads = [
    [Color(0xFF1565C0), Color(0xFF1976D2), Color(0xFF42A5F5)],
    [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFFAB47BC)],
    [Color(0xFF004D40), Color(0xFF00695C), Color(0xFF26A69A)],
    [Color(0xFFBF360C), Color(0xFFE64A19), Color(0xFFFF7043)],
    [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF66BB6A)],
  ];
  static const _emojis = ['🚌', '📢', '🎯', '⚡', '🌟'];

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.docs.isNotEmpty) {
        _recordImpression(widget.docs[0].id);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _recordImpression(String adId) {
    FirebaseFirestore.instance
        .collection('ads')
        .doc(adId)
        .update({
      'impressions': FieldValue.increment(1),
      'lastSeen': FieldValue.serverTimestamp(),
    })
        .catchError((_) {});
  }

  void _recordTap(String adId) {
    FirebaseFirestore.instance
        .collection('ads')
        .doc(adId)
        .update({
      'taps': FieldValue.increment(1),
      'lastTap': FieldValue.serverTimestamp(),
    })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: PageView.builder(
              controller: _ctrl,
              onPageChanged: (i) {
                setState(() => _page = i);
                _recordImpression(widget.docs[i].id);
              },
              itemCount: widget.docs.length,
              itemBuilder: (_, i) {
                final doc = widget.docs[i];
                final d = doc.data() as Map<String, dynamic>;
                final grad = _grads[i % _grads.length];
                final emoji = _emojis[i % _emojis.length];
                final imageUrl = d['imageUrl'] ?? '';
                final linkUrl = d['linkUrl'] ?? '';
                final title = d['title'] ?? '';
                final body = d['body'] ?? '';
                return _AdBillboard(
                  adId: doc.id,
                  title: title,
                  body: body,
                  imageUrl: imageUrl,
                  linkUrl: linkUrl,
                  grad: grad,
                  emoji: emoji,
                  onTap: () => _recordTap(doc.id),
                );
              },
            ),
          ),
          if (widget.docs.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.docs.length,
                    (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _page == i ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _page == i
                        ? const Color(0xFF1565C0)
                        : const Color(0xFF1565C0).withOpacity(0.25),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _AdBillboard extends StatelessWidget {
  final String adId;
  final String title, body, imageUrl, linkUrl, emoji;
  final List<Color> grad;
  final VoidCallback onTap;
  const _AdBillboard({
    required this.adId,
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.linkUrl,
    required this.grad,
    required this.emoji,
    required this.onTap,
  });

  Future<void> _openLink() async {
    if (linkUrl.trim().isEmpty) return;
    try {
      String safe = linkUrl.trim();
      if (!safe.startsWith('http://') && !safe.startsWith('https://')) {
        safe = 'https://$safe';
      }
      final uri = Uri.parse(safe);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: linkUrl.isNotEmpty
          ? () {
        onTap();
        _openLink();
      }
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: grad[0].withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              if (imageUrl.isNotEmpty)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: grad,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight)),
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: grad,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight)),
                  ),
                ),
              if (imageUrl.isNotEmpty)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.55),
                          Colors.black.withOpacity(0.15)
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                ),
              if (imageUrl.isEmpty) ...[
                Positioned(
                  right: -30,
                  top: -30,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.06)),
                  ),
                ),
                Positioned(
                  left: -20,
                  bottom: -20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.05)),
                  ),
                ),
              ],
              Positioned(
                top: 10,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white38, width: 1),
                  ),
                  child: const Text('AD',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5)),
                ),
              ),
              if (linkUrl.isNotEmpty)
                Positioned(
                  top: 10,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded,
                            color: Colors.white, size: 10),
                        SizedBox(width: 3),
                        Text('TAP TO OPEN',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 60, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (imageUrl.isEmpty)
                        Row(
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 6),
                            const Text('AFIT SHUTTLE',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2)),
                          ],
                        ),
                      if (imageUrl.isEmpty) const SizedBox(height: 6),
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 8)
                              ]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(body,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                                height: 1.4,
                                shadows: const [
                                  Shadow(color: Colors.black45, blurRadius: 6)
                                ]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}