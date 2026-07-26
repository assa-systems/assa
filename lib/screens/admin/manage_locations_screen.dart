import 'package:flutter/material.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/firestore_service.dart';
import 'package:assa/services/esp32_service.dart';
import 'package:assa/widgets/common/common_widgets.dart';

class ManageLocationsScreen extends StatefulWidget {
  const ManageLocationsScreen({super.key});
  @override
  State<ManageLocationsScreen> createState() => _ManageLocationsScreenState();
}

class _ManageLocationsScreenState extends State<ManageLocationsScreen>
    with SingleTickerProviderStateMixin {
  final _firestore = FirestoreService();
  final _nameController = TextEditingController();
  bool _isAdding = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _addLocation(BuildContext sheetCtx) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _isAdding = true);
    final success = await _firestore.addLocation(name);
    if (mounted) {
      setState(() => _isAdding = false);
      if (success) {
        _nameController.clear();
        Navigator.pop(sheetCtx);
        Helpers.showSuccessSnackBar(context, '"$name" added!');
      } else {
        Helpers.showErrorSnackBar(context, 'Failed to add location.');
      }
    }
  }

  Future<void> _deleteLocation(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Location?'),
        content: Text('Remove "$name"? Existing bookings are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await _firestore.removeLocation(name);
      if (mounted) Helpers.showSuccessSnackBar(context, '"$name" removed.');
    }
  }

  void _showAddSheet() {
    _nameController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text('Add Online Location', style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('This location will appear for users in online mode.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              CustomTextField(label: 'Location Name', hint: 'e.g. AFIT Parade Ground',
                  controller: _nameController, prefixIcon: Icons.location_on_rounded),
              const SizedBox(height: 20),
              CustomButton(text: 'Add Location',
                  onPressed: _isAdding ? null : () => _addLocation(ctx),
                  isLoading: _isAdding, backgroundColor: AppColors.adminColor),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnlineTab = _tabController.index == 0;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: isOnlineTab
          ? FloatingActionButton(
        onPressed: _showAddSheet,
        backgroundColor: AppColors.adminColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_location_alt_rounded, size: 28),
      )
          : null,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          // Info banner
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text(
                'Online locations are dynamic — admin can add/remove them. '
                    'Offline locations are fixed campus stops in the ESP32 firmware.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.5),
              )),
            ]),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            labelColor: AppColors.adminColor,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.adminColor,
            tabs: const [
              Tab(text: 'Online Locations'),
              Tab(text: 'Offline (Fixed)'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── Dynamic online locations ────────────────────────
                StreamBuilder<List<String>>(
                  stream: _firestore.getLocationsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final locations = snapshot.data ?? [];
                    if (locations.isEmpty) {
                      return Center(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.location_off_rounded, size: 64, color: AppColors.textHint),
                          const SizedBox(height: 16),
                          const Text('No online locations yet',
                              style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          const Text('Tap the + button to add a location',
                              style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                        ]),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: locations.length,
                      itemBuilder: (ctx, i) {
                        final loc = locations[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.cardBorder),
                            boxShadow: [BoxShadow(color: AppColors.shadow,
                                blurRadius: 6, offset: const Offset(0, 2))],
                          ),
                          child: ListTile(
                            leading: Container(width: 40, height: 40,
                                decoration: BoxDecoration(
                                    color: AppColors.userColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.wifi_rounded,
                                    color: AppColors.userColor, size: 18)),
                            title: Text(loc, style: const TextStyle(fontSize: 14,
                                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            subtitle: const Text('Online mode only',
                                style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                            trailing: IconButton(
                                onPressed: () => _deleteLocation(loc),
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: AppColors.error, size: 22)),
                          ),
                        );
                      },
                    );
                  },
                ),

                // ── Static offline locations ────────────────────────
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: Esp32Service.allLocations.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == 0) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.pendingColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.pendingColor.withOpacity(0.2)),
                        ),
                        child: const Row(children: [
                          Icon(Icons.lock_outline_rounded, color: AppColors.pendingColor, size: 16),
                          SizedBox(width: 8),
                          Expanded(child: Text(
                            'These are hardcoded in the ESP32 firmware and cannot be changed here.',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
                          )),
                        ]),
                      );
                    }
                    final loc = Esp32Service.allLocations[i - 1];
                    final code = Esp32Service.getLocationCode(loc).toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cardBorder)),
                      child: ListTile(
                        leading: Container(width: 40, height: 40,
                            decoration: BoxDecoration(
                                color: AppColors.pendingColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.wifi_off_rounded,
                                color: AppColors.pendingColor, size: 18)),
                        title: Text(loc, style: const TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        subtitle: Text('Code: $code',
                            style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                        trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.pendingColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(code, style: const TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w700, color: AppColors.pendingColor))),
                      ),
                    );
                  },
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
        gradient: LinearGradient(colors: [
          AppColors.adminColor, AppColors.adminColor.withOpacity(0.8)
        ]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(children: [
        IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20)),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Manage Locations', style: TextStyle(color: Colors.white, fontSize: 18,
              fontWeight: FontWeight.w700)),
          Text('Online dynamic · Offline fixed',
              style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12)),
        ])),
        const Icon(Icons.location_on_rounded, color: Colors.white, size: 24),
      ]),
    );
  }
}