import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/models/driver_model.dart';
import 'package:assa/services/firestore_service.dart';
import 'package:assa/services/notification_service.dart';
import 'package:assa/widgets/common/common_widgets.dart';

class ManageDriversScreen extends StatefulWidget {
  const ManageDriversScreen({super.key});
  @override
  State<ManageDriversScreen> createState() => _ManageDriversScreenState();
}

class _ManageDriversScreenState extends State<ManageDriversScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _firestore = FirestoreService();
  final _notif = NotificationService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _approveDriver(DriverModel driver) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final success = await _firestore.approveDriver(
        driverUid: driver.uid, approvedByUid: adminUid);
    if (success) {
      await _notif.notifyDriverApproved(
          driverUid: driver.uid, driverName: driver.name);
      if (mounted) Helpers.showSuccessSnackBar(context, '${driver.name} approved!');
    } else {
      if (mounted) Helpers.showErrorSnackBar(context, 'Failed to approve driver.');
    }
  }

  Future<void> _rejectDriver(DriverModel driver) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Driver?'),
        content: Text('Reject ${driver.name}\'s application?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reject', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final success = await _firestore.rejectDriver(
        driverUid: driver.uid, rejectedByUid: adminUid);
    if (success) {
      await _notif.notifyDriverRejected(
          driverUid: driver.uid, driverName: driver.name);
      if (mounted) Helpers.showErrorSnackBar(context, '${driver.name} rejected.');
    } else {
      if (mounted) Helpers.showErrorSnackBar(context, 'Failed to reject driver.');
    }
  }

  void _viewFullDetails(DriverModel driver) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _DriverDetailSheet(
        driver: driver,
        onApprove: () { Navigator.pop(ctx); _approveDriver(driver); },
        onReject: () { Navigator.pop(ctx); _rejectDriver(driver); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          TabBar(
            controller: _tabController,
            labelColor: AppColors.adminColor,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.adminColor,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DriverList(
                  stream: _firestore.getPendingDrivers(),
                  emptyMsg: 'No pending applications',
                  emptyIcon: Icons.hourglass_empty_rounded,
                  onCardTap: _viewFullDetails,
                  onApprove: _approveDriver,
                  onReject: _rejectDriver,
                  showActions: true,
                ),
                _DriverList(
                  stream: _firestore.getApprovedDrivers(),
                  emptyMsg: 'No approved drivers',
                  emptyIcon: Icons.check_circle_outline_rounded,
                  onCardTap: _viewFullDetails,
                  showActions: false,
                ),
                _DriverList(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'driver')
                      .where('status', isEqualTo: 'rejected')
                      .snapshots()
                      .map((s) => s.docs.map((d) => DriverModel.fromDocument(d)).toList()),
                  emptyMsg: 'No rejected drivers',
                  emptyIcon: Icons.cancel_outlined,
                  onCardTap: _viewFullDetails,
                  showActions: false,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.adminColor, AppColors.adminColor.withOpacity(0.8)]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(children: [
        IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20)),
        const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Manage Drivers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('Tap a driver to view full details',
                  style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12)),
            ])),
        const Icon(Icons.drive_eta_rounded, color: Colors.white, size: 24),
      ]),
    );
  }
}

// ── Driver List ────────────────────────────────────────────────────────
class _DriverList extends StatelessWidget {
  final Stream<List<DriverModel>> stream;
  final String emptyMsg;
  final IconData emptyIcon;
  final bool showActions;
  final void Function(DriverModel) onCardTap;
  final void Function(DriverModel)? onApprove;
  final void Function(DriverModel)? onReject;

  const _DriverList({
    required this.stream,
    required this.emptyMsg,
    required this.emptyIcon,
    required this.showActions,
    required this.onCardTap,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DriverModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(emptyIcon, size: 56, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(emptyMsg,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.length,
          itemBuilder: (ctx, i) {
            final driver = snapshot.data![i];
            return _DriverCard(
              driver: driver,
              showActions: showActions,
              onTap: () => onCardTap(driver),
              onApprove: onApprove != null ? () => onApprove!(driver) : null,
              onReject: onReject != null ? () => onReject!(driver) : null,
            );
          },
        );
      },
    );
  }
}

// ── Driver Card (summary) ──────────────────────────────────────────────
class _DriverCard extends StatelessWidget {
  final DriverModel driver;
  final bool showActions;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _DriverCard({
    required this.driver,
    required this.showActions,
    required this.onTap,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.driverColor.withOpacity(0.12)),
              child: Center(
                  child: Text(Helpers.getInitials(driver.name),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16,
                          color: AppColors.driverColor))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(driver.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text(driver.email,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ),
            StatusBadge(status: driver.status),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _Chip(icon: Icons.phone_rounded, label: driver.phoneNumber),
            const SizedBox(width: 8),
            _Chip(icon: Icons.directions_bus_rounded, label: driver.shuttleId),
            const Spacer(),
            const Text('Tap for details',
                style: TextStyle(fontSize: 10, color: AppColors.textHint)),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 16),
          ]),
          if (showActions) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onApprove,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.driverColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Approve', style: TextStyle(color: Colors.white)),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ── Full Driver Detail Sheet ───────────────────────────────────────────
class _DriverDetailSheet extends StatelessWidget {
  final DriverModel driver;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _DriverDetailSheet({
    required this.driver,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: scrollCtrl,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Handle
              Center(
                child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),

              // Profile header
              Row(children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.driverColor.withOpacity(0.12)),
                  child: Center(
                      child: Text(Helpers.getInitials(driver.name),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800,
                              color: AppColors.driverColor))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(driver.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text(driver.email,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ]),
                ),
                StatusBadge(status: driver.status),
              ]),
              const SizedBox(height: 20),
              const Divider(color: AppColors.divider),
              const SizedBox(height: 16),

              // Details grid
              const Text('Driver Information',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              _DetailRow(label: 'Phone Number', value: driver.phoneNumber, icon: Icons.phone_rounded),
              _DetailRow(label: 'Shuttle ID', value: driver.shuttleId, icon: Icons.directions_bus_rounded),
              _DetailRow(label: 'Account Status', value: driver.status.toUpperCase(), icon: Icons.verified_user_rounded,
                  valueColor: driver.status == 'approved'
                      ? AppColors.success
                      : driver.status == 'rejected'
                      ? AppColors.error
                      : AppColors.pendingColor),
              _DetailRow(label: 'Registered',
                  value: Helpers.formatDate(driver.createdAt),
                  icon: Icons.calendar_today_rounded),
              _DetailRow(label: 'User ID', value: driver.uid, icon: Icons.fingerprint_rounded, isSmall: true),

              // Shuttle ID Image
              if (driver.driverIdCardUrl.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Shuttle ID Document',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _viewImage(context, driver.driverIdCardUrl),
                  child: Container(
                    width: double.infinity,
                    height: 180,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.cardBorder),
                        color: AppColors.surface),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: driver.driverIdCardUrl.startsWith('data:image')
                          ? Image.memory(
                        base64Decode(driver.driverIdCardUrl.split(',').last),
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, e, s) => const Center(
                            child: Icon(Icons.broken_image_rounded, color: AppColors.textHint, size: 40)),
                      )
                          : Image.network(
                        driver.driverIdCardUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) => progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (ctx, e, s) => const Center(
                            child: Icon(Icons.broken_image_rounded, color: AppColors.textHint, size: 40)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                    child: Text('Tap image to view full screen',
                        style: TextStyle(fontSize: 11, color: AppColors.textHint))),
              ],

              const SizedBox(height: 28),

              // Action buttons — always show for all statuses
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.driverColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }

  void _viewImage(BuildContext context, String url) {
    final isBase64 = url.startsWith('data:image');
    final imageWidget = isBase64
        ? Image.memory(base64Decode(url.split(',').last), fit: BoxFit.contain)
        : Image.network(url, fit: BoxFit.contain);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text('\${driver.name} — ID Card',
              style: const TextStyle(color: Colors.white, fontSize: 15)),
        ),
        body: Center(
          child: InteractiveViewer(child: imageWidget),
        ),
      ),
    ));
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color? valueColor;
  final bool isSmall;
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: isSmall ? 11 : 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppColors.textPrimary)),
          ]),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.cardBorder)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]),
    );
  }
}