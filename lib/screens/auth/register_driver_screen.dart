import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'login_screen.dart';
import 'package:assa/screens/auth/email_verification_screen.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../driver/driver_pending_screen.dart';

class RegisterDriverScreen extends StatefulWidget {
  final String googleName;
  final String googleEmail;
  final String googleUid;
  const RegisterDriverScreen({super.key, this.googleName = '', this.googleEmail = '', this.googleUid = ''});

  @override
  State<RegisterDriverScreen> createState() => _RegisterDriverScreenState();
}

class _RegisterDriverScreenState extends State<RegisterDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _shuttleIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  String _loadingMessage = 'Creating your account...';

  File? _idCardImage;
  String? _idCardUrl;
  bool _uploadingId = false;

  // ─── NEW: List of all 16 shuttles ──────────────────────────────────
  static const List<String> _allShuttleIds = [
    'AFIT-001', 'AFIT-002', 'AFIT-003', 'AFIT-004',
    'AFIT-005', 'AFIT-006', 'AFIT-007', 'AFIT-008',
    'AFIT-009', 'AFIT-010', 'AFIT-011', 'AFIT-012',
    'AFIT-013', 'AFIT-014', 'AFIT-015', 'AFIT-016',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.googleName.isNotEmpty) _nameController.text = widget.googleName;
    if (widget.googleEmail.isNotEmpty) _emailController.text = widget.googleEmail;
  }

  Future<void> _pickIdCard() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 60, maxWidth: 1024);
    if (picked == null) return;
    setState(() { _idCardImage = File(picked.path); _uploadingId = true; });
    try {
      final bytes = await File(picked.path).readAsBytes();
      _idCardUrl = 'data:image/jpeg;base64,' + base64Encode(bytes);
    } catch (_) {}
    if (mounted) setState(() => _uploadingId = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _shuttleIdController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ─── NEW: Build Shuttle Dropdown ──────────────────────────────────
  Widget _buildShuttleDropdown() {
    String? selectedShuttle = _shuttleIdController.text.trim();
    if (!_allShuttleIds.contains(selectedShuttle)) selectedShuttle = null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select Your Shuttle',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: DropdownButtonFormField<String>(
            value: selectedShuttle,
            hint: const Text('Select a shuttle...'),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              prefixIcon: Icon(Icons.directions_bus_rounded),
            ),
            items: _allShuttleIds.map((id) {
              return DropdownMenuItem(
                value: id,
                child: Text(id, style: const TextStyle(fontWeight: FontWeight.w600)),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _shuttleIdController.text = value ?? '';
              });
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please select a shuttle';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Creating your account...';
    });

    // Google user — create Firestore doc directly
    if (widget.googleUid.isNotEmpty) {
      try {
        final uid = widget.googleUid;
        final onlineUUID  = AuthService.generateOnlineUUIDStatic(uid);
        final offlineUUID = AuthService.generateOfflineUUIDStatic(uid);
        final pickupId    = await _authService.assignShortId();
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'uid':         uid,
          'name':        _nameController.text.trim(),
          'email':       widget.googleEmail,
          'role':        'driver',
          'status':      'pending',
          'phoneNumber': _phoneController.text.trim(),
          'shuttleId':   _shuttleIdController.text.trim(),
          'createdAt':   DateTime.now().toIso8601String(),
          'onlineUUID':  onlineUUID,
          'offlineUUID': offlineUUID,
          'fingerprintEnabled': false,
          'pickupId':    pickupId,
          'authProvider': 'google',
          'driverIdCardUrl': _idCardUrl ?? '',
        });
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DriverPendingScreen(status: 'pending')),
              (route) => false,
        );
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Registration failed. Please try again.'),
          backgroundColor: AppColors.error,
        ));
        return;
      }
    }

    // Email/password registration
    final tempResult = await _authService.registerDriver(
      name: _nameController.text,
      email: _emailController.text,
      password: _passwordController.text,
      phoneNumber: _phoneController.text,
      shuttleId: _shuttleIdController.text,
      driverIdCardUrl: _idCardUrl ?? '',
    );

    if (!mounted) return;

    if (!tempResult['success']) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tempResult['error'] ?? 'Registration failed.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final driver = tempResult['driver'];
    if (!mounted) return;
    setState(() => _isLoading = false);

    final driverEmail = driver.email ?? _emailController.text.trim();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => EmailVerificationScreen(email: driverEmail),
      ),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: _loadingMessage,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Driver Registration',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Your account will be reviewed by admin',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),

                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.driverLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                AppColors.driverColor.withOpacity(0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.drive_eta_rounded,
                                  color: AppColors.driverColor, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Registering as a Driver',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.driverColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        CustomTextField(
                          label: 'Full Name',
                          hint: 'Enter your full name',
                          controller: _nameController,
                          prefixIcon: Icons.person_outline_rounded,
                          validator: Validators.name,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 16),
                        CustomTextField(
                          label: 'Email Address',
                          hint: 'Enter your email',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: Icons.email_outlined,
                          validator: Validators.email,
                        ),
                        const SizedBox(height: 16),
                        CustomTextField(
                          label: 'Phone Number',
                          hint: 'e.g. 08012345678',
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          prefixIcon: Icons.phone_outlined,
                          validator: Validators.phoneNumber,
                        ),
                        const SizedBox(height: 16),
                        // ─── NEW: Shuttle Dropdown ──────────────────────
                        _buildShuttleDropdown(),
                        const SizedBox(height: 16),

                        CustomTextField(
                          label: 'Password',
                          hint: 'Create a password',
                          controller: _passwordController,
                          isPassword: true,
                          prefixIcon: Icons.lock_outline_rounded,
                          validator: Validators.password,
                        ),
                        const SizedBox(height: 16),
                        CustomTextField(
                          label: 'Confirm Password',
                          hint: 'Re-enter your password',
                          controller: _confirmPasswordController,
                          isPassword: true,
                          prefixIcon: Icons.lock_outline_rounded,
                          validator: (value) => Validators.confirmPassword(
                            value,
                            _passwordController.text,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ID Card Upload
                        const Text('ID Card Photo',
                            style: TextStyle(fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _uploadingId ? null : _pickIdCard,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 130,
                            decoration: BoxDecoration(
                              color: _idCardImage != null
                                  ? AppColors.driverColor.withOpacity(0.05)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _idCardImage != null
                                    ? AppColors.driverColor.withOpacity(0.5)
                                    : AppColors.cardBorder,
                                width: _idCardImage != null ? 2 : 1,
                              ),
                            ),
                            child: _uploadingId
                                ? const Center(child: CircularProgressIndicator(
                                color: AppColors.driverColor, strokeWidth: 2))
                                : _idCardImage != null
                                ? ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: Stack(fit: StackFit.expand, children: [
                                Image.file(_idCardImage!, fit: BoxFit.cover),
                                Positioned(
                                  bottom: 6, right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: AppColors.driverColor,
                                        borderRadius: BorderRadius.circular(6)),
                                    child: const Text('✓ Uploaded',
                                        style: TextStyle(color: Colors.white,
                                            fontSize: 10, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ]),
                            )
                                : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.badge_rounded,
                                    size: 32, color: AppColors.driverColor.withOpacity(0.6)),
                                const SizedBox(height: 8),
                                const Text('Tap to upload ID Card photo',
                                    style: TextStyle(fontSize: 13,
                                        color: AppColors.textSecondary)),
                                const SizedBox(height: 2),
                                const Text('Required for admin review',
                                    style: TextStyle(fontSize: 11,
                                        color: AppColors.textHint)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        CustomButton(
                          text: 'Submit for Review',
                          onPressed: _register,
                          isLoading: _isLoading,
                          backgroundColor: AppColors.driverColor,
                          icon: Icons.send_rounded,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Already have an account? Sign In',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.driverColor,
            AppColors.driverColor.withOpacity(0.8)
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              await AuthService().logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
              );
            },
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white, size: 20),
          ),
          const Expanded(
            child: Text(
              'Driver Registration',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}