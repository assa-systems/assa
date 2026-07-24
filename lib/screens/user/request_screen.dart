// ═══════════════════════════════════════════════════════════════════════════
// request_screen.dart  —  v24  (FINAL – Button always clickable, auto online/offline)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/services/connectivity_service.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/services/firestore_service.dart';
import 'package:assa/services/offline_request_store.dart';
import 'package:assa/widgets/common/common_widgets.dart';
import 'package:assa/widgets/common/ad_overlay.dart';

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});
  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final _connectivity = ConnectivityService();
  final _esp32 = Esp32Service();
  final _firestoreService = FirestoreService();

  String? _selectedPickup;
  String? _selectedDestination;
  String _selectedRideType = 'Shared';
  int _passengerCount = 1;
  bool _isOnline = true;
  bool _isLoading = false;
  bool _checkingConnectivity = true;
  Map<String, dynamic>? _userData;
  String? _pickupId;
  bool _isEsp32Reachable = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkConnectivity();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null) {
        if (mounted) setState(() {
          _userData = data;
          _pickupId = data['pickupId'] as String?;
        });
        final prefs = await SharedPreferences.getInstance();
        final pickupId = data['pickupId'] as String?;
        final name = data['name'] as String?;
        if (pickupId != null && pickupId.isNotEmpty) {
          await prefs.setString('cached_pickupId', pickupId);
        }
        if (name != null && name.isNotEmpty) {
          await prefs.setString('cached_name', name);
        }
        return;
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final cachedPickupId = prefs.getString('cached_pickupId');
    final cachedName = prefs.getString('cached_name');
    if (cachedPickupId != null && mounted) {
      setState(() {
        _userData = {
          'pickupId': cachedPickupId,
          'name': cachedName ?? '',
        };
        _pickupId = cachedPickupId;
      });
    }
  }

  // ─── FAST connectivity check ─────────────────────────────────────────
  // FIX: this previously called `await _connectivity.checkConnectivity()`
  // with no try/catch and no timeout. If that native plugin call ever
  // threw OR simply hung (e.g. connectivity_plus / wifi_iot's platform
  // channel stalling on some devices), the code below it — including the
  // setState() that flips _checkingConnectivity to false — never ran, and
  // the screen was stuck on "Checking connection..." forever with no way
  // forward. Wrapping it in try/catch/timeout/finally guarantees this
  // always resolves within a few seconds, success or failure.
  Future<void> _checkConnectivity() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    bool online = false;
    bool esp32Reachable = false;
    try {
      online = await _connectivity
          .checkConnectivity()
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
    } catch (_) {
      online = false;
    }
    try {
      esp32Reachable = await _esp32.isConnectedToEsp32().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
    } catch (_) {
      esp32Reachable = false;
    }

    if (mounted) {
      setState(() {
        _isOnline = online;
        _isEsp32Reachable = esp32Reachable;
        _checkingConnectivity = false;
        // If we just went offline and the already-selected pickup isn't
        // one of the physical AP locations, it's no longer a valid
        // choice — clear it rather than silently submitting a pickup
        // the offline flow was never designed to accept.
        if (!online && _selectedPickup != null &&
            !Esp32Service.offlinePickupLocations.contains(_selectedPickup)) {
          _selectedPickup = null;
        }
      });
    }

    _connectivity.connectionStream.listen((online) async {
      if (!mounted) return;
      bool esp32Reachable = false;
      try {
        esp32Reachable = await _esp32.isConnectedToEsp32().timeout(
          const Duration(seconds: 2),
          onTimeout: () => false,
        );
      } catch (_) {
        esp32Reachable = false;
      }
      setState(() {
        _isOnline = online;
        _isEsp32Reachable = esp32Reachable;
        if (!online && _selectedPickup != null &&
            !Esp32Service.offlinePickupLocations.contains(_selectedPickup)) {
          _selectedPickup = null;
        }
      });
      if (online) _firestoreService.syncOfflineRequests();
    });
  }

  // Pickup locations are the same full campus list whether online or
  // offline — offline (campus AP) mode now shows all 12 locations too.
  List<String> get _pickupLocations => Esp32Service.allLocations;
  List<String> get _destinationLocations => Esp32Service.allLocations;

  // ─── SUBMIT REQUEST – ALWAYS TRIES, AUTO‑DETECTS PATH ─────────────
  Future<void> _submitRequest() async {
    if (_pickupId == null || _pickupId!.length != 3) {
      _showError('Your Pickup ID is missing or invalid. Please contact admin.');
      return;
    }
    if (_selectedPickup == null || _selectedDestination == null) {
      _showError('Please select both a pickup location and destination.');
      return;
    }
    if (_selectedPickup == _selectedDestination) {
      _showError('Pickup and destination cannot be the same location.');
      return;
    }
    setState(() => _isLoading = true);

    // Refresh connectivity state
    // FIX: same class of bug as _checkConnectivity() above — these two
    // native-plugin calls had no timeout, so a stall here would leave
    // _isLoading stuck true (the "Sending your request..." overlay
    // spinning forever) with no fallback.
    bool hasInternet = false;
    bool esp32Reachable = false;
    try {
      hasInternet = await _connectivity
          .checkConnectivity()
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
    } catch (_) {
      hasInternet = false;
    }
    try {
      esp32Reachable = await _esp32
          .isConnectedToEsp32()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (_) {
      esp32Reachable = false;
    }

    if (hasInternet) {
      // ─── Online path ──────────────────────────────────────────────
      await _submitOnlineRequest();
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (esp32Reachable) {
      // ─── Offline path (campus WiFi) ──────────────────────────────
      await _submitOfflineRequest();
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // ─── Neither – show error ───────────────────────────────────────
    if (mounted) {
      setState(() => _isLoading = false);
      _showError('No internet connection and not connected to campus WiFi.');
    }
  }

  Future<void> _submitOnlineRequest() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userName = _userData?['name'] ?? '';
    final pickupId = _pickupId!;

    final String? bookingId = await _firestoreService.submitOnlineRequest(
      userId: uid,
      userName: userName,
      onlineUUID: pickupId,
      pickupLocation: _selectedPickup!,
      destination: _selectedDestination!,
      rideType: _selectedRideType,
      passengerCount: _selectedRideType == 'Chartered' ? 1 : _passengerCount,
    );

    if (!mounted) return;
    if (bookingId is String && bookingId.isNotEmpty) {
      await showFullScreenAd(context);
      if (!mounted) return;
      _showOnlineFeedbackDialog(bookingId);
    } else {
      _showError('Failed to submit request. Please try again.');
    }
  }

  Future<void> _submitOfflineRequest() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      _showError('User not authenticated. Please log in again.');
      return;
    }

    final esp32Connected = await _esp32.isConnectedToEsp32();
    if (!esp32Connected) {
      if (mounted) setState(() => _isLoading = false);
      _showEsp32Dialog();
      return;
    }

    final userName = (_userData?['name'] as String?) ?? '';
    if (userName.isEmpty) {
      _showError('Name not found. Please contact admin.');
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final result = await _esp32.sendRequestToEsp32(
      userName: userName,
      pickupLocation: _selectedPickup!,
      destination: _selectedDestination!,
      rideType: _selectedRideType,
      passengerCount: _selectedRideType == 'Chartered' ? 1 : _passengerCount,
      pickupId: _userData?['pickupId'] as String?,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final bookingId = result['bookingId'] as String? ?? '';
      final String id = bookingId.isNotEmpty ? bookingId : (result['id'] as String? ?? '');

      if (mounted) setState(() => _isLoading = false);

      if (id.isEmpty) {
        _showError('No booking ID received from AP.');
        return;
      }

      await OfflineRequestStore.instance.add(OfflineRequest(
        pid: id,
        pickupLocation: _selectedPickup!,
        destination: _selectedDestination!,
        rideType: _selectedRideType,
        passengerCount: _selectedRideType == 'Chartered' ? 1 : _passengerCount,
        createdAt: DateTime.now(),
        status: OfflineStatus.pending,
      ));
      debugPrint('[Offline] Saved to local store — id:$id');

      await showFullScreenAd(context);
      if (!mounted) return;

      _showOfflineFeedbackDialog(
        offlineUUID: id,
        confirmedFrom: _selectedPickup!,
        confirmedTo: _selectedDestination!,
        remainingBudget: result['remainingBudget'] as int? ?? 0,
      );
    } else {
      if (mounted) setState(() => _isLoading = false);
      _showError(result['error'] ?? 'Failed to send offline request.');
    }
  }

  void _showOnlineFeedbackDialog(String bookingId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OnlineFeedbackDialog(bookingId: bookingId),
    );
  }

  void _showOfflineFeedbackDialog({
    required String offlineUUID,
    required String confirmedFrom,
    required String confirmedTo,
    required int remainingBudget,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OfflineFeedbackDialog(
        offlineUUID: offlineUUID,
        confirmedFrom: confirmedFrom,
        confirmedTo: confirmedTo,
        remainingBudget: remainingBudget,
      ),
    );
  }

  void _showEsp32Dialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text('Connect to Campus WiFi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.pendingColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'You are in offline mode. To send a request, connect '
                  'to the campus AFIT KEKE WiFi network first.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          _StepTile('1', 'Open your phone WiFi settings'),
          _StepTile('2', 'Connect to the AFIT KEKE WiFi network (named "ASSA-System")'),
          _StepTile('3', 'Wait 5 seconds, then return here'),
          _StepTile('4', 'Tap Send again'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'The WiFi network has no internet. Your phone may show "No Internet".',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ]),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AppColors.pendingColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: 'Sending your request...',
        child: SafeArea(
          child: Column(children: [
            _buildHeader(context),
            Expanded(
              child: _checkingConnectivity
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Checking connection...',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              )
                  : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModeIndicator(),
                    const SizedBox(height: 24),
                    const Text('Pickup Location',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    _buildLocationGrid(
                      locations: _pickupLocations,
                      selected: _selectedPickup,
                      onSelect: (loc) => setState(() => _selectedPickup = loc),
                      disabledItem: _selectedDestination,
                    ),
                    const SizedBox(height: 28),
                    const Text('Destination',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    _buildLocationGrid(
                      locations: _destinationLocations,
                      selected: _selectedDestination,
                      onSelect: (loc) => setState(() => _selectedDestination = loc),
                      disabledItem: _selectedPickup,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                      ),
                      child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 15),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Select the point closest to your destination. '
                                    'You can negotiate your exact drop-off point '
                                    'with the driver on arrival.',
                                style: TextStyle(fontSize: 14, color: AppColors.textSecondary,
                                    height: 1.5),
                              ),
                            ),
                          ]),
                    ),
                    const SizedBox(height: 28),
                    const Text('Ride Options',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    _buildRideTypeSelector(),
                    const SizedBox(height: 24),
                    if (_selectedPickup != null && _selectedDestination != null) ...[
                      _buildSummaryCard(),
                      const SizedBox(height: 24),
                    ],
                    // ─── BUTTON: ALWAYS ENABLED ──────────────────────────
                    CustomButton(
                      text: 'Send Request',
                      onPressed: _submitRequest,
                      isLoading: _isLoading,
                      icon: Icons.send_rounded,
                      backgroundColor: AppColors.primary,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ─── UI Builders ──────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF0D47A1)]),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        ),
        const Expanded(
          child: Text('Book a Ride',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              _checkingConnectivity
                  ? Icons.wifi_find_rounded
                  : _isEsp32Reachable ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: Colors.white, size: 12,
            ),
            const SizedBox(width: 4),
            Text(
              _checkingConnectivity ? 'Checking...'
                  : _isEsp32Reachable ? 'Campus Mode' : 'No WiFi',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildModeIndicator() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isOnline
            ? AppColors.success.withOpacity(0.08)
            : AppColors.pendingColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isOnline
              ? AppColors.success.withOpacity(0.3)
              : AppColors.pendingColor.withOpacity(0.3),
        ),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: (_isOnline ? AppColors.success : AppColors.pendingColor).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isOnline ? Icons.cloud_done_rounded : Icons.wifi_rounded,
            color: _isOnline ? AppColors.success : AppColors.pendingColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _isOnline ? 'Online Mode' : 'Offline Campus Mode',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: _isOnline ? AppColors.success : AppColors.pendingColor),
            ),
            Text(
              _isOnline
                  ? 'All campus locations available.'
                  : 'Campus WiFi mode — all locations available without internet.',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildLocationGrid({
    required List<String> locations,
    required String? selected,
    required Function(String) onSelect,
    String? disabledItem,
  }) {
    if (locations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: const Center(child: Text('No locations available.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
      );
    }

    return Wrap(
      spacing: 8, runSpacing: 8,
      children: locations.map((loc) {
        final isSelected = selected == loc;
        final isDisabled = disabledItem == loc;
        return GestureDetector(
          onTap: isDisabled ? null : () => onSelect(loc),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary
                  : isDisabled ? AppColors.background : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppColors.primary
                    : isDisabled ? AppColors.divider : AppColors.inputBorder,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: AppColors.primary.withOpacity(0.25),
                  blurRadius: 6, offset: const Offset(0, 2))]
                  : [],
            ),
            child: Text(loc,
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white
                    : isDisabled ? AppColors.textHint : AppColors.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRideTypeSelector() {
    final isChartered = _selectedRideType == 'Chartered';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _RideTypeCard(
          label: 'Shared Ride', subtitle: '1–4 passengers',
          icon: Icons.directions_bus_rounded,
          selected: !isChartered,
          onTap: () => setState(() => _selectedRideType = 'Shared'),
        ),
        const SizedBox(width: 10),
        _RideTypeCard(
          label: 'Chartered', subtitle: 'Private AFIT KEKE',
          icon: Icons.airline_seat_recline_extra_rounded,
          selected: isChartered,
          onTap: () => setState(() => _selectedRideType = 'Chartered'),
        ),
      ]),
      if (!isChartered) ...[
        const SizedBox(height: 16),
        const Text('Number of Passengers',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (i) {
            final count = i + 1;
            final sel = _passengerCount == count;
            return GestureDetector(
              onTap: () => setState(() => _passengerCount = count),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: sel ? AppColors.primary : AppColors.inputBorder,
                      width: sel ? 2 : 1),
                  boxShadow: sel ? [BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 6, offset: const Offset(0, 2))] : [],
                ),
                child: Center(child: Text('$count',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                        color: sel ? Colors.white : AppColors.textPrimary))),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          _passengerCount == 1 ? 'Just me' : '$_passengerCount passengers',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.success.withOpacity(0.25)),
          ),
          child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.people_alt_outlined, color: AppColors.success, size: 15),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Are others at your bus stop? Select the number of '
                        'passengers with you and submit a '
                        'shared ride — one AFIT KEKE picks you all up together.',
                    style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                  ),
                ),
              ]),
        ),
      ],
    ]);
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [BoxShadow(color: AppColors.shadow,
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Request Summary',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        _SummaryRow(Icons.radio_button_checked_rounded, AppColors.success,
            'From', _selectedPickup!),
        const SizedBox(height: 12),
        _SummaryRow(Icons.location_on_rounded, AppColors.error,
            'To', _selectedDestination!),
        const SizedBox(height: 8),
        _SummaryRow(Icons.directions_bus_rounded, AppColors.primary,
            'Type', _selectedRideType == 'Chartered'
                ? 'Chartered (private)'
                : 'Shared · $_passengerCount passenger${_passengerCount > 1 ? 's' : ''}'),
      ]),
    );
  }
}

// ─── Online Feedback Dialog ──────────────────────────────────────────────
class _OnlineFeedbackDialog extends StatefulWidget {
  final String bookingId;
  const _OnlineFeedbackDialog({required this.bookingId});
  @override
  State<_OnlineFeedbackDialog> createState() => _OnlineFeedbackDialogState();
}

class _OnlineFeedbackDialogState extends State<_OnlineFeedbackDialog> {
  StreamSubscription<DocumentSnapshot>? _sub;
  Timer? _cancelTimer;
  int _status = 0;
  String _shuttleId = '';

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(widget.bookingId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final d = snap.data() as Map<String, dynamic>;
      setState(() {
        _status = (d['status'] as int?) ?? 0;
        final raw = d['shuttleIdFeedback'];
        _shuttleId = (raw != null && raw.toString().isNotEmpty && raw.toString() != '0')
            ? raw.toString() : '';
      });

      // If status changed from pending, we don't need the auto-cancel anymore
      if (_status > 0) {
        _cancelTimer?.cancel();
      }
    });

    // Auto-cancel if still pending after 5 minutes
    _cancelTimer = Timer(const Duration(minutes: 5), () async {
      if (mounted && _status == 0) {
        try {
          await FirebaseFirestore.instance
              .collection('ride_requests')
              .doc(widget.bookingId)
              .update({'status': 4});
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cancelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noShuttle = _status == 4;
    final accepted = _status == 2;
    final completed = _status == 6;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: noShuttle ? AppColors.error.withOpacity(0.12)
                  : completed ? AppColors.success.withOpacity(0.12)
                  : AppColors.pendingColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              noShuttle ? Icons.directions_bus_filled_rounded
                  : completed ? Icons.flag_rounded
                  : Icons.check_circle_rounded,
              size: 36,
              color: noShuttle ? AppColors.error
                  : completed ? AppColors.success
                  : AppColors.pendingColor,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            noShuttle ? 'No AFIT KEKE Available'
                : completed ? 'Ride Complete!'
                : 'Request Sent!',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          if (noShuttle) ...[
            const SizedBox(height: 8),
            const Text(
              'All AFIT KEKEs were unavailable. Please try again in a few minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 20),
          _RequestStage(
            icon: Icons.send_rounded, color: AppColors.success,
            label: 'Request Sent',
            sub: 'Your request is live on the network',
            done: true,
          ),
          _RequestStage(
            icon: noShuttle ? Icons.cancel_rounded
                : completed ? Icons.flag_rounded
                : Icons.check_circle_rounded,
            color: noShuttle ? AppColors.error
                : completed ? AppColors.success
                : AppColors.primary,
            label: noShuttle ? 'No Driver Available'
                : completed ? 'Ride Completed'
                : 'Driver Accepted',
            sub: noShuttle
                ? 'No driver accepted. Please try again.'
                : completed
                ? 'Thank you for riding with ASSA!'
                : accepted
                ? '$_shuttleId is on its way!'
                : 'Waiting for a driver to accept…',
            done: accepted || noShuttle || completed,
          ),
          if (!noShuttle && !completed)
            _RequestStage(
              icon: Icons.flag_rounded,
              color: AppColors.success,
              label: 'Completed',
              sub: 'In progress…',
              done: false,
            ),
          const SizedBox(height: 20),
          CustomButton(
            text: noShuttle ? 'Try Again' : 'Done',
            onPressed: () {
              Navigator.pop(context);
              if (!noShuttle) Navigator.pop(context);
            },
          ),
        ]),
      ),
    );
  }
}

// ─── Offline Feedback Dialog ──────────────────────────────────────────────
class _OfflineFeedbackDialog extends StatefulWidget {
  final String offlineUUID;
  final String confirmedFrom;
  final String confirmedTo;
  final int remainingBudget;
  const _OfflineFeedbackDialog({
    required this.offlineUUID,
    required this.confirmedFrom,
    required this.confirmedTo,
    required this.remainingBudget,
  });
  @override
  State<_OfflineFeedbackDialog> createState() => _OfflineFeedbackDialogState();
}

class _OfflineFeedbackDialogState extends State<_OfflineFeedbackDialog> {
  final _esp32 = Esp32Service();
  Timer? _pollTimer;
  bool _gatewayForwarded = false;
  bool _assigned = false;
  bool _noShuttle = false;
  bool _apUnreachable = false;
  String _shuttleId = '';
  int _pollAttempts = 0;
  static const int maxPollAttempts = 30;

  @override
  void initState() {
    super.initState();
    _pollAP();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollAP());
  }

  Future<void> _pollAP() async {
    if (!mounted) return;

    _pollAttempts++;

    if (_pollAttempts > maxPollAttempts) {
      setState(() {
        _noShuttle = true;
        _gatewayForwarded = true;
      });
      await OfflineRequestStore.instance.updateStatus(
        widget.offlineUUID,
        OfflineStatus.rejected,
      );
      _pollTimer?.cancel();
      return;
    }

    final result = await _esp32.pollRequestStatus(widget.offlineUUID);
    if (!mounted) return;

    final status = result['status'] as String? ?? 'PENDING';

    if (status == 'ERROR') {
      setState(() => _apUnreachable = true);
      return;
    }
    setState(() => _apUnreachable = false);

    debugPrint('[Offline] Poll $widget.offlineUUID: status=$status, AFIT KEKE=${result['AFIT KEKE']}');

    switch (status) {
      case 'ACCEPTED':
      case 'CONFIRMED':
        final shuttle = result['AFIT KEKE'] as String? ?? '';
        setState(() {
          _gatewayForwarded = true;
          _assigned = true;
          _shuttleId = shuttle;
        });
        await OfflineRequestStore.instance.updateStatus(
          widget.offlineUUID,
          status == 'CONFIRMED' ? OfflineStatus.confirmed : OfflineStatus.accepted,
          shuttleId: shuttle,
        );
        _pollTimer?.cancel();
        break;
      case 'ASSIGNED':
        setState(() {
          _gatewayForwarded = true;
        });
        break;
      case 'REJECTED':
      case 'CANCELLED':
        setState(() {
          _gatewayForwarded = true;
          _noShuttle = true;
        });
        await OfflineRequestStore.instance.updateStatus(
          widget.offlineUUID,
          OfflineStatus.rejected,
        );
        _pollTimer?.cancel();
        break;
      case 'EXPIRED':
        setState(() {
          _gatewayForwarded = true;
          _noShuttle = true;
        });
        await OfflineRequestStore.instance.updateStatus(
          widget.offlineUUID,
          OfflineStatus.rejected,
        );
        _pollTimer?.cancel();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: _noShuttle ? AppColors.error.withOpacity(0.12)
                  : _assigned ? AppColors.success.withOpacity(0.12)
                  : AppColors.pendingColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _noShuttle ? Icons.directions_bus_filled_rounded
                  : _assigned ? Icons.check_circle_rounded
                  : Icons.wifi_rounded,
              size: 36,
              color: _noShuttle ? AppColors.error
                  : _assigned ? AppColors.success
                  : AppColors.pendingColor,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _noShuttle ? 'No AFIT KEKE Available'
                : _assigned ? 'AFIT KEKE Assigned!'
                : 'Request Sent!',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            _noShuttle ? 'Please try again in a few minutes'
                : 'Campus WiFi Mode  •  ID: ${widget.offlineUUID}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (!_noShuttle && widget.confirmedFrom.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.15)),
              ),
              child: Row(children: [
                const Icon(Icons.route_rounded, color: AppColors.primary, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.confirmedFrom}  →  ${widget.confirmedTo}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          _RequestStage(
            icon: Icons.router_rounded, color: AppColors.success,
            label: 'Access Point Received',
            sub: 'Request sent to campus AFIT KEKE network',
            done: true,
          ),
          _RequestStage(
            icon: _noShuttle ? Icons.cancel_rounded : Icons.cell_tower_rounded,
            color: _noShuttle ? AppColors.error : AppColors.primary,
            label: _noShuttle ? 'No AFIT KEKE Responded' : 'Gateway Forwarded',
            sub: _noShuttle
                ? 'No AFIT KEKE accepted within the timeout window'
                : _gatewayForwarded
                ? 'Request relayed to AFIT KEKE via LoRa radio'
                : 'Waiting for gateway to relay…',
            done: _gatewayForwarded || _noShuttle,
          ),
          if (!_noShuttle)
            _RequestStage(
              icon: Icons.directions_bus_rounded,
              color: _assigned ? AppColors.success : AppColors.driverColor,
              label: _assigned ? 'AFIT KEKE Assigned' : 'Waiting for AFIT KEKE',
              sub: _assigned
                  ? (_shuttleId.isNotEmpty
                  ? '$_shuttleId is on its way!'
                  : 'An AFIT KEKE has been assigned to pick you up')
                  : 'Waiting for an AFIT KEKE to accept…',
              done: _assigned,
            ),
          const SizedBox(height: 16),
          if (!_noShuttle && !_assigned)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.pendingColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.pendingColor.withOpacity(0.2)),
              ),
              child: const Column(children: [
                Row(children: [
                  Icon(Icons.lightbulb_outline_rounded, color: AppColors.pendingColor, size: 16),
                  SizedBox(width: 6),
                  Text('While you wait...', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.pendingColor)),
                ]),
                SizedBox(height: 8),
                Text('🎮  Try our puzzle game and climb the winning ladder!',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.5)),
                SizedBox(height: 4),
                Text('🔍  Check our Lost & Found box — someone may have found something of yours!',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.5)),
              ]),
            ),
          const SizedBox(height: 20),
          CustomButton(
            text: _noShuttle ? 'Try Again' : 'Done',
            onPressed: () {
              Navigator.pop(context);
              if (!_noShuttle) Navigator.pop(context);
            },
          ),
        ]),
      ),
    );
  }
}

// ─── Shared Widgets ──────────────────────────────────────────────────────
Widget _SummaryRow(IconData icon, Color color, String label, String value) {
  return Row(children: [
    Icon(icon, color: color, size: 20),
    const SizedBox(width: 8),
    Text('$label: ', style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
    Expanded(child: Text(value,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
            color: AppColors.textPrimary))),
  ]);
}

class _RideTypeCard extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _RideTypeCard({required this.label, required this.subtitle,
    required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.primary : AppColors.inputBorder),
            boxShadow: selected ? [BoxShadow(
                color: AppColors.primary.withOpacity(0.25),
                blurRadius: 6, offset: const Offset(0, 2))] : [],
          ),
          child: Column(children: [
            Icon(icon, color: selected ? Colors.white : AppColors.textSecondary, size: 26),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary)),
            Text(subtitle, style: TextStyle(fontSize: 10,
                color: selected ? Colors.white.withOpacity(0.8) : AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

class _RequestStage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, sub;
  final bool done;
  const _RequestStage({required this.icon, required this.color,
    required this.label, required this.sub, required this.done});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: done ? color.withOpacity(0.12) : AppColors.surfaceVariant,
            shape: BoxShape.circle,
            border: Border.all(color: done ? color : AppColors.divider, width: 1.5),
          ),
          child: Icon(icon, color: done ? color : AppColors.textHint, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: done ? AppColors.textPrimary : AppColors.textHint)),
          Text(sub, style: TextStyle(fontSize: 11,
              color: done ? AppColors.textSecondary : AppColors.textHint)),
        ])),
        if (done)
          const Icon(Icons.check_rounded, color: AppColors.success, size: 18)
        else
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: AppColors.divider, shape: BoxShape.circle)),
      ]),
    );
  }
}

class _StepTile extends StatelessWidget {
  final String number, text;
  const _StepTile(this.number, this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
          width: 22, height: 22,
          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          child: Center(child: Text(number,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
      ]),
    );
  }
}
