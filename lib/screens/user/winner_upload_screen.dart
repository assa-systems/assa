import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/widgets/common/common_widgets.dart';

// ════════════════════════════════════════════════════════════════════
// WINNER UPLOAD SCREEN
//
// When a user wins "Face of the Week" (top scorer across all games),
// they are asked to:
//   • Upload a photo (camera or gallery)
//   • Enter department / matric number
//   • Share hobbies
//   • Share "What do you do while waiting for the shuttle?"
//
// Data saved to winners/{weekKey} collection.
// Displayed on Game Hub and User Dashboard as a hero banner.
// ════════════════════════════════════════════════════════════════════

class WinnerUploadScreen extends StatefulWidget {
  final int totalScore;
  final Map<String, int> gameScores; // {'puzzle': x, 'quiz': y, 'tap': z}
  const WinnerUploadScreen({
    super.key,
    required this.totalScore,
    required this.gameScores,
  });

  @override
  State<WinnerUploadScreen> createState() => _WinnerUploadScreenState();
}

class _WinnerUploadScreenState extends State<WinnerUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _deptCtrl = TextEditingController();
  final _matricCtrl = TextEditingController();
  final _hobbiesCtrl = TextEditingController();
  final _waitingHabitCtrl = TextEditingController();

  File? _imageFile;
  bool _isUploading = false;
  bool _isLoading = true;
  String? _userName;
  String? _userEmail;

  static String get _weekKey {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final week = ((monday.difference(DateTime(monday.year, 1, 1)).inDays +
        DateTime(monday.year, 1, 1).weekday - 1) ~/ 7) + 1;
    return '${monday.year}-W$week';
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _deptCtrl.dispose();
    _matricCtrl.dispose();
    _hobbiesCtrl.dispose();
    _waitingHabitCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (mounted) {
        setState(() {
          _userName = doc.data()?['name'] ?? 'User';
          _userEmail = doc.data()?['email'] ?? '';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 800);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _showImagePicker() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Upload Photo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _PickerOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  _PickerOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageFile == null) {
      Helpers.showErrorSnackBar(context, 'Please upload a photo');
      return;
    }

    setState(() => _isUploading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Not logged in');

      // Upload image to Firebase Storage
      final weekKey = _weekKey;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('winners')
          .child('$weekKey')
          .child('$uid.jpg');
      await storageRef.putFile(_imageFile!);
      final photoUrl = await storageRef.getDownloadURL();

      // Save winner document
      await FirebaseFirestore.instance
          .collection('winners')
          .doc(weekKey)
          .set({
        'weekKey': weekKey,
        'userId': uid,
        'userName': _userName,
        'userEmail': _userEmail,
        'photoUrl': photoUrl,
        'department': _deptCtrl.text.trim(),
        'matricNumber': _matricCtrl.text.trim(),
        'hobbies': _hobbiesCtrl.text.trim(),
        'waitingHabit': _waitingHabitCtrl.text.trim(),
        'totalScore': widget.totalScore,
        'gameScores': widget.gameScores,
        'declaredAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Helpers.showSuccessSnackBar(
            context, '🎉 You are now the Face of the Week!');
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        Helpers.showErrorSnackBar(context, 'Failed to submit. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('You Won! 🏆'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Congratulatory message
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 8),
                    Text('Congratulations $_userName!',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF3E2000))),
                    const SizedBox(height: 4),
                    Text('You are the Face of the Week!',
                        style: const TextStyle(
                            fontSize: 14, color: Color(0xFF5D3200))),
                    const SizedBox(height: 8),
                    Text('Total Score: ${widget.totalScore} pts',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3E2000))),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Photo upload
              const Text('Upload Your Photo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showImagePicker,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(60),
                    border: Border.all(
                        color: AppColors.primary, width: 2),
                  ),
                  child: _imageFile != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(60),
                    child: Image.file(_imageFile!, fit: BoxFit.cover),
                  )
                      : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_rounded,
                          size: 32, color: AppColors.textSecondary),
                      const SizedBox(height: 4),
                      Text('Tap to add',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Form fields
              CustomTextField(
                label: 'Department / Faculty',
                hint: 'e.g. Engineering, Computer Science...',
                controller: _deptCtrl,
                prefixIcon: Icons.business_rounded,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Matric Number',
                hint: 'e.g. AFIT/2020/001',
                controller: _matricCtrl,
                prefixIcon: Icons.badge_rounded,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'Hobbies',
                hint: 'e.g. Reading, Football, Coding...',
                controller: _hobbiesCtrl,
                prefixIcon: Icons.favorite_rounded,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                label: 'What do you do while waiting for the shuttle?',
                hint: 'e.g. Study, Listen to music, Chat with friends...',
                controller: _waitingHabitCtrl,
                prefixIcon: Icons.timer_rounded,
                maxLines: 2,
              ),
              const SizedBox(height: 24),

              // Submit button
              CustomButton(
                text: _isUploading ? 'Submitting...' : 'Claim Face of the Week',
                onPressed: _isUploading ? null : _submit,
                isLoading: _isUploading,
                icon: Icons.emoji_events_rounded,
                backgroundColor: const Color(0xFFFFD700),
                textColor: const Color(0xFF3E2000),
              ),
              const SizedBox(height: 16),
              Text(
                'Your photo and details will be displayed on the Game Hub and Dashboard for the entire week.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}