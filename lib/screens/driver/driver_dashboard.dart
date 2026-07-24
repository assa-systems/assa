import 'package:assa/services/notification_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/auth_service.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/widgets/common/common_widgets.dart';
import 'package:assa/screens/auth/login_screen.dart';
import 'package:assa/screens/user/puzzle_screen.dart';
import 'package:assa/screens/user/lost_found_screen.dart';
import 'package:assa/screens/user/notifications_screen.dart';
import 'package:assa/screens/shared/settings_screen.dart';

// ───────────────────────────────────────────────────────────────────────────
// Global key configuration mapping template tracking hooks
// ───────────────────────────────────────────────────────────────────────────
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void showToast(String msg, String type) {
  final context = navigatorKey.currentContext;
  if (context != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: type == 'success' ? AppColors.success : AppColors.error,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

void showLoading(BuildContext context, String msg) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Text(msg),
        ],
      ),
    ),
  );
}

void hideLoading(BuildContext context) {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Road network matrix (same as in assa_common.h)
// Must match locations order in Esp32Service.allLocations
// Index: 0=AFIT Gates,1=45x1 Hostel,2=Old Girls,3=TETFUND,4=BK,
//        5=Boys Hostel,6=Alfa Hall,7=EED,8=AFIT Mosque,
//        9=New Mechanical,10=Entrepreneurship,11=Hall A
// ───────────────────────────────────────────────────────────────────────────
const List<List<bool>> _ROAD_NETWORK = [
  [false,false,false,false,false,false,false, true, true,false,false,false], // 0 AFIT Gates
  [false,false,false, true, true,false,false,false,false,false,false,false], // 1 45x1 Hostel
  [false,false,false,false,false,false, true,false,false,false, true,false], // 2 Old Girls
  [false, true,false,false,false,false, true,false,false,false,false,false], // 3 TETFUND
  [false, true,false,false,false,false,false,false,false,false,false,false], // 4 BK
  [false,false,false,false,false,false,false,false,false, true, true, true], // 5 Boys Hostel
  [false,false, true, true,false,false,false,false, true,false,false,false], // 6 Alfa Hall
  [ true,false,false,false,false,false,false,false,false,false,false, true], // 7 EED
  [ true,false,false,false,false,false, true,false,false,false,false,false], // 8 AFIT Mosque
  [false,false,false,false,false, true,false,false,false,false,false,false], // 9 New Mechanical
  [false,false, true,false,false, true,false,false,false,false,false,false], //10 Entrepreneurship
  [false,false,false,false,false, true,false, true,false,false,false,false], //11 Hall A
];

bool _areDirectlyConnected(String pickup, String dest) {
  final locs = Esp32Service.allLocations;
  final a = locs.indexOf(pickup);
  final b = locs.indexOf(dest);
  if (a == -1 || b == -1) return false;
  if (a == b) return true;
  return _ROAD_NETWORK[a][b];
}

bool _canReach(String from, String to) {
  if (from == to) return true;
  final locs = Esp32Service.allLocations;
  final start = locs.indexOf(from);
  final end = locs.indexOf(to);
  if (start == -1 || end == -1) return false;
  List<bool> visited = List.filled(locs.length, false);
  List<int> queue = [];
  queue.add(start);
  visited[start] = true;
  while (queue.isNotEmpty) {
    int cur = queue.removeAt(0);
    for (int nxt = 0; nxt < locs.length; nxt++) {
      if (!visited[nxt] && _ROAD_NETWORK[cur][nxt]) {
        if (nxt == end) return true;
        visited[nxt] = true;
        queue.add(nxt);
      }
    }
  }
  return false;
}

// ───────────────────────────────────────────────────────────────────────────
// Grouping logic (client-side)
// Groups requests that have same destination AND
// pickups are directly connected OR reachable via road network.
// Returns a map: groupKey -> list of requests, sorted by distance to destination.
// ───────────────────────────────────────────────────────────────────────────
Map<String, List<Map<String, dynamic>>> _groupPendingRequests(List<Map<String, dynamic>> requests) {
  final Map<String, List<Map<String, dynamic>>> groups = {};
  for (final req in requests) {
    final dest = req['destination'] ?? '';
    final pickup = req['pickupLocation'] ?? '';
    bool added = false;
    for (final key in groups.keys) {
      final groupDest = key.split('_')[1];
      if (groupDest != dest) continue;
      if (_canReach(pickup, groupDest)) {
        groups[key]!.add(req);
        added = true;
        break;
      }
    }
    if (!added) {
      final groupKey = '${pickup}_$dest';
      groups[groupKey] = [req];
    }
  }
  final locs = Esp32Service.allLocations;
  for (final key in groups.keys) {
    final dest = key.split('_')[1];
    final destIndex = locs.indexOf(dest);
    groups[key]!.sort((a, b) {
      final aIndex = locs.indexOf(a['pickupLocation'] ?? '');
      final bIndex = locs.indexOf(b['pickupLocation'] ?? '');
      final aDist = (destIndex - aIndex).abs();
      final bDist = (destIndex - bIndex).abs();
      return aDist.compareTo(bDist);
    });
  }
  return groups;
}

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});
  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final _auth = AuthService();
  Map<String, dynamic>? _driverData;
  bool _isLoading = true;
  int _unreadNotifs = 0;
  String _statusFilter = 'Active';
  List<Map<String, dynamic>> _allPending = [];
  Map<String, List<Map<String, dynamic>>> _groups = {};
  bool _isShuttleOnline = false;

  StreamSubscription<QuerySnapshot>? _requestSub;
  // FIX: Changed from QuerySnapshot to DocumentSnapshot
  StreamSubscription<DocumentSnapshot>? _shuttleStatusSub;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
    _listenToRequests();
    _listenToShuttleStatus();
  }

  @override
  void dispose() {
    _requestSub?.cancel();
    _shuttleStatusSub?.cancel();
    super.dispose();
  }

  void _listenToRequests() {
    _requestSub = FirebaseFirestore.instance
        .collection('ride_requests')
        .where('status', isEqualTo: 0)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final requests = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      setState(() {
        _allPending = requests;
        _groups = _groupPendingRequests(requests);
      });
      if (requests.isNotEmpty) HapticFeedback.heavyImpact();
    }, onError: (e) => debugPrint('Request stream error: $e'));
  }

  // ─── NEW: Listen to shuttle status for this driver's shuttle ──────
  void _listenToShuttleStatus() {
    final shuttleId = _driverData?['shuttleId'] ?? '';
    if (shuttleId.isEmpty || shuttleId == '---') return;

    _shuttleStatusSub = FirebaseFirestore.instance
        .collection('shuttle_status')
        .doc(shuttleId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (snap.exists) {
        final data = snap.data()!;
        final isOnline = data['isOnline'] as bool? ?? false;
        final lastSeen = data['lastSeen'] as Timestamp?;
        // Consider online if seen within last 60 seconds
        final seenRecently = lastSeen != null &&
            DateTime.now().difference(lastSeen.toDate()).inSeconds < 60;
        setState(() {
          _isShuttleOnline = isOnline && seenRecently;
        });
      } else {
        // No status document yet - assume offline
        setState(() {
          _isShuttleOnline = false;
        });
      }
    }, onError: (e) => debugPrint('Shuttle status stream error: $e'));
  }

  Future<void> _loadDriverData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted) setState(() {
        _driverData = doc.data();
        _isLoading = false;
      });
      _listenToNotifications(uid);
      _listenToShuttleStatus();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
    await _refreshPendingRequests();
  }

  Future<void> _refreshPendingRequests() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ride_requests')
          .where('status', isEqualTo: 0)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      final requests = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      setState(() {
        _allPending = requests;
        _groups = _groupPendingRequests(requests);
      });
    } catch (e) {
      debugPrint('Manual pending refresh error: $e');
    }
  }

  void _listenToNotifications(String uid) {
    FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((s) {
      if (mounted) setState(() => _unreadNotifs = s.docs.length);
    });
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  // ════════════════════════════════════════════════════════════════
  // Accept group with full error handling and UI refresh
  // ════════════════════════════════════════════════════════════════
  Future<void> _acceptGroup(List<Map<String, dynamic>> group, String groupKey) async {
    final first = group.first;
    final pickup = first['pickupLocation'];
    final dest = first['destination'];
    final totalPax = group.fold<int>(0, (sum, r) => sum + ((r['passengerCount'] as int?) ?? 1));
    final pickupIds = group.map((r) => r['pickupId'] as String? ?? '???').join(', ');

    final shuttleId = _driverData?['shuttleId'] ?? '0';
    if (shuttleId == '0' || shuttleId == '---' || shuttleId.isEmpty) {
      showToast('Please set your Shuttle ID in settings first.', 'error');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept Group Request'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$totalPax passenger${totalPax > 1 ? 's' : ''} · $pickup → $dest'),
          const SizedBox(height: 8),
          Text('Pickup IDs: $pickupIds', style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accept All')),
        ],
      ),
    );
    if (confirmed != true) return;

    if (mounted) showLoading(context, 'Accepting group...');
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final driverName = _driverData?['name'] ?? 'Driver';

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final req in group) {
        final rid = req['id'];
        batch.update(FirebaseFirestore.instance.collection('ride_requests').doc(rid), {
          'status': 1,
          'statusName': 'Assigned',
          'driverId': uid,
          'driverName': driverName,
          'shuttleIdFeedback': shuttleId,
          'assignedAt': FieldValue.serverTimestamp(),
        });
        final userId = req['userId'];
        if (userId != null && userId.isNotEmpty) {
          final notifRef = FirebaseFirestore.instance.collection('notifications').doc();
          batch.set(notifRef, {
            'userId': userId,
            'title': '🚌 Driver Accepted!',
            'body': 'Driver $driverName (Shuttle $shuttleId) accepted your request: $pickup → $dest',
            'type': 'ride_assigned',
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();

      for (final req in group) {
        final userId = req['userId'];
        if (userId == null) continue;
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
          final fcmToken = userDoc.data()?['fcmToken'] as String?;
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await NotificationService.instance.sendPushNotification(
              token: fcmToken,
              title: '🚌 Driver Accepted!',
              body: 'Driver $driverName (Shuttle $shuttleId) is coming: $pickup → $dest',
              data: {'type': 'ride_assigned', 'userId': userId},
            );
          }
        } catch (_) {}
      }

      if (mounted) {
        hideLoading(context);
        showToast('Accepted ${group.length} passenger${group.length > 1 ? 's' : ''}!', 'success');
        await _loadDriverData();
      }
    } catch (e) {
      if (mounted) {
        hideLoading(context);
        showToast('Failed to accept: $e', 'error');
      }
      debugPrint('Accept error: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════
  // Reject group with error handling and UI refresh
  // ════════════════════════════════════════════════════════════════
  Future<void> _rejectGroup(List<Map<String, dynamic>> group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Group?'),
        content: const Text('This will reject all passengers in this group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject All', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (mounted) showLoading(context, 'Rejecting...');

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final req in group) {
        final rid = req['id'];
        batch.update(FirebaseFirestore.instance.collection('ride_requests').doc(rid), {
          'status': 4,
          'statusName': 'Rejected',
        });
      }
      await batch.commit();
      if (mounted) {
        hideLoading(context);
        showToast('Rejected ${group.length} passenger${group.length > 1 ? 's' : ''}', 'error');
        await _loadDriverData();
      }
    } catch (e) {
      if (mounted) {
        hideLoading(context);
        showToast('Failed to reject: $e', 'error');
      }
      debugPrint('Reject error: $e');
    }
  }

  Future<void> _sendArrivalAlert(String shuttleId) async {
    if (shuttleId.isEmpty || shuttleId == '---') {
      showToast('No shuttle ID assigned', 'error');
      return;
    }
    try {
      final shuttleInt = int.tryParse(shuttleId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final q = await FirebaseFirestore.instance
          .collection('ride_requests')
          .where('shuttle_id', isEqualTo: shuttleInt)
          .where('status', whereIn: [0, 1])
          .get();
      if (q.docs.isEmpty) {
        showToast('No active passengers', 'error');
        return;
      }
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in q.docs) {
        final userId = doc.data()['userId'] as String? ?? '';
        if (userId.isEmpty) continue;
        batch.update(doc.reference, {'status': 2, 'statusName': 'Shuttle Arriving'});
        final ref = FirebaseFirestore.instance.collection('notifications').doc();
        batch.set(ref, {
          'userId': userId,
          'title': '🟢 Shuttle Arriving!',
          'body': 'Shuttle $shuttleId is on its way. Be ready at your pickup!',
          'type': 'arrival',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      showToast('Alert sent to ${q.docs.length} passenger(s)!', 'success');
    } catch (_) {
      showToast('Failed to send alert', 'error');
    }
  }

  Future<void> _updatePassengerStatus(String requestId, int newStatus, String userId) async {
    final statusName = Esp32Service.getStatusName(newStatus);
    try {
      await FirebaseFirestore.instance.collection('ride_requests').doc(requestId).update({
        'status': newStatus,
        'statusName': statusName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final msgs = {
        1: '🚌 Shuttle Assigned — your shuttle is confirmed.',
        3: '✅ You\'ve been picked up! Have a safe ride.',
        4: '🏁 Ride Completed — thank you for using ASSA!',
        5: '❌ Your ride has been cancelled.',
      };
      if (msgs.containsKey(newStatus)) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': userId,
          'title': statusName,
          'body': msgs[newStatus],
          'type': 'ride_status',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
          final fcmToken = userDoc.data()?['fcmToken'] as String?;
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await NotificationService.instance.sendPushNotification(
              token: fcmToken,
              title: statusName,
              body: msgs[newStatus]!,
              data: {'type': 'ride_status', 'userId': userId},
            );
          }
        } catch (_) {}
      }
      showToast('Status → $statusName', 'success');
      await _loadDriverData();
    } catch (_) {
      showToast('Failed to update status', 'error');
    }
  }

  // ─── NEW: Build Shuttle Status Card ──────────────────────────────────
  Widget _buildShuttleStatusCard() {
    final shuttleId = _driverData?['shuttleId'] ?? '---';
    final isOnline = _isShuttleOnline;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isOnline ? AppColors.success.withOpacity(0.3) : AppColors.error.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOnline ? AppColors.success.withOpacity(0.12) : AppColors.error.withOpacity(0.12),
          ),
          child: Icon(
            Icons.directions_bus_rounded,
            color: isOnline ? AppColors.success : AppColors.error,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Shuttle $shuttleId', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(
            isOnline ? '🟢 Online - Ready to accept rides' : '🔴 Offline - Check shuttle unit',
            style: TextStyle(fontSize: 12, color: isOnline ? AppColors.success : AppColors.error),
          ),
        ])),
        if (isOnline)
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
        else
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.driverColor)));
    }
    final name = _driverData?['name'] ?? 'Driver';
    final shuttleId = _driverData?['shuttleId'] ?? '---';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDriverData,
          color: AppColors.driverColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(children: [
              _buildHeader(name, shuttleId),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _buildShuttleStatusCard(),
                  if (_groups.isNotEmpty) ...[
                    const Text('Pending Ride Groups', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ..._groups.entries.map((entry) => _buildGroupCard(entry.key, entry.value)),
                    const SizedBox(height: 16),
                  ],
                  _buildQuickActions(),
                  const SizedBox(height: 20),
                  _buildPassengersSection(uid, shuttleId),
                  const SizedBox(height: 100),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(String groupKey, List<Map<String, dynamic>> group) {
    final first = group.first;
    final pickup = first['pickupLocation'];
    final dest = first['destination'];
    final totalPax = group.fold<int>(0, (sum, r) => sum + ((r['passengerCount'] as int?) ?? 1));
    final pickupIds = group.map((r) => r['pickupId'] as String? ?? '???').join(', ');
    final requestTypes = group.map((r) => r['requestType'] as String? ?? 'online').toSet();
    final hasOnline = requestTypes.contains('online');
    final hasOffline = requestTypes.contains('offline');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.radio_button_checked, size: 14, color: AppColors.success),
          const SizedBox(width: 6),
          Expanded(child: Text(pickup, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.location_on, size: 14, color: AppColors.error),
          const SizedBox(width: 6),
          Expanded(child: Text(dest, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4,
          children: pickupIds.split(',').map((pid) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(pid.trim(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          )).toList(),
        ),
        const SizedBox(height: 6),
        Row(children: [
          if (hasOnline) _typeChip('Online', AppColors.success),
          if (hasOffline) const SizedBox(width: 6),
          if (hasOffline) _typeChip('Offline', AppColors.warning),
          const Spacer(),
          Text('$totalPax pax', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _rejectGroup(group),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
              child: const Text('Reject', style: TextStyle(color: AppColors.error)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _acceptGroup(group, groupKey),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              child: const Text('Accept', style: TextStyle(color: Colors.white)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _typeChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildHeader(String name, String shuttleId) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1976D2)]),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.2)),
            child: Center(child: Text(Helpers.getInitials(name), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Helpers.getGreeting(), style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13)),
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ])),
          Stack(children: [
            IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                icon: const Icon(Icons.notifications_rounded, color: Colors.white, size: 26)),
            if (_unreadNotifs > 0)
              Positioned(top: 8, right: 8,
                  child: Container(width: 16, height: 16, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Center(child: Text('$_unreadNotifs', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))))),
          ]),
          IconButton(onPressed: _showSettingsSheet, icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 26)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text('Shuttle: $shuttleId', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _sendArrivalAlert(shuttleId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.notifications_active_rounded, color: Color(0xFF0D47A1), size: 16),
                SizedBox(width: 6),
                Text('Alert All', style: TextStyle(color: Color(0xFF0D47A1), fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildQuickActions() {
    return Row(children: [
      Expanded(child: _ActionCard(
        icon: Icons.extension_rounded, label: 'Weekly Puzzle',
        subtitle: 'Slide tiles & earn pts', color: const Color(0xFF6A1B9A),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PuzzleScreen())),
      )),
      const SizedBox(width: 12),
      Expanded(child: _ActionCard(
        icon: Icons.search_rounded, label: 'Lost & Found',
        subtitle: 'Report or find items', color: const Color(0xFF00695C),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserLostFoundScreen())),
      )),
    ]);
  }

  Widget _buildPassengersSection(String uid, String shuttleId) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('My Passengers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
        ...['Active', 'All', 'Done'].map((label) => GestureDetector(
          onTap: () => setState(() => _statusFilter = label),
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _statusFilter == label ? AppColors.driverColor : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _statusFilter == label ? AppColors.driverColor : AppColors.inputBorder),
            ),
            child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusFilter == label ? Colors.white : AppColors.textSecondary)),
          ),
        )),
      ]),
      const SizedBox(height: 12),
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('ride_requests')
            .where('driverId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.driverColor));
          }
          var docs = snapshot.data?.docs ?? [];
          docs.sort((a, b) {
            final at = (a.data() as Map)['timestamp'];
            final bt = (b.data() as Map)['timestamp'];
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return (bt as Timestamp).compareTo(at as Timestamp);
          });
          if (_statusFilter == 'Active') {
            docs = docs.where((d) {
              final s = (d.data() as Map)['status'] as int? ?? 0;
              return s >= 1 && s <= 3;
            }).toList();
          } else if (_statusFilter == 'Done') {
            docs = docs.where((d) {
              final s = (d.data() as Map)['status'] as int? ?? 0;
              return s == 4 || s == 5;
            }).toList();
          }
          if (docs.isEmpty) {
            return _emptyCard(icon: Icons.people_outline_rounded, title: 'No passengers', subtitle: 'Accepted passengers appear here');
          }
          return Column(children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _PassengerCard(
              requestId: doc.id,
              data: data,
              onUpdateStatus: (newStatus) => _updatePassengerStatus(doc.id, newStatus, data['userId'] ?? ''),
            );
          }).toList());
        },
      ),
    ]);
  }

  Widget _emptyCard({required IconData icon, required String title, required String subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)),
      child: Column(children: [
        Icon(icon, size: 48, color: AppColors.textHint),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textHint), textAlign: TextAlign.center),
      ]),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DriverSettingsSheet(driverData: _driverData, onLogout: _logout),
    );
  }
}

class _PassengerCard extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final void Function(int) onUpdateStatus;
  const _PassengerCard({required this.requestId, required this.data, required this.onUpdateStatus});

  Color _statusColor(int s) {
    switch (s) {
      case 0: return AppColors.textHint;
      case 1: return AppColors.primary;
      case 2: return AppColors.warning;
      case 3: return AppColors.success;
      case 4: return AppColors.success;
      case 5: return AppColors.error;
      default: return AppColors.textHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as int? ?? 0;
    final userName = data['userName'] ?? 'Passenger';
    final pickup = data['pickupLocation'] ?? data['origin'] ?? '—';
    final dest = data['destination'] ?? '—';
    final rideType = data['rideTypeName'] ?? 'Shared';
    final pickupId = data['pickupId'] as String? ?? '';
    final statusName = Esp32Service.getStatusName(status);
    final color = _statusColor(status);

    final List<Map<String, dynamic>> actions = [];
    if (status == 1) actions.add({'label': '✅ Picked Up', 'status': 3, 'color': AppColors.success});
    if (status == 3) actions.add({'label': '🏁 Complete', 'status': 4, 'color': AppColors.primary});
    if (status == 1 || status == 3) actions.add({'label': '❌ Cancel', 'status': 5, 'color': AppColors.error});

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            border: Border(bottom: BorderSide(color: color.withOpacity(0.15))),
          ),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withOpacity(0.12)),
              child: Center(child: Text(Helpers.getInitials(userName), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(userName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              if (pickupId.isNotEmpty) Text('ID: $pickupId', style: const TextStyle(fontSize: 18, color: AppColors.primary, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: data['requestType'] == 'offline' ? const Color(0xFFFFCA28).withOpacity(0.15) : AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text((data['requestType'] ?? 'online').toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: data['requestType'] == 'offline' ? const Color(0xFFE65100) : AppColors.primary)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(statusName.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.radio_button_checked_rounded, size: 14, color: AppColors.success),
              const SizedBox(width: 6),
              Expanded(child: Text(pickup, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_rounded, size: 14, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(child: Text(dest, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: rideType == 'Chartered' ? AppColors.adminColor.withOpacity(0.1) : AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(rideType, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: rideType == 'Chartered' ? AppColors.adminColor : AppColors.primary)),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: actions.map((a) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: a == actions.last ? 0 : 8),
                  child: ElevatedButton(
                    onPressed: () {
                      if (a['status'] == 5) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Cancel ride?'),
                            content: Text('Cancel $userName\'s ride?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No')),
                              TextButton(onPressed: () { Navigator.pop(ctx); onUpdateStatus(a['status'] as int); }, child: const Text('Cancel Ride', style: TextStyle(color: AppColors.error))),
                            ],
                          ),
                        );
                      } else {
                        onUpdateStatus(a['status'] as int);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (a['color'] as Color).withOpacity(0.9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                    ),
                    child: Text(a['label'] as String, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              )).toList()),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.label, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder), boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 22)),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]),
    ),
  );
}

class _DriverSettingsSheet extends StatefulWidget {
  final Map<String, dynamic>? driverData;
  final VoidCallback onLogout;
  const _DriverSettingsSheet({required this.driverData, required this.onLogout});
  @override
  State<_DriverSettingsSheet> createState() => _DriverSettingsSheetState();
}

class _DriverSettingsSheetState extends State<_DriverSettingsSheet> {
  bool _editMode = false;
  late TextEditingController _nameCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.driverData?['name'] ?? '');
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({'name': _nameCtrl.text.trim()});
        if (mounted) {
          setState(() { _editMode = false; _isSaving = false; });
          showToast('Profile updated!', 'success');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.driverData?['name'] ?? 'Driver';
    final email = widget.driverData?['email'] ?? '';
    final shuttleId = widget.driverData?['shuttleId'] ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.driverColor.withOpacity(0.12)), child: Center(child: Text(Helpers.getInitials(name), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.driverColor)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_editMode)
                TextField(controller: _nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Name', isDense: true), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary))
              else
                Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(email, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              if (shuttleId.isNotEmpty) Text('Shuttle: $shuttleId', style: const TextStyle(fontSize: 12, color: AppColors.driverColor, fontWeight: FontWeight.w600)),
            ])),
          ]),
          const SizedBox(height: 16),
          if (_editMode) ...[
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => setState(() => _editMode = false), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: _isSaving ? null : _save, style: ElevatedButton.styleFrom(backgroundColor: AppColors.driverColor), child: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save', style: TextStyle(color: Colors.white)))),
            ]),
          ] else ...[
            const Divider(color: AppColors.divider),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_outline_rounded), title: const Text('Edit Profile'), trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint), onTap: () => setState(() => _editMode = true)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_rounded),
              title: const Text('App Settings'),
              subtitle: const Text('Theme & about ASSA', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.logout_rounded, color: AppColors.error), title: const Text('Logout', style: TextStyle(color: AppColors.error)), trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textHint), onTap: () { Navigator.pop(context); widget.onLogout(); }),
          ],
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}