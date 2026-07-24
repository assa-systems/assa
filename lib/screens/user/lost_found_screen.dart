import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/services/storage_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:assa/widgets/common/common_widgets.dart';
import 'package:assa/widgets/common/ad_overlay.dart';

// ======================================================================
// LOST & FOUND SYSTEM — Full Specification
//
// FIRESTORE COLLECTIONS:
//   lost_found/ {
//     userId, userName, userRole,
//     itemType,        -- 'Lost' or 'Found'
//     category,        -- Phone/Bag/ID Card/Keys/Laptop/Wallet/Other
//     description, locationCode, locationName,
//     imageUrl,        -- (optional, base64 string or direct URL)
//     status,          -- 'Lost' | 'Found' | 'Recovered'
//     is_active: bool,
//     finePaid: bool,  -- set by admin when owner pays fine
//     fineAmount: int, -- admin sets fine based on category/value
//     finderUserId,    -- UID of person who found and posted
//     ownerUserId,     -- UID of person who claims ownership
//     rewardGiven: bool,
//     timestamp, updatedAt
//   }
//
//   ride_credits/ {
//     userId, amount, reason, sourceItemId,
//     used: bool, usedAt, createdAt
//   }
// ======================================================================

class UserLostFoundScreen extends StatefulWidget {
  const UserLostFoundScreen({super.key});
  @override
  State<UserLostFoundScreen> createState() => _LostFoundScreenState();
}

class _LostFoundScreenState extends State<UserLostFoundScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  Map<String, dynamic>? _adData;
  bool _adDismissed = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAd();
  }

  Future<void> _loadAd() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ads')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (mounted && snap.docs.isNotEmpty) {
        setState(() =>
        _adData = {'id': snap.docs.first.id, ...snap.docs.first.data()});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPostSheet(context),
        backgroundColor: const Color(0xFF00897B),
        elevation: 4,
        icon:  const Icon(Icons.post_add_rounded, color: Colors.white, size: 24),
        label: const Text('📋  Post Item', style: TextStyle(color: Colors.white,
            fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.3)),
      ),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          Container(
            color: const Color(0xFF00695C),
            child: TabBar(
              controller: _tab,
              indicatorColor:      Colors.white,
              labelColor:          Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: 'All Active'),
                Tab(text: 'My Posts'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _AllActiveTab(myUid: _myUid),
                _MyPostsTab(myUid: _myUid),
              ],
            ),
          ),
          // Ad banner — natural bottom placement, dismissable
          if (_adData != null && !_adDismissed)
            AdDashboardCard(
              ad:        _adData!,
              onTap:     () {
                final id = _adData!['id'] as String?;
                if (id != null) {
                  FirebaseFirestore.instance.collection('ads').doc(id)
                      .update({'taps': FieldValue.increment(1)})
                      .catchError((_) {});
                }
              },
              onDismiss: () => setState(() => _adDismissed = true),
            ),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF00897B), Color(0xFF00695C)]),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(0), bottomRight: Radius.circular(0)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      child: Row(children: [
        IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white)),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Lost & Found', style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
          Text('Report lost items or post found ones to reunite owners.',
              style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 11)),
        ])),
        const Icon(Icons.volunteer_activism_rounded, color: Colors.white, size: 26),
      ]),
    );
  }

  void _openPostSheet(BuildContext context) {
    showModalBottomSheet(
      context:         context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _PostItemSheet(myUid: _myUid),
    );
  }
}

// ======================================================================
// TAB 1: ALL ACTIVE ITEMS (Lost + Found)
// ======================================================================
class _AllActiveTab extends StatefulWidget {
  final String myUid;
  const _AllActiveTab({required this.myUid});
  @override
  State<_AllActiveTab> createState() => _AllActiveTabState();
}

class _AllActiveTabState extends State<_AllActiveTab> {
  String _filter = 'All'; // All, Lost, Found

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Filter chips
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: ['All', 'Lost', 'Found'].map((f) {
          final sel = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF00897B) : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? const Color(0xFF00897B) : AppColors.inputBorder),
                ),
                child: Text(f, style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : AppColors.textPrimary)),
              ),
            ),
          );
        }).toList()),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('lost_found')
              .where('is_active', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(
                  color: Color(0xFF00897B)));
            }
            var docs = snapshot.data?.docs ?? [];
            if (_filter != 'All') {
              docs = docs.where((d) =>
              (d.data() as Map)['itemType'] == _filter).toList();
            }
            // Sort newest first
            docs.sort((a, b) {
              final at = (a.data() as Map)['timestamp'];
              final bt = (b.data() as Map)['timestamp'];
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;
              return (bt as Timestamp).compareTo(at as Timestamp);
            });
            if (docs.isEmpty) return _emptyState();
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final data  = docs[i].data() as Map<String, dynamic>;
                final docId = docs[i].id;
                return _ItemCard(data: data, docId: docId,
                    myUid: widget.myUid, showClaimButton: true);
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _emptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.search_off_rounded, size: 60, color: AppColors.textHint),
      const SizedBox(height: 12),
      Text(_filter == 'All' ? 'No active items' : 'No $_filter items',
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      const Text('Be the first to post a lost or found item!',
          style: TextStyle(fontSize: 12, color: AppColors.textHint)),
    ]));
  }
}

// ======================================================================
// TAB 2: MY POSTS (includes history, recovered etc.)
// ======================================================================
class _MyPostsTab extends StatelessWidget {
  final String myUid;
  const _MyPostsTab({required this.myUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lost_found')
          .where('userId', isEqualTo: myUid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(
              color: Color(0xFF00897B)));
        }
        final docs = (snapshot.data?.docs ?? [])..sort((a, b) {
          final at = (a.data() as Map)['timestamp'];
          final bt = (b.data() as Map)['timestamp'];
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return (bt as Timestamp).compareTo(at as Timestamp);
        });
        if (docs.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.history_rounded, size: 60, color: AppColors.textHint),
            const SizedBox(height: 12),
            const Text('No posts yet',
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            const Text('Items you post will appear here — even after recovery.',
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
                textAlign: TextAlign.center),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data  = docs[i].data() as Map<String, dynamic>;
            final docId = docs[i].id;
            return _ItemCard(data: data, docId: docId,
                myUid: myUid, showClaimButton: false, isOwner: true);
          },
        );
      },
    );
  }
}

// ======================================================================
// TAB 3: MY RIDE CREDITS
// ======================================================================
class _MyCreditsTab extends StatelessWidget {
  final String myUid;
  const _MyCreditsTab({required this.myUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ride_credits')
          .where('userId', isEqualTo: myUid)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = (snapshot.data?.docs ?? [])..sort((a, b) {
          final at = (a.data() as Map)['createdAt'];
          final bt = (b.data() as Map)['createdAt'];
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return (bt as Timestamp).compareTo(at as Timestamp);
        });

        final unusedDocs = docs.where((d) =>
        (d.data() as Map)['used'] == false).toList();
        final unusedCount = unusedDocs.length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Summary banner ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF00897B), Color(0xFF00695C)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                    color: const Color(0xFF00897B).withOpacity(0.3),
                    blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(children: [
                const Icon(Icons.card_giftcard_rounded,
                    color: Colors.white70, size: 28),
                const SizedBox(height: 6),
                Text(
                  unusedCount == 0
                      ? 'No unused credits'
                      : '$unusedCount Free Ride${unusedCount > 1 ? 's' : ''} Available',
                  style: const TextStyle(color: Colors.white, fontSize: 22,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Earned by finding & returning lost items.\n'
                      'Each credit lets you book one free ride.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
            const SizedBox(height: 16),

            if (docs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Column(children: [
                    Icon(Icons.volunteer_activism_rounded,
                        size: 56, color: AppColors.textHint),
                    SizedBox(height: 12),
                    Text('No credits yet.',
                        style: TextStyle(fontSize: 15,
                            color: AppColors.textSecondary)),
                    SizedBox(height: 6),
                    Text(
                      'Post a found item to help return it\n'
                          'to its owner.',
                      style: TextStyle(fontSize: 12, color: AppColors.textHint),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
              )
            else ...[
              const Text('Your Ride Credits',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              ...docs.map((doc) {
                final d        = doc.data() as Map<String, dynamic>;
                final creditId = doc.id;
                final used     = d['used'] == true;
                final amt      = d['amount'] ?? 0;
                final rideType = d['rideType'] ?? 'Shared';
                final reason   = d['reason'] ?? 'Item returned';
                final ts       = d['createdAt'];
                final date     = ts != null
                    ? Helpers.formatDateTime((ts as Timestamp).toDate()) : '';
                final rtColor  = rideType == 'Chartered'
                    ? AppColors.adminColor : AppColors.primary;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: used
                          ? AppColors.cardBorder
                          : const Color(0xFF00897B).withOpacity(0.3),
                      width: used ? 1 : 1.5,
                    ),
                    boxShadow: used ? [] : [BoxShadow(
                        color: const Color(0xFF00897B).withOpacity(0.08),
                        blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card header
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          decoration: BoxDecoration(
                            color: used
                                ? AppColors.background
                                : const Color(0xFF00897B).withOpacity(0.06),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(13)),
                            border: Border(bottom: BorderSide(
                                color: used
                                    ? AppColors.divider
                                    : const Color(0xFF00897B).withOpacity(0.15))),
                          ),
                          child: Row(children: [
                            Icon(
                              used ? Icons.check_circle_rounded
                                  : Icons.card_giftcard_rounded,
                              color: used
                                  ? AppColors.textHint
                                  : const Color(0xFF00897B),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              used ? 'USED' : 'FREE RIDE AVAILABLE',
                              style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800,
                                color: used
                                    ? AppColors.textHint
                                    : const Color(0xFF00897B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            // Ride type badge
                            if (!used)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: rtColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: rtColor.withOpacity(0.3)),
                                ),
                                child: Text(rideType,
                                    style: TextStyle(
                                        fontSize: 10, fontWeight: FontWeight.w700,
                                        color: rtColor)),
                              ),
                          ]),
                        ),

                        // Card body
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(reason,
                                    style: const TextStyle(fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Text('Value: ₦$amt  •  $date',
                                      style: const TextStyle(fontSize: 11,
                                          color: AppColors.textSecondary)),
                                ]),

                                // Book free ride button — only on unused credits
                                if (!used) ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _openCreditBooking(
                                        context,
                                        creditId: creditId,
                                        rideType: rideType,
                                        amount:   amt,
                                        myUid:    myUid,
                                      ),
                                      icon: const Icon(Icons.directions_bus_rounded,
                                          size: 18, color: Colors.white),
                                      label: Text(
                                        'Book Free $rideType Ride',
                                        style: const TextStyle(color: Colors.white,
                                            fontWeight: FontWeight.w700),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00897B),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ]),
                        ),
                      ]),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  // Opens ride booking sheet pre-filled with the credit's ride type.
  void _openCreditBooking(
      BuildContext context, {
        required String creditId,
        required String rideType,
        required int    amount,
        required String myUid,
      }) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _CreditRideBookingSheet(
        creditId: creditId,
        rideType: rideType,
        amount:   amount,
        myUid:    myUid,
      ),
    );
  }
}

// ======================================================================
// CREDIT RIDE BOOKING SHEET
// ======================================================================
class _CreditRideBookingSheet extends StatefulWidget {
  final String creditId, rideType, myUid;
  final int    amount;
  const _CreditRideBookingSheet({
    required this.creditId,
    required this.rideType,
    required this.myUid,
    required this.amount,
  });
  @override
  State<_CreditRideBookingSheet> createState() =>
      _CreditRideBookingSheetState();
}

class _CreditRideBookingSheetState extends State<_CreditRideBookingSheet> {
  String? _pickup;
  String? _destination;
  bool    _booking = false;
  String  _userName = '';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(widget.myUid).get();
    if (mounted) setState(() => _userName = doc.data()?['name'] ?? 'User');
  }

  Future<void> _confirmBooking() async {
    if (_pickup == null || _destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select pickup and destination.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    if (_pickup == _destination) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pickup and destination cannot be the same.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _booking = true);
    try {
      final onlineUUID = (await FirebaseFirestore.instance
          .collection('users').doc(widget.myUid).get())
          .data()?['onlineUUID'] ?? '';

      // 1. Submit the actual ride request (online booking)
      final id = FirebaseFirestore.instance
          .collection('ride_requests').doc().id;
      await FirebaseFirestore.instance
          .collection('ride_requests').doc(id).set({
        'student_id':       widget.myUid,
        'pickup_code':      _locationCode(_pickup!),
        'destination_code': _locationCode(_destination!),
        'ride_type':        widget.rideType == 'Chartered' ? 1 : 0,
        'status':           0,
        'shuttle_id':       0,
        'timestamp':        FieldValue.serverTimestamp(),
        'bookingId':        id,
        'userId':           widget.myUid,
        'userName':         _userName,
        'onlineUUID':       onlineUUID,
        'pickupLocation':   _pickup,
        'origin':           _pickup,
        'destination':      _destination,
        'rideTypeName':     widget.rideType,
        'statusName':       'Pending',
        'requestType':      'online',
        'isCreditRide':     true,
        'creditId':         widget.creditId,
        'creditAmount':     widget.amount,
        'isSynced':         true,
        'routeId':          '',
        'driverId':         '',
        'seatNumber':       0,
        'shuttleIdFeedback': '',
        'bookedAt':         FieldValue.serverTimestamp(),
      });

      // 2. Mark the credit as used
      await FirebaseFirestore.instance
          .collection('ride_credits').doc(widget.creditId).update({
        'used':          true,
        'usedAt':        FieldValue.serverTimestamp(),
        'usedBookingId': id,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Free ${widget.rideType} ride booked! '
                'Check "My Requests" for status.',
          ),
          backgroundColor: const Color(0xFF00897B),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _booking = false);
    }
  }

  int _locationCode(String name) => Esp32Service.getLocationCode(name);

  List<String> get _allLocations => Esp32Service.allLocations;

  @override
  Widget build(BuildContext context) {
    final rtColor = widget.rideType == 'Chartered'
        ? AppColors.adminColor : AppColors.primary;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),

                // Credit badge
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF00897B), Color(0xFF00695C)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.card_giftcard_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Booking with Ride Credit',
                          style: TextStyle(color: Colors.white70, fontSize: 10,
                              fontWeight: FontWeight.w600)),
                      Text(
                        'FREE ${widget.rideType.toUpperCase()} RIDE  (Value: ₦${widget.amount})',
                        style: const TextStyle(color: Colors.white, fontSize: 14,
                            fontWeight: FontWeight.w800),
                      ),
                    ])),
                  ]),
                ),
                const SizedBox(height: 20),

                // Pickup
                const Text('Pickup Location',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                _locationGrid(
                  selected: _pickup,
                  disabled: _destination,
                  onSelect: (l) => setState(() => _pickup = l),
                ),
                const SizedBox(height: 16),

                // Destination
                const Text('Destination',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                _locationGrid(
                  selected: _destination,
                  disabled: _pickup,
                  onSelect: (l) => setState(() => _destination = l),
                ),
                const SizedBox(height: 20),

                // Confirm button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _booking ? null : _confirmBooking,
                    icon: _booking
                        ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                        : Icon(Icons.directions_bus_rounded,
                        size: 20, color: Colors.white),
                    label: Text(
                      _booking
                          ? 'Booking...'
                          : 'Confirm Free ${widget.rideType} Ride',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _locationGrid({
    required String? selected,
    required String? disabled,
    required void Function(String) onSelect,
  }) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _allLocations.map((loc) {
        final isSel = selected == loc;
        final isDis = disabled == loc;
        return GestureDetector(
          onTap: isDis ? null : () => onSelect(loc),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSel
                  ? const Color(0xFF00897B)
                  : isDis ? AppColors.background : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSel
                    ? const Color(0xFF00897B)
                    : isDis ? AppColors.divider : AppColors.inputBorder,
              ),
            ),
            child: Text(loc, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: isSel
                  ? Colors.white
                  : isDis ? AppColors.textHint : AppColors.textPrimary,
            )),
          ),
        );
      }).toList(),
    );
  }
}

// ======================================================================
// ITEM CARD — shown in both All Active and My Posts tabs
// ======================================================================
class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId, myUid;
  final bool showClaimButton;
  final bool isOwner;
  const _ItemCard({required this.data, required this.docId,
    required this.myUid, required this.showClaimButton,
    this.isOwner = false});

  Color get _typeColor => data['itemType'] == 'Found'
      ? const Color(0xFF00897B)
      : AppColors.error;

  IconData get _typeIcon => data['itemType'] == 'Found'
      ? Icons.volunteer_activism_rounded
      : Icons.search_rounded;

  Color get _statusColor {
    switch (data['status']) {
      case 'Recovered': return AppColors.success;
      case 'Pending Claim': return AppColors.warning;
      default: return _typeColor;
    }
  }

  // Helper to check if imageUrl is base64
  bool _isBase64(String url) {
    return url.startsWith('data:image');
  }

  @override
  Widget build(BuildContext context) {
    final ts = data['timestamp'];
    final date = ts != null
        ? Helpers.formatDateTime((ts as Timestamp).toDate())
        : '';
    final status       = data['status'] ?? data['itemType'] ?? 'Unknown';
    final imageUrl = data['imageUrl'] ?? '';

    return GestureDetector(
      onTap: () => _showDetailSheet(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color:        AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(color: AppColors.cardBorder),
          boxShadow: [BoxShadow(color: AppColors.shadow,
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header strip
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color:        _typeColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border:       Border(bottom: BorderSide(color: _typeColor.withOpacity(0.2))),
            ),
            child: Row(children: [
              Icon(_typeIcon, color: _typeColor, size: 18),
              const SizedBox(width: 6),
              Text(data['itemType'] ?? '',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                      color: _typeColor)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:        _typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(data['category'] ?? '',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: _typeColor)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border:       Border.all(color: _statusColor.withOpacity(0.3)),
                ),
                child: Text(status.toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        color: _statusColor)),
              ),
            ]),
          ),

          // Image — using conditional: base64 or network
          if (imageUrl.isNotEmpty)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.zero,
                child: _isBase64(imageUrl)
                    ? Image.memory(
                  base64Decode(imageUrl.split(',').last),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 60,
                    color: AppColors.surfaceVariant,
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_rounded,
                              color: AppColors.textHint, size: 20),
                          SizedBox(width: 6),
                          Text('Image unavailable',
                              style: TextStyle(fontSize: 12,
                                  color: AppColors.textHint)),
                        ],
                      ),
                    ),
                  ),
                )
                    : CachedNetworkImage(
                  imageUrl: imageUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  httpHeaders: const {'User-Agent': 'Mozilla/5.0'},
                  placeholder: (_, __) => Container(
                    height: 180,
                    color: AppColors.surfaceVariant,
                    child: const Center(child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00897B))),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 60,
                    color: AppColors.surfaceVariant,
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_rounded,
                              color: AppColors.textHint, size: 20),
                          SizedBox(width: 6),
                          Text('Image unavailable',
                              style: TextStyle(fontSize: 12,
                                  color: AppColors.textHint)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Gradient overlay at bottom of image
              Positioned(
                bottom: 0, left: 0, right: 0, height: 70,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
            ]),

          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['description'] ?? '',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.location_on_rounded, size: 14,
                    color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(data['locationName'] ?? '',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const Spacer(),
                Text(date, style: const TextStyle(
                    fontSize: 11, color: AppColors.textHint)),
              ]),
              if (data['userName'] != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.person_outline_rounded, size: 14,
                      color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('Posted by ${data['userName']}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
              ],

              if (data['ownerUserId'] != null &&
                  data['ownerUserId'].toString().isNotEmpty &&
                  data['itemType'] == 'Found' &&
                  data['status'] != 'Recovered') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color:        AppColors.infoLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    Icon(Icons.hourglass_empty_rounded, size: 14, color: AppColors.info),
                    SizedBox(width: 6),
                    Text('Claim submitted — awaiting admin review',
                        style: TextStyle(fontSize: 11, color: AppColors.info)),
                  ]),
                ),
              ],

              // Owner: mark own lost item as recovered
              if (isOwner && data['itemType'] == 'Lost' &&
                  data['status'] != 'Recovered') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _markRecovered(context),
                    icon:  const Icon(Icons.check_circle_outline_rounded,
                        size: 16, color: Color(0xFF00897B)),
                    label: const Text('Mark as Recovered',
                        style: TextStyle(color: Color(0xFF00897B),
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00897B)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  void _showDetailSheet(BuildContext context) {
    final imageUrl = data['imageUrl'] ?? '';
    final ts = data['timestamp'];
    final date = ts != null
        ? Helpers.formatDateTime((ts as Timestamp).toDate()) : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            // Handle
            Center(child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            )),
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_typeIcon, color: _typeColor, size: 14),
                    const SizedBox(width: 5),
                    Text(data['itemType'] ?? '',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: _typeColor)),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _typeColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(data['category'] ?? '',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700, color: _typeColor)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // Image — conditional
                  if (imageUrl.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _isBase64(imageUrl)
                          ? Image.memory(
                        base64Decode(imageUrl.split(',').last),
                        width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          height: 200, color: Colors.grey.shade100,
                          child: const Center(
                              child: Text('Image unavailable',
                                  style: TextStyle(color: Colors.grey))),
                        ),
                      )
                          : CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => Container(
                            height: 200, color: Colors.grey.shade100,
                            child: const Center(child: CircularProgressIndicator(
                                strokeWidth: 2))),
                        errorWidget: (_, __, ___) => Container(
                          height: 80, color: Colors.grey.shade100,
                          child: const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image_rounded,
                                    color: Colors.grey, size: 20),
                                SizedBox(width: 6),
                                Text('Image unavailable',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  // Description
                  const Text('Description', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  Text(data['description'] ?? '',
                      style: const TextStyle(fontSize: 15,
                          color: Color(0xFF1A1A2E), height: 1.5)),
                  const SizedBox(height: 20),
                  // Location + date
                  _detailRow(Icons.location_on_rounded,
                      data['locationName'] ?? 'Unknown location'),
                  const SizedBox(height: 10),
                  _detailRow(Icons.access_time_rounded, date),
                  const SizedBox(height: 10),
                  _detailRow(Icons.person_outline_rounded,
                      'Posted by ${data['userName'] ?? 'Unknown'}'),
                  if ((data['contactInfo'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _detailRow(Icons.phone_rounded, data['contactInfo']),
                  ],
                  const SizedBox(height: 24),
                  // Claim button if applicable
                  if (showClaimButton &&
                      data['itemType'] == 'Found' &&
                      data['userId'] != myUid &&
                      (data['ownerUserId'] ?? '').isEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.volunteer_activism_rounded, size: 18),
                        label: const Text('This Is Mine — Claim Item',
                            style: TextStyle(fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        onPressed: () {
                          Navigator.pop(context);
                          _claimItem(context);
                        },
                      ),
                    ),
                  if (isOwner && data['itemType'] == 'Lost' &&
                      data['status'] != 'Recovered')
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _markRecovered(context);
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded,
                            size: 16, color: Color(0xFF00897B)),
                        label: const Text('Mark as Recovered',
                            style: TextStyle(color: Color(0xFF00897B),
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF00897B)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _detailRow(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: const Color(0xFF00897B)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(
          fontSize: 13, color: Color(0xFF333344), height: 1.4))),
    ],
  );

  Future<void> _claimItem(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Claim this item?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'By claiming this item you confirm it belongs to you. '
                'Admin will review your claim and set a recovery fine based on the item.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:        AppColors.warningLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '⚠️ A fine will be set by admin and must be paid to the finder before the item is returned.',
              style: TextStyle(fontSize: 11, color: AppColors.warning, height: 1.5),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B)),
            child: const Text('Yes, This is Mine',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('lost_found')
            .doc(docId)
            .update({
          'ownerUserId': myUid,
          'status':      'Pending Claim',
          'updatedAt':   FieldValue.serverTimestamp(),
        });
        // Notify the finder so it surfaces in Notifications + Dashboard
        final finderId = data['finderUserId'] as String? ?? data['userId'] as String?;
        if (finderId != null && finderId.isNotEmpty && finderId != myUid) {
          await FirebaseFirestore.instance.collection('notifications').add({
            'userId':    finderId,
            'title':     '🔍 Item Claimed',
            'body':      'Someone claimed the ${data['category'] ?? 'item'} you found '
                '("${data['description'] ?? ''}"). Admin will review the claim.',
            'type':      'lost_found',
            'lostFoundId': docId,
            'read':      false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Claim submitted! Admin will review and set the fine.'),
            backgroundColor: Color(0xFF00897B),
            behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (_) {}
    }
  }

  Future<void> _markRecovered(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as Recovered?'),
        content: const Text(
            'This will remove the item from the public listing. '
                'It will stay in your history.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B)),
            child: const Text('Mark Recovered',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('lost_found')
          .doc(docId)
          .update({
        'status':    'Recovered',
        'is_active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}

// ======================================================================
// POST ITEM SHEET — user posts a lost or found item
// ======================================================================
class _PostItemSheet extends StatefulWidget {
  final String myUid;
  const _PostItemSheet({required this.myUid});
  @override
  State<_PostItemSheet> createState() => _PostItemSheetState();
}

class _PostItemSheetState extends State<_PostItemSheet> {
  final _descCtrl     = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _contactCtrl  = TextEditingController();
  final _storage      = StorageService();
  File? _pickedImageFile;
  bool _pickingImage = false;
  String  _itemType        = 'Found';
  String  _category        = 'Phone';
  String? _locationName;
  bool    _submitting      = false;
  bool    _showSuggestions = false;
  String  _userName        = '';

  static const List<String> _categories = [
    'Phone', 'Bag', 'ID Card', 'Keys', 'Laptop', 'Wallet', 'Clothes', 'Other',
  ];

  List<String> get _locationSuggestions {
    final q = _locationCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return Esp32Service.allLocations;
    return Esp32Service.allLocations
        .where((l) => l.toLowerCase().contains(q))
        .toList();
  }


  @override
  void initState() {
    super.initState();
    _loadName();
    _locationCtrl.addListener(() {
      if (mounted) setState(() {
        _showSuggestions = _locationCtrl.text.isNotEmpty;
        if (_locationName != null && _locationCtrl.text != _locationName) {
          _locationName = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadName() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.myUid)
        .get();
    if (mounted) setState(() => _userName = doc.data()?['name'] ?? 'User');
  }


  Future<void> _submit() async {
    // Lost & Found is online-only — items must be posted to the live board
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No internet connection. Lost & Found requires an active connection to post items.'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ));
      return;
    }
    if (_descCtrl.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please add a description (at least 5 characters).'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    final locationText = _locationName ?? _locationCtrl.text.trim();
    if (locationText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter the location where the item was found/lost.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    setState(() => _submitting = true);
    try {

      final role = (await FirebaseFirestore.instance
          .collection('users').doc(widget.myUid).get())
          .data()?['role'] ?? 'user';

      // Reserve the doc ID up front so the Storage upload path can use it
      final docRef = FirebaseFirestore.instance.collection('lost_found').doc();

      String uploadedImageUrl = '';
      if (_pickedImageFile != null) {
        final uploadResult = await _storage.uploadLostFoundImage(
          imageFile: _pickedImageFile!,
          itemId: docRef.id,
        );
        if (uploadResult['success'] == true) {
          uploadedImageUrl = uploadResult['url'] as String? ?? '';
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(uploadResult['error'] ?? 'Image upload failed — posting without photo.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }

      await docRef.set({
        'userId':       widget.myUid,
        'userName':     _userName,
        'userRole':     role,
        'itemType':     _itemType,
        'category':     _category,
        'description':  _descCtrl.text.trim(),
        'locationCode': Esp32Service.getLocationCode(locationText),
        'locationName': locationText,
        'imageUrl': uploadedImageUrl,
        'status':       _itemType,
        'is_active':    true,
        'fineAmount':   0,
        'finePaid':     false,
        'rewardGiven':  false,
        'finderUserId': _itemType == 'Found' ? widget.myUid : '',
        'ownerUserId':  _itemType == 'Lost'  ? widget.myUid : '',
        'contactInfo':  _contactCtrl.text.trim(),
        'timestamp':    FieldValue.serverTimestamp(),
        'updatedAt':    FieldValue.serverTimestamp(),
      });

      // Broadcast a Lost & Found notification when a "Found" item is
      // posted, so other users see it in Notifications + Dashboard.
      if (_itemType == 'Found') {
        try {
          final usersSnap = await FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'user')
              .get();
          final batch = FirebaseFirestore.instance.batch();
          for (final u in usersSnap.docs) {
            if (u.id == widget.myUid) continue;
            final ref = FirebaseFirestore.instance.collection('notifications').doc();
            batch.set(ref, {
              'userId':      u.id,
              'title':       '🔍 Item Found',
              'body':        '${_category} found at $locationText. '
                  'Check Lost & Found in case it\'s yours.',
              'type':        'lost_found',
              'lostFoundId': docRef.id,
              'read':        false,
              'createdAt':   FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        } catch (_) {
          // Non-fatal — the item post itself already succeeded above.
        }
      }

      if (mounted) {
        await showFullScreenAd(context);

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_itemType == 'Found'
                ? 'Found item posted! Other users can now see and claim this item.'
                : 'Lost item posted! You\'ll be notified if someone finds it.'),
            backgroundColor: const Color(0xFF00897B),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Handle
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Post a Lost / Found Item',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Help reunite items with their owners.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 20),

            // Item type toggle
            const Text('Item Type', style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Row(children: ['Lost', 'Found'].asMap().entries.map((e) {
              final sel = _itemType == e.value;
              final color = e.value == 'Found'
                  ? const Color(0xFF00897B) : AppColors.error;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _itemType = e.value),
                  child: Container(
                    margin: EdgeInsets.only(right: e.key == 0 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: sel ? color : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? color : AppColors.inputBorder),
                    ),
                    child: Column(children: [
                      Icon(e.value == 'Found'
                          ? Icons.volunteer_activism_rounded
                          : Icons.search_rounded,
                          color: sel ? Colors.white : color, size: 22),
                      const SizedBox(height: 4),
                      Text(e.value, style: TextStyle(fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : color)),
                      Text(e.value == 'Found'
                          ? 'I found something' : 'I lost something',
                          style: TextStyle(fontSize: 10,
                              color: sel ? Colors.white70 : AppColors.textSecondary)),
                    ]),
                  ),
                ),
              );
            }).toList()),
            const SizedBox(height: 20),

            // Category
            const Text('Category', style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8,
              children: _categories.map((cat) {
                final sel = _category == cat;
                return GestureDetector(
                  onTap: () => setState(() => _category = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF00897B) : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel ? const Color(0xFF00897B) : AppColors.inputBorder),
                    ),
                    child: Text(cat, style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : AppColors.textPrimary)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Location
            const Text('Location', style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
              _itemType == 'Found' ? 'Where did you find it?' : 'Where did you last see it?',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _locationCtrl,
                onTap: () => setState(() => _showSuggestions = true),
                decoration: InputDecoration(
                  hintText: 'e.g. AFIT Gate, ICE Department...',
                  prefixIcon: const Icon(Icons.location_on_rounded,
                      color: Color(0xFF00897B), size: 20),
                  suffixIcon: _locationName != null
                      ? const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF00897B), size: 20)
                      : null,
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.inputBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00897B), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              if (_showSuggestions && _locationSuggestions.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.inputBorder),
                    boxShadow: [BoxShadow(color: AppColors.shadow,
                        blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _locationSuggestions.length,
                    itemBuilder: (_, i) {
                      final loc = _locationSuggestions[i];
                      return InkWell(
                        onTap: () => setState(() {
                          _locationName = loc;
                          _locationCtrl.text = loc;
                          _showSuggestions = false;
                          FocusScope.of(context).unfocus();
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(children: [
                            const Icon(Icons.location_on_outlined,
                                size: 14, color: Color(0xFF00897B)),
                            const SizedBox(width: 8),
                            Text(loc, style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 20),

            // Description
            const Text('Description', style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            CustomTextField(
              label: 'Describe the item',
              hint:  'Colour, brand, distinguishing features...',
              controller: _descCtrl,
              prefixIcon: Icons.description_outlined,
              maxLines: 3,
            ),

            const SizedBox(height: 16),

            // Photo picker
            const Text('Photo (optional)', style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickingImage ? null : () async {
                setState(() => _pickingImage = true);
                try {
                  final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
                  if (picked != null) {
                    setState(() => _pickedImageFile = File(picked.path));
                  }
                } catch (_) {}
                if (mounted) setState(() => _pickingImage = false);
              },
              child: Container(
                height: _pickedImageFile != null ? 160 : 56,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00897B), width: 1.5),
                ),
                child: _pickedImageFile != null
                    ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(_pickedImageFile!,
                        fit: BoxFit.cover, width: double.infinity))
                    : _pickingImage
                    ? const Center(child: CircularProgressIndicator(
                    color: Color(0xFF00897B), strokeWidth: 2))
                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_photo_alternate_rounded, size: 22,
                      color: Color(0xFF00897B)),
                  SizedBox(width: 8),
                  Text('Tap to add photo', style: TextStyle(
                      fontSize: 13, color: Color(0xFF00897B),
                      fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            if (_pickedImageFile != null) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _pickedImageFile = null),
                child: const Text('Remove photo',
                    style: TextStyle(fontSize: 11, color: AppColors.error)),
              ),
            ],

            const SizedBox(height: 16),
            // Contact Info
            const Text('Contact Info', style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Phone number or other way to reach you (optional)',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: _contactCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'e.g. 08012345678',
                prefixIcon: const Icon(Icons.phone_rounded,
                    color: Color(0xFF00897B), size: 20),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.inputBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.inputBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF00897B), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 24),
            CustomButton(
              text:            _itemType == 'Found' ? 'Post Found Item' : 'Post Lost Item',
              onPressed:       _submit,
              isLoading:       _submitting,
              icon:            Icons.post_add_rounded,
              backgroundColor: const Color(0xFF00897B),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

// ── Image source picker option tile ────────────────────────────────────
class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SourceOption({required this.icon, required this.label,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]),
    ),
  );
}