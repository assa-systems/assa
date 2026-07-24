import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/firestore_service.dart';
import 'package:assa/services/storage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/widgets/common/common_widgets.dart';

class ManageAdsScreen extends StatefulWidget {
  const ManageAdsScreen({super.key});
  @override
  State<ManageAdsScreen> createState() => _ManageAdsScreenState();
}

class _ManageAdsScreenState extends State<ManageAdsScreen> {
  final _firestore  = FirestoreService();
  final _storage    = StorageService();
  final _titleCtrl  = TextEditingController();
  final _bodyCtrl   = TextEditingController();
  final _linkCtrl   = TextEditingController();
  final _imageCtrl  = TextEditingController();

  bool  _isCreating = false;

  // Device image upload (gallery/camera) — replaces Google Drive link paste
  File? _pickedAdImage;
  bool  _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _migrateAdStats();
  }

  /// One-time migration: ensures impressions and taps fields exist on all ads.
  /// Uses set+merge so it silently skips ads that already have the fields.
  Future<void> _migrateAdStats() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('ads').get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['impressions'] == null || data['taps'] == null) {
          await doc.reference.set({
            'impressions': data['impressions'] ?? 0,
            'taps':        data['taps']        ?? 0,
          }, SetOptions(merge: true));
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _linkCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  // Convert Google Drive share link to direct image URL
  String _toDirectUrl(String url) {
    if (!url.contains('drive.google.com')) return url;
    final m = RegExp(r'(?:/file/d/|[?&]id=)([a-zA-Z0-9_-]+)').firstMatch(url);
    if (m == null) return url;
    return 'https://drive.google.com/uc?export=view&id=' + m.group(1)!;
  }

  void _showCreateAdSheet() {
    _titleCtrl.clear();
    _bodyCtrl.clear();
    _linkCtrl.clear();
    _imageCtrl.clear();
    _pickedAdImage = null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => SingleChildScrollView(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              top: 24, left: 24, right: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Align(alignment: Alignment.centerLeft,
              child: Text('Create New Ad',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 4),
            const Align(alignment: Alignment.centerLeft,
              child: Text('Fill in the fields below. Image and link are optional.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 16),

            // Title
            CustomTextField(
                label: 'Ad Title *',
                hint: 'e.g. Special Weekend Shuttle',
                controller: _titleCtrl,
                prefixIcon: Icons.campaign_rounded),
            const SizedBox(height: 12),

            // Body
            CustomTextField(
                label: 'Message / Body',
                hint: 'e.g. Shuttle now runs on Saturdays 8am-6pm',
                controller: _bodyCtrl,
                prefixIcon: Icons.message_rounded,
                maxLines: 3),
            const SizedBox(height: 12),

            // Image — picked directly from device (gallery or camera)
            const Align(alignment: Alignment.centerLeft,
              child: Text('Ad Image (optional)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickingImage ? null : () async {
                setSt(() => _pickingImage = true);
                try {
                  final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 75, maxWidth: 1600);
                  if (picked != null) {
                    setSt(() => _pickedAdImage = File(picked.path));
                  }
                } catch (_) {}
                setSt(() => _pickingImage = false);
              },
              child: Container(
                height: _pickedAdImage != null ? 150 : 56,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.adminColor, width: 1.5),
                ),
                child: _pickingImage
                    ? const Center(child: CircularProgressIndicator(
                    color: AppColors.adminColor, strokeWidth: 2))
                    : _pickedAdImage != null
                    ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(_pickedAdImage!,
                        fit: BoxFit.cover, width: double.infinity))
                    : const Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_rounded,
                          size: 20, color: AppColors.adminColor),
                      SizedBox(width: 8),
                      Text('Tap to choose photo from device',
                          style: TextStyle(fontSize: 13,
                              color: AppColors.adminColor,
                              fontWeight: FontWeight.w600)),
                    ]),
              ),
            ),
            if (_pickedAdImage != null) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setSt(() => _pickedAdImage = null),
                child: const Text('Remove photo',
                    style: TextStyle(fontSize: 11, color: AppColors.error)),
              ),
            ],
            const SizedBox(height: 12),

            // Link URL
            CustomTextField(
                label: 'Tap-through Link (optional)',
                hint: 'https://... (users tap ad to open this)',
                controller: _linkCtrl,
                prefixIcon: Icons.link_rounded,
                keyboardType: TextInputType.url),
            const SizedBox(height: 20),

            CustomButton(
              text: 'Create Ad',
              backgroundColor: AppColors.adminColor,
              isLoading: _isCreating,
              onPressed: _isCreating ? null : () async {
                if (_titleCtrl.text.trim().isEmpty) {
                  Helpers.showErrorSnackBar(context, 'Please enter an ad title.');
                  return;
                }
                setSt(() => _isCreating = true);
                final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

                // Upload picked device photo (if any) to Firebase Storage first
                String uploadedImageUrl = '';
                if (_pickedAdImage != null) {
                  final adFolderId = 'ad_${DateTime.now().millisecondsSinceEpoch}';
                  final uploadResult = await _storage.uploadAdImage(
                    imageFile: _pickedAdImage!,
                    adId: adFolderId,
                  );
                  if (uploadResult['success'] == true) {
                    uploadedImageUrl = uploadResult['url'] as String? ?? '';
                  } else if (mounted) {
                    Helpers.showErrorSnackBar(context,
                        uploadResult['error'] ?? 'Image upload failed.');
                  }
                }

                final success = await _firestore.createAd(
                  title:     _titleCtrl.text.trim(),
                  body:      _bodyCtrl.text.trim(),
                  imageUrl:  uploadedImageUrl,
                  linkUrl:   _linkCtrl.text.trim(),
                  createdBy: uid,
                );
                setSt(() => _isCreating = false);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  if (success) {
                    Helpers.showSuccessSnackBar(context, 'Ad created!');
                  } else {
                    Helpers.showErrorSnackBar(context, 'Failed to create ad.');
                  }
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _deleteAd(String adId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Ad?'),
        content: Text('Delete "$title"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await _firestore.deleteAd(adId);
      if (mounted) Helpers.showSuccessSnackBar(context, 'Ad deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateAdSheet,
        backgroundColor: AppColors.adminColor,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Ad'),
      ),
      body: SafeArea(child: Column(children: [
        _buildHeader(context),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _firestore.getAllAds(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final ads = snapshot.data ?? [];
              if (ads.isEmpty) {
                return Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.campaign_rounded,
                      size: 64, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  const Text('No ads yet',
                      style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  const Text('Tap "New Ad" to create one.',
                      style: TextStyle(fontSize: 13,
                          color: AppColors.textHint)),
                ]));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: ads.length,
                itemBuilder: (ctx, i) {
                  final ad         = ads[i];
                  final adId       = ad['id'] ?? ad['adId'] ?? '';
                  final isActive   = ad['isActive']   ?? false;
                  final title      = ad['title']      ?? 'Untitled';
                  final body       = ad['body']       ?? '';
                  final imageUrl   = ad['imageUrl']   ?? '';
                  final linkUrl    = ad['linkUrl']    ?? '';
                  final impressions = ad['impressions'] ?? 0;
                  final taps        = ad['taps']        ?? 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [BoxShadow(
                          color: AppColors.shadow, blurRadius: 6,
                          offset: const Offset(0, 2))],
                    ),
                    child: Column(children: [
                      // Image preview strip
                      if (imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(14)),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            height: 100, width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                            const SizedBox.shrink(),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.campaign_rounded,
                                color: AppColors.warning, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14,
                                    color: AppColors.textPrimary)),
                                if (body.isNotEmpty)
                                  Text(body, style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                if (linkUrl.isNotEmpty)
                                  Row(children: [
                                    const Icon(Icons.link_rounded,
                                        size: 11, color: AppColors.primary),
                                    const SizedBox(width: 3),
                                    Expanded(child: Text(linkUrl,
                                        style: const TextStyle(fontSize: 11,
                                            color: AppColors.primary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                                  ]),
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppColors.success.withOpacity(0.1)
                                        : AppColors.textHint.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isActive ? '● Active' : '○ Inactive',
                                    style: TextStyle(fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isActive
                                            ? AppColors.success
                                            : AppColors.textHint),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(children: [
                                  _StatBadge(
                                    icon: Icons.visibility_rounded,
                                    label: '$impressions views',
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  _StatBadge(
                                    icon: Icons.touch_app_rounded,
                                    label: '$taps taps',
                                    color: AppColors.accent,
                                  ),
                                ]),
                              ])),
                          Switch(
                            value: isActive,
                            activeColor: AppColors.adminColor,
                            onChanged: (val) =>
                                _firestore.toggleAdStatus(adId, val),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_rounded,
                                color: AppColors.error, size: 20),
                            onPressed: () => _deleteAd(adId, title),
                          ),
                        ]),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ])),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.adminColor,
          AppColors.adminColor.withOpacity(0.8)
        ]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(children: [
        IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white, size: 20)),
        const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Manage Ads',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                  color: Colors.white)),
          Text('Ads appear on user dashboard with image & link',
              style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12)),
        ])),
        const Icon(Icons.campaign_rounded, color: Colors.white, size: 24),
      ]),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}