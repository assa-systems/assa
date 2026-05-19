import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/services/connectivity_service.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/services/firestore_service.dart';
import 'package:assa/widgets/common/common_widgets.dart';

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});
  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen>
    with TickerProviderStateMixin {
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
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (mounted) setState(() => _userData = doc.data());
    } catch (_) {}
  }

  Future<void> _checkConnectivity() async {
    final online = await _connectivity.checkConnectivity();
    if (mounted) {
      setState(() {
        _isOnline = online;
        _checkingConnectivity = false;
        if (!online && _selectedPickup != null) {
          if (!Esp32Service.offlinePickupLocations
              .contains(_selectedPickup)) {
            _selectedPickup = null;
          }
        }
      });
    }
    _connectivity.connectionStream.listen((online) {
      if (!mounted) return;
      setState(() {
        _isOnline = online;
        if (!online && _selectedPickup != null) {
          if (!Esp32Service.offlinePickupLocations
              .contains(_selectedPickup)) {
            _selectedPickup = null;
            _showInfo(
              'You are now in campus WiFi mode. '
              'Please reselect a hostel pickup point.',
            );
          }
        }
      });
      if (online) _firestoreService.syncOfflineRequests();
    });
  }

  // Online  → all 12 locations as pickup
  // Offline → only 3 hostel ESP32 access points
  List<String> get _pickupLocations => _isOnline
      ? Esp32Service.allLocations
      : Esp32Service.offlinePickupLocations;

  // Destinations always show all 12 regardless of mode
  List<String> get _destinationLocations => Esp32Service.allLocations;

  Future<void> _submitRequest() async {
    if (_selectedPickup == null || _selectedDestination == null) {
      _showError('Please select a pickup point and drop-off area.');
      return;
    }
    if (_selectedPickup == _selectedDestination) {
      _showError('Pickup and destination cannot be the same location.');
      return;
    }
    setState(() => _isLoading = true);
    if (_isOnline) {
      await _submitOnlineRequest();
    } else {
      await _submitOfflineRequest();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _submitOnlineRequest() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final success = await _firestoreService.submitOnlineRequest(
      userId: uid,
      userName: _userData?['name'] ?? '',
      onlineUUID: _userData?['onlineUUID'] ?? '',
      pickupLocation: _selectedPickup!,
      destination: _selectedDestination!,
      rideType: _selectedRideType,
      passengerCount:
          _selectedRideType == 'Chartered' ? 1 : _passengerCount,
    );

    if (!mounted) return;
    if (success) {
      _showModernFeedbackDialog(
        isOnline: true,
        pickupLocation: _selectedPickup!,
        destination: _selectedDestination!,
        rideType: _selectedRideType,
        passengerCount:
            _selectedRideType == 'Chartered' ? 1 : _passengerCount,
      );
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
      _showEsp32Dialog();
      return;
    }

    final pickupId = (_userData?['pickupId'] as String?) ?? '';
    if (pickupId.isEmpty) {
      _showError('Pickup ID not found. Please contact admin.');
      setState(() => _isLoading = false);
      return;
    }

    final result = await _esp32.sendRequestToEsp32(
      pickupId: pickupId,
      pickupLocation: _selectedPickup!,
      destination: _selectedDestination!,
      rideType: _selectedRideType,
      passengerCount:
          _selectedRideType == 'Chartered' ? 1 : _passengerCount,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      await _firestoreService.submitOfflineRequest(
        userId: uid,
        userName: _userData?['name'] ?? '',
        offlineUUID: _userData?['offlineUUID'] ?? uid,
        pickupLocation: _selectedPickup!,
        destination: _selectedDestination!,
        rideType: _selectedRideType,
        passengerCount:
            _selectedRideType == 'Chartered' ? 1 : _passengerCount,
      );
      _showModernFeedbackDialog(
        isOnline: false,
        pickupLocation: _selectedPickup!,
        destination: _selectedDestination!,
        rideType: _selectedRideType,
        passengerCount:
            _selectedRideType == 'Chartered' ? 1 : _passengerCount,
        pickupId: pickupId,
      );
    } else {
      _showError(result['error'] ?? 'Failed to send offline request.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(msg)),
        ],
      ),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(msg)),
        ],
      ),
      backgroundColor: AppColors.info,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showEsp32Dialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModernAlertDialog(
        icon: Icons.wifi_rounded,
        iconColor: AppColors.warning,
        title: 'Connect to Campus WiFi',
        message:
            'To send an offline request, connect your phone to the "ASSA-Campus" WiFi hotspot near your hostel, then try again.',
        actionButtonText: 'Understood',
        onActionPressed: () => Navigator.pop(context),
      ),
    );
  }

  void _showModernFeedbackDialog({
    required bool isOnline,
    required String pickupLocation,
    required String destination,
    required String rideType,
    required int passengerCount,
    String? pickupId,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RequestSuccessDialog(
        isOnline: isOnline,
        pickupLocation: pickupLocation,
        destination: destination,
        rideType: rideType,
        passengerCount: passengerCount,
        pickupId: pickupId,
        vsync: this,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Book a Ride',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        elevation: 0,
      ),
      body: _checkingConnectivity
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Mode banner ──────────────────────────────────────
                    _ModeBanner(isOnline: _isOnline),
                    const SizedBox(height: 20),

                    // ── Pickup ID display ────────────────────────────────
                    if (_userData?['pickupId'] != null) ...[
                      _PickupIdBadge(
                          pickupId: _userData!['pickupId'] as String),
                      const SizedBox(height: 20),
                    ],

                    // ── Bargain notice ───────────────────────────────────
                    _BargainNotice(),
                    const SizedBox(height: 24),

                    // ── Pickup location ──────────────────────────────────
                    const Text('Pickup Point',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 10),
                    if (!_isOnline)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Offline mode: only hostel access points available',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.warning),
                        ),
                      ),
                    _LocationDropdown(
                      value: _selectedPickup,
                      locations: _pickupLocations,
                      hint: 'Select pickup point',
                      onChanged: (v) => setState(() => _selectedPickup = v),
                    ),
                    const SizedBox(height: 20),

                    // ── Drop-off area ─────────────────────────────────────
                    const Text('Drop-off Area',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 10),
                    _LocationDropdown(
                      value: _selectedDestination,
                      locations: _destinationLocations,
                      hint: 'Select area',
                      onChanged: (v) =>
                          setState(() => _selectedDestination = v),
                    ),
                    const SizedBox(height: 20),

                    // ── Ride type ────────────────────────────────────────
                    const Text('Ride Type',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    Row(children: ['Shared', 'Chartered'].map((type) {
                      final selected = _selectedRideType == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedRideType = type;
                            if (type == 'Chartered')
                              _passengerCount = 1;
                          }),
                          child: Container(
                            margin: EdgeInsets.only(
                                right: type == 'Shared' ? 8 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.inputBorder,
                                  width: 2),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                          color: AppColors.primary
                                              .withOpacity(0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2))
                                    ]
                                  : [],
                            ),
                            child: Text(type,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.textSecondary)),
                          ),
                        ),
                      );
                    }).toList()),
                    const SizedBox(height: 20),

                    // ── Passenger count (Shared only) ────────────────────
                    if (_selectedRideType == 'Shared') ...[
                      const Text('Number of Passengers',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppColors.inputBorder, width: 1),
                        ),
                        child: Row(children: [
                          IconButton(
                            onPressed: _passengerCount > 1
                                ? () =>
                                    setState(() => _passengerCount--)
                                : null,
                            icon:
                                const Icon(Icons.remove_circle_outline_rounded),
                            color: AppColors.primary,
                          ),
                          const Spacer(),
                          Text('$_passengerCount',
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const Spacer(),
                          IconButton(
                            onPressed: _passengerCount < 4
                                ? () =>
                                    setState(() => _passengerCount++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            color: AppColors.primary,
                          ),
                        ]),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Maximum 4 passengers',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── Submit ───────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: CustomButton(
                        text: _isOnline
                            ? 'Submit Request'
                            : 'Send via Campus WiFi',
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : _submitRequest,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ]),
            ),
    );
  }
}

// ── Mode Banner ──────────────────────────────────────────────────────────
class _ModeBanner extends StatelessWidget {
  final bool isOnline;
  const _ModeBanner({required this.isOnline});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOnline
            ? AppColors.successLight
            : AppColors.warningLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isOnline ? AppColors.success : AppColors.warning,
            width: 1.5),
      ),
      child: Row(children: [
        Icon(isOnline ? Icons.cloud_done_rounded : Icons.wifi_off_rounded,
            color: isOnline ? AppColors.success : AppColors.warning,
            size: 20),
        const SizedBox(width: 12),
        Expanded(
            child: Text(
          isOnline
              ? 'Online Mode'
              : 'Offline Mode',
          style: TextStyle(
              fontSize: 13,
              color: isOnline ? AppColors.success : AppColors.warning,
              fontWeight: FontWeight.w600),
        )),
        Text(
          isOnline ? 'Connected' : 'Campus WiFi',
          style: TextStyle(
              fontSize: 11,
              color: isOnline ? AppColors.success : AppColors.warning,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3),
        ),
      ]),
    );
  }
}

// ── Pickup ID Badge ──────────────────────────────────────────────────────
class _PickupIdBadge extends StatelessWidget {
  final String pickupId;
  const _PickupIdBadge({required this.pickupId});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0D47A1).withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.badge_rounded,
              color: Colors.white, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Your Pickup ID',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(pickupId,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6)),
              const SizedBox(height: 6),
              const Text('Driver will call this ID at your pickup location',
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      height: 1.3)),
            ])),
      ]),
    );
  }
}

// ── Bargain Notice ───────────────────────────────────────────────────────
class _BargainNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFFFA000).withOpacity(0.5), width: 1.5),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline_rounded,
            color: Color(0xFFF57F17), size: 20),
        const SizedBox(width: 12),
        const Expanded(
            child: Text(
          'Select the drop-off area closest to your destination. You can negotiate the exact drop-off point with the driver when the shuttle arrives.',
          style: TextStyle(
              fontSize: 13,
              color: Color(0xFF5D4037),
              height: 1.5,
              fontWeight: FontWeight.w500),
        )),
      ]),
    );
  }
}

// ── Location Dropdown ────────────────────────────────────────────────────
class _LocationDropdown extends StatelessWidget {
  final String? value;
  final List<String> locations;
  final String hint;
  final ValueChanged<String?> onChanged;
  const _LocationDropdown({
    required this.value,
    required this.locations,
    required this.hint,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.inputBorder, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint,
              style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary),
          items: locations
              .map((loc) => DropdownMenuItem(
                    value: loc,
                    child: Text(loc,
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Modern Alert Dialog ──────────────────────────────────────────────────
class _ModernAlertDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String actionButtonText;
  final VoidCallback onActionPressed;

  const _ModernAlertDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actionButtonText,
    required this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 24,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 32),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onActionPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(actionButtonText,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Request Success Dialog ───────────────────────────────────────────────
class _RequestSuccessDialog extends StatefulWidget {
  final bool isOnline;
  final String pickupLocation;
  final String destination;
  final String rideType;
  final int passengerCount;
  final String? pickupId;
  final TickerProvider vsync;

  const _RequestSuccessDialog({
    required this.isOnline,
    required this.pickupLocation,
    required this.destination,
    required this.rideType,
    required this.passengerCount,
    this.pickupId,
    required this.vsync,
  });

  @override
  State<_RequestSuccessDialog> createState() => _RequestSuccessDialogState();
}

class _RequestSuccessDialogState extends State<_RequestSuccessDialog>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _slideController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
        );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );

    _scaleController.forward();
    _slideController.forward();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                )
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Success checkmark animation
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  widget.isOnline
                      ? Icons.cloud_done_rounded
                      : Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                widget.isOnline ? 'Request Submitted!' : 'Request Sent!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Subtitle
              Text(
                widget.isOnline
                    ? 'Your ride request is confirmed'
                    : 'Request sent via campus WiFi',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),

              // Request details card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.location_on_rounded,
                      label: 'Pickup',
                      value: widget.pickupLocation,
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        height: 1,
                        color: Colors.grey[300],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      icon: Icons.location_on_rounded,
                      label: 'Destination',
                      value: widget.destination,
                      labelColor: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        height: 1,
                        color: Colors.grey[300],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DetailRow(
                            icon: Icons.directions_car_rounded,
                            label: 'Type',
                            value: widget.rideType,
                          ),
                        ),
                        Expanded(
                          child: _DetailRow(
                            icon: Icons.group_rounded,
                            label: 'Passengers',
                            value: '${widget.passengerCount}',
                          ),
                        ),
                      ],
                    ),
                    // Pickup ID for offline
                    if (!widget.isOnline && widget.pickupId != null) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          height: 1,
                          color: Colors.grey[300],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.badge_rounded,
                                color: AppColors.warning, size: 20),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Your ID',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600)),
                                Text(widget.pickupId!,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                        letterSpacing: 2)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action message
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.isOnline
                            ? 'A driver will arrive shortly. Track your ride in real-time.'
                            : 'Listen for your pickup ID when the shuttle arrives.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Close button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Got it!',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Detail Row for Success Dialog ────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color labelColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.labelColor = AppColors.success,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: labelColor, size: 18),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }
}
