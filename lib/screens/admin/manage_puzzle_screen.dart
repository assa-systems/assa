import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/services/storage_service.dart';
import 'package:assa/widgets/common/common_widgets.dart';



class ManagePuzzleScreen extends StatefulWidget {
  const ManagePuzzleScreen({super.key});
  @override
  State<ManagePuzzleScreen> createState() => _ManagePuzzleScreenState();
}

class _ManagePuzzleScreenState extends State<ManagePuzzleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  static String get _weekKey {
    final now    = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final week   = ((monday.difference(DateTime(monday.year, 1, 1)).inDays +
        DateTime(monday.year, 1, 1).weekday - 1) ~/ 7) + 1;
    return '${monday.year}-W$week';
  }

  static String get _monthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          Container(
            color: const Color(0xFF4A148C),
            child: TabBar(
              controller:           _tab,
              indicatorColor:       Colors.white,
              labelColor:           Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(icon: Icon(Icons.image_rounded, size: 18), text: 'Puzzle Images'),
                Tab(icon: Icon(Icons.leaderboard_rounded, size: 18), text: 'Leaderboard'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _ImagesTab(weekKey: _weekKey),
                _LeaderboardTab(weekKey: _weekKey, monthKey: _monthKey),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF6A1B9A), Color(0xFF4A148C)]),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Manage Puzzle',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            Text('Upload images · Track leaderboard · Moderate scores',
                style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 11)),
          ]),
        ),
        const Icon(Icons.extension_rounded, color: Colors.white, size: 26),
      ]),
    );
  }
}

// ======================================================================
// TAB 1: PUZZLE IMAGES
// ======================================================================
class _ImagesTab extends StatelessWidget {
  final String weekKey;
  const _ImagesTab({required this.weekKey});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.adminLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.adminColor.withOpacity(0.2)),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.chevron_right_rounded,
                color: AppColors.adminColor, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text(
              'Upload one image per grid size each week. Players see the building '
                  'name as a hint while solving. Uploading a new image automatically '
                  'deactivates the previous one for that size.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
            )),
          ]),
        ),
        const SizedBox(height: 20),
        _UploadSection(gridSize: 3, weekKey: weekKey),
        const SizedBox(height: 20),
        _UploadSection(gridSize: 4, weekKey: weekKey),
        const SizedBox(height: 28),
        const _ImageHistory(),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── Upload section for one grid size ───────────────────────────────────
class _UploadSection extends StatefulWidget {
  final int gridSize;
  final String weekKey;
  const _UploadSection({required this.gridSize, required this.weekKey});
  @override
  State<_UploadSection> createState() => _UploadSectionState();
}

class _UploadSectionState extends State<_UploadSection> {
  final _titleCtrl = TextEditingController();
  final _urlCtrl   = TextEditingController();
  final _storage   = StorageService();

  bool   _saving   = false;

  // Device image upload (gallery/camera) — replaces Google Drive link paste
  File? _pickedImage;
  bool  _pickingImage = false;

  Color  get _color => widget.gridSize == 4 ? AppColors.primary : const Color(0xFF00897B);
  String get _label => '${widget.gridSize}×${widget.gridSize}';

  @override
  void initState() {
    super.initState();
    _urlCtrl.addListener(() {
      if (mounted) setState(() => _urlValid = _urlCtrl.text.trim().length > 10);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
      if (picked != null && mounted) {
        setState(() => _pickedImage = File(picked.path));
      }
    } catch (_) {}
    if (mounted) setState(() => _pickingImage = false);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (_pickedImage == null) {
      Helpers.showErrorSnackBar(context, 'Please choose a photo from your device.');
      return;
    }
    if (title.isEmpty) {
      Helpers.showErrorSnackBar(context, 'Please enter the building / location name.');
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';

      final newRef = FirebaseFirestore.instance.collection('puzzle_images').doc();

      // Upload the device photo to Firebase Storage
      final uploadResult = await _storage.uploadPuzzleImage(
        imageFile: _pickedImage!,
        storagePath: 'puzzle_images/${widget.gridSize}/${newRef.id}.jpg',
      );
      if (uploadResult['success'] != true) {
        if (mounted) {
          setState(() => _saving = false);
          Helpers.showErrorSnackBar(context,
              uploadResult['error'] ?? 'Failed to upload image.');
        }
        return;
      }
      final imageUrl = uploadResult['url'] as String;

      final existing = await FirebaseFirestore.instance
          .collection('puzzle_images')
          .where('gridSize', isEqualTo: widget.gridSize)
          .where('isActive', isEqualTo: true)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in existing.docs) {
        batch.update(doc.reference, {'isActive': false});
      }
      batch.set(newRef, {
        'imageId':    newRef.id,
        'imageUrl':   imageUrl,
        'title':      title,
        'gridSize':   widget.gridSize,
        'gridLabel':  '${widget.gridSize}x${widget.gridSize}',
        'weekKey':    widget.weekKey,
        'isActive':   true,
        'uploadedBy': uid,
        'uploadedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (mounted) {
        setState(() { _saving = false; _urlValid = false; _pickedImage = null; });
        _titleCtrl.clear();
        _urlCtrl.clear();
        Helpers.showSuccessSnackBar(context, '$_label puzzle image saved and activated!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        Helpers.showErrorSnackBar(context, 'Failed to save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _color.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: _color.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(bottom: BorderSide(color: _color.withOpacity(0.15))),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: _color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(_label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _color))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_label Puzzle Image',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('${widget.gridSize * widget.gridSize - 1} numbered tiles',
                  style: TextStyle(fontSize: 11, color: _color)),
            ])),
            // Live active badge
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('puzzle_images')
                  .where('gridSize', isEqualTo: widget.gridSize)
                  .where('isActive', isEqualTo: true).limit(1).snapshots(),
              builder: (_, snap) {
                final active = snap.data?.docs.isNotEmpty ?? false;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? AppColors.successLight : AppColors.warningLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(active ? 'Active ✓' : 'No image',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: active ? AppColors.success : AppColors.warning)),
                );
              },
            ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Current active image
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('puzzle_images')
                  .where('gridSize', isEqualTo: widget.gridSize)
                  .where('isActive', isEqualTo: true).limit(1).snapshots(),
              builder: (_, snap) {
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return Container(
                    height: 90, margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: AppColors.background, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider)),
                    child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.image_not_supported_rounded, size: 28, color: AppColors.textHint),
                      SizedBox(height: 4),
                      Text('No active image', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                    ])),
                  );
                }
                final data  = snap.data!.docs.first.data() as Map<String, dynamic>;
                final docId = snap.data!.docs.first.id;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Current Active Image',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: data['imageUrl'] ?? '',
                      height: 140, width: double.infinity, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(height: 140, color: AppColors.surfaceVariant,
                          child: const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))),
                      errorWidget: (_, __, ___) => Container(height: 140, color: AppColors.surfaceVariant,
                          child: const Icon(Icons.broken_image_rounded, size: 36, color: AppColors.textHint)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Text(data['title'] ?? '',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                    TextButton.icon(
                      onPressed: () async {
                        final ok = await showDialog<bool>(context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: Text('Deactivate $_label Image?'),
                            content: Text('Remove "${data['title']}" from the active $_label puzzle?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Deactivate', style: TextStyle(color: AppColors.error))),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await FirebaseFirestore.instance.collection('puzzle_images')
                              .doc(docId).update({'isActive': false});
                          if (context.mounted) Helpers.showSuccessSnackBar(context, 'Image deactivated.');
                        }
                      },
                      icon: const Icon(Icons.visibility_off_rounded, size: 14, color: AppColors.error),
                      label: const Text('Deactivate', style: TextStyle(color: AppColors.error, fontSize: 12)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                    ),
                  ]),
                  const Divider(height: 24, color: AppColors.divider),
                ]);
              },
            ),

            // Set image from device
            const Text('Puzzle Photo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text(
              'Choose a photo directly from your gallery or camera.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: (_saving || _pickingImage) ? null : _pickImage,
              child: Container(
                height: _pickedImage != null ? 150 : 56,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _color, width: 1.5),
                ),
                child: _pickingImage
                    ? Center(child: CircularProgressIndicator(
                    color: _color, strokeWidth: 2))
                    : _pickedImage != null
                    ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(_pickedImage!,
                        fit: BoxFit.cover, width: double.infinity))
                    : Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_rounded,
                          size: 20, color: _color),
                      const SizedBox(width: 8),
                      Text('Tap to choose photo from device',
                          style: TextStyle(fontSize: 13,
                              color: _color, fontWeight: FontWeight.w600)),
                    ]),
              ),
            ),
            if (_pickedImage != null) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _pickedImage = null),
                child: const Text('Remove photo',
                    style: TextStyle(fontSize: 11, color: AppColors.error)),
              ),
            ],
            const SizedBox(height: 12),

            // Building name
            CustomTextField(
              label:      'Building / Location Name',
              hint:       'e.g. ICE Department, Alpha Hall...',
              controller: _titleCtrl,
              prefixIcon: Icons.apartment_rounded,
            ),
            const SizedBox(height: 14),

            const SizedBox(height: 14),
            CustomButton(
              text:            'Save & Activate',
              isLoading:       _saving,
              onPressed:       _save,
              icon:            Icons.check_circle_outline_rounded,
              backgroundColor: _color,
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── All uploaded images history ────────────────────────────────────────
class _ImageHistory extends StatelessWidget {
  const _ImageHistory();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('All Uploaded Images',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 10),
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('puzzle_images').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: AppColors.adminColor, strokeWidth: 2)));
          }
          final docs = (snap.data?.docs ?? [])..sort((a, b) {
            final at = (a.data() as Map)['uploadedAt'];
            final bt = (b.data() as Map)['uploadedAt'];
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return (bt as Timestamp).compareTo(at as Timestamp);
          });
          if (docs.isEmpty) {
            return const Padding(padding: EdgeInsets.all(16),
                child: Center(child: Text('No images uploaded yet.',
                    style: TextStyle(color: AppColors.textSecondary))));
          }
          return Column(children: docs.map((doc) {
            final d        = doc.data() as Map<String, dynamic>;
            final isActive = d['isActive'] == true;
            final gridLbl  = d['gridLabel'] ?? '?x?';
            final gs       = d['gridSize']  ?? 4;
            final title    = d['title']     ?? '';
            final imageUrl = d['imageUrl']  ?? '';
            final ts       = d['uploadedAt'];
            final date     = ts != null ? Helpers.formatDateTime((ts as Timestamp).toDate()) : '';
            final color    = gs == 4 ? AppColors.primary : const Color(0xFF00897B);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isActive ? color.withOpacity(0.4) : AppColors.cardBorder,
                    width: isActive ? 1.5 : 1),
              ),
              child: Row(children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(13)),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl, width: 72, height: 72, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(width: 72, height: 72,
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.image_rounded, color: AppColors.textHint, size: 24)),
                    errorWidget: (_, __, ___) => Container(width: 72, height: 72,
                        color: AppColors.surfaceVariant,
                        child: const Icon(Icons.broken_image_rounded, color: AppColors.textHint, size: 24)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(gridLbl, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(4)),
                          child: const Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.success)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis),
                    Text(date, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                  ]),
                )),
                // Toggle active/inactive
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: Icon(
                      isActive ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                      color: isActive ? AppColors.success : AppColors.textHint,
                      size: 32,
                    ),
                    tooltip: isActive ? 'Deactivate' : 'Activate',
                    onPressed: () async {
                      if (!isActive) {
                        final existing = await FirebaseFirestore.instance.collection('puzzle_images')
                            .where('gridSize', isEqualTo: gs).where('isActive', isEqualTo: true).get();
                        final batch = FirebaseFirestore.instance.batch();
                        for (final e in existing.docs) batch.update(e.reference, {'isActive': false});
                        batch.update(FirebaseFirestore.instance.collection('puzzle_images').doc(doc.id), {'isActive': true});
                        await batch.commit();
                        if (context.mounted) Helpers.showSuccessSnackBar(context, '"$title" activated.');
                      } else {
                        await FirebaseFirestore.instance.collection('puzzle_images').doc(doc.id).update({'isActive': false});
                        if (context.mounted) Helpers.showSuccessSnackBar(context, '"$title" deactivated.');
                      }
                    },
                  ),
                ),
              ]),
            );
          }).toList());
        },
      ),
    ]);
  }
}

// ======================================================================
// TAB 2: LEADERBOARD
// ======================================================================
class _LeaderboardTab extends StatefulWidget {
  final String weekKey, monthKey;
  const _LeaderboardTab({required this.weekKey, required this.monthKey});
  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab>
    with SingleTickerProviderStateMixin {
  late TabController _innerTab;

  @override
  void initState() {
    super.initState();
    _innerTab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _innerTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: const Color(0xFF6A1B9A).withOpacity(0.07),
        child: TabBar(
          controller:           _innerTab,
          indicatorColor:       const Color(0xFF6A1B9A),
          labelColor:           const Color(0xFF6A1B9A),
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: '3×3 Weekly'),
            Tab(text: '4×4 Weekly'),
            Tab(text: 'Monthly'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _innerTab,
          children: [
            _ScoreBoard(periodField: 'weekKey',  periodKey: widget.weekKey,  gridSize: 3),
            _ScoreBoard(periodField: 'weekKey',  periodKey: widget.weekKey,  gridSize: 4),
            _ScoreBoard(periodField: 'monthKey', periodKey: widget.monthKey, gridSize: null),
          ],
        ),
      ),
    ]);
  }
}

class _ScoreBoard extends StatelessWidget {
  final String periodField, periodKey;
  final int?   gridSize;
  const _ScoreBoard({required this.periodField, required this.periodKey, required this.gridSize});

  String _fmt(int secs) {
    final m = secs ~/ 60, s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('puzzle_scores')
        .where(periodField, isEqualTo: periodKey);
    if (gridSize != null) q = q.where('gridSize', isEqualTo: gridSize);

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A)));
        }

        var docs = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? []);

        // Monthly: keep only each user's best score across all grid sizes
        if (gridSize == null) {
          final Map<String, QueryDocumentSnapshot> best = {};
          for (final doc in docs) {
            final d = doc.data() as Map<String, dynamic>;
            final uid = d['userId'] ?? '';
            final score = d['score'] ?? 0;
            if (!best.containsKey(uid) || score > ((best[uid]!.data() as Map)['score'] ?? 0)) {
              best[uid] = doc;
            }
          }
          docs = best.values.toList();
        }

        docs.sort((a, b) => ((b.data() as Map)['score'] ?? 0).compareTo((a.data() as Map)['score'] ?? 0));

        if (docs.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.leaderboard_rounded, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              gridSize != null ? 'No ${gridSize}×${gridSize} scores this period' : 'No scores this month',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            const Text('Scores appear once players solve a puzzle.',
                style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          ]));
        }



        return Column(children: [
          // Stats strip + reset button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surfaceVariant,
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _Strip('Players',   '${docs.length}',  Icons.people_rounded,        AppColors.primary),
                _Strip('Top Score', '\$topScore pts',   Icons.emoji_events_rounded,  Colors.amber),
                _Strip('Avg Score', '\$avgScore pts',   Icons.bar_chart_rounded,     AppColors.accent),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => _confirmResetPeriod(context, docs.map((d) => d.id).toList()),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: AppColors.error),
                  label: const Text('Reset This Period',
                      style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => _confirmResetAll(context),
                  icon: const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                  label: const Text('Reset All Scores',
                      style: TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.warning),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                )),
              ]),
            ]),
          ),
          // Rows
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final doc   = docs[i];
                final d     = doc.data() as Map<String, dynamic>;
                final rank  = i + 1;
                final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '#$rank';
                final gLabel = d['gridLabel'] ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: rank <= 3 ? const Color(0xFF6A1B9A).withOpacity(0.05) : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: rank <= 3
                            ? const Color(0xFF6A1B9A).withOpacity(0.2) : AppColors.cardBorder),
                  ),
                  child: Row(children: [
                    SizedBox(width: 36,
                        child: Text(medal, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(d['userName'] ?? 'Unknown',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis)),
                        if (gLabel.isNotEmpty && gridSize == null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(4)),
                            child: Text(gLabel, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      Text('${d['moves'] ?? 0} moves  ·  ${_fmt(d['timeTaken'] ?? 0)}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${d['score'] ?? 0} pts',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF6A1B9A))),
                      GestureDetector(
                        onTap: () => _confirmDelete(context, doc.id, d['userName'] ?? 'Unknown'),
                        child: const Text('delete',
                            style: TextStyle(fontSize: 10, color: AppColors.error,
                                decoration: TextDecoration.underline, decorationColor: AppColors.error)),
                      ),
                    ]),
                  ]),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  Future<void> _confirmResetPeriod(BuildContext context, List<String> docIds) async {
    if (docIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset This Period?'),
        content: Text('Delete all ${docIds.length} score(s) for this period? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final id in docIds) {
      batch.delete(FirebaseFirestore.instance.collection('puzzle_scores').doc(id));
    }
    await batch.commit();
    if (context.mounted) Helpers.showSuccessSnackBar(context, 'Leaderboard reset for this period.');
  }

  Future<void> _confirmResetAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_rounded, color: AppColors.warning, size: 22),
          SizedBox(width: 8),
          Text('Reset ALL Scores?'),
        ]),
        content: const Text(
          'This will permanently delete every puzzle score across all periods and grid sizes. '
              'This cannot be undone.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete Everything', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('puzzle_scores').get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) batch.delete(doc.reference);
      await batch.commit();
      if (context.mounted) Helpers.showSuccessSnackBar(context, 'All puzzle scores deleted.');
    } catch (_) {
      if (context.mounted) Helpers.showErrorSnackBar(context, 'Failed to reset scores.');
    }
  }

  Future<void> _confirmDelete(BuildContext context, String docId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Score?'),
        content: Text('Remove $name\'s score from the leaderboard? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance.collection('puzzle_scores').doc(docId).delete();
      if (context.mounted) Helpers.showSuccessSnackBar(context, 'Score removed.');
    }
  }
}

Widget _Strip(String label, String value, IconData icon, Color color) {
  return Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(height: 2),
    Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
  ]);
}