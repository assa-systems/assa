import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';

class ManageAboutScreen extends StatefulWidget {
  const ManageAboutScreen({super.key});

  @override
  State<ManageAboutScreen> createState() => _ManageAboutScreenState();
}

class _ManageAboutScreenState extends State<ManageAboutScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  String? _hodUrl;
  String? _teamUrl;

  @override
  void initState() {
    super.initState();
    _loadCurrentImages();
  }

  Future<void> _loadCurrentImages() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('about_images').get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _hodUrl = data['hod_url'];
            _teamUrl = data['team_url'];
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading about images: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadImage(String fieldName, String storagePath) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _isLoading = true);
      
      final file = File(picked.path);
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      
      await ref.putFile(file);
      final downloadUrl = await ref.getDownloadURL();
      
      await FirebaseFirestore.instance.collection('settings').doc('about_images').set({
        fieldName: downloadUrl,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          if (fieldName == 'hod_url') _hodUrl = downloadUrl;
          if (fieldName == 'team_url') _teamUrl = downloadUrl;
        });
        Helpers.showSuccessSnackBar(context, 'Image updated successfully!');
      }
    } catch (e) {
      if (mounted) Helpers.showErrorSnackBar(context, 'Failed to upload image: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteImage(String fieldName, String storagePath) async {
    setState(() => _isLoading = true);
    try {
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.delete();
      
      await FirebaseFirestore.instance.collection('settings').doc('about_images').update({
        fieldName: FieldValue.delete(),
      });

      if (mounted) {
        setState(() {
          if (fieldName == 'hod_url') _hodUrl = null;
          if (fieldName == 'team_url') _teamUrl = null;
        });
        Helpers.showSuccessSnackBar(context, 'Image removed successfully!');
      }
    } catch (e) {
      if (mounted) Helpers.showErrorSnackBar(context, 'Failed to remove image: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manage About Images'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.adminGradient),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.adminColor))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildImageSection(
                  title: 'HOD Image',
                  subtitle: 'Displayed in the Acknowledgements section',
                  currentUrl: _hodUrl,
                  fieldName: 'hod_url',
                  storagePath: 'about_images/hod.jpg',
                ),
                const SizedBox(height: 24),
                _buildImageSection(
                  title: 'Team / Inventors Image',
                  subtitle: 'Displayed in the Meet the Team section',
                  currentUrl: _teamUrl,
                  fieldName: 'team_url',
                  storagePath: 'about_images/team.jpg',
                ),
              ],
            ),
    );
  }

  Widget _buildImageSection({
    required String title,
    required String subtitle,
    required String? currentUrl,
    required String fieldName,
    required String storagePath,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            if (currentUrl != null && currentUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  currentUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                ),
              )
            else
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported_rounded, size: 40, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('No Image Selected', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: const Text('Upload'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.adminColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _uploadImage(fieldName, storagePath),
                  ),
                ),
                if (currentUrl != null && currentUrl.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_rounded, size: 18),
                      label: const Text('Remove'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                      onPressed: () => _deleteImage(fieldName, storagePath),
                    ),
                  ),
                ]
              ],
            )
          ],
        ),
      ),
    );
  }
}
