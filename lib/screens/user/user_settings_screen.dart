import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/widgets/common/common_widgets.dart';
import 'package:assa/screens/user/report_screen.dart';
import 'package:assa/screens/shared/settings_screen.dart';

class UserSettingsScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final VoidCallback onLogout;
  const UserSettingsScreen({super.key, required this.userData, required this.onLogout});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  // Which panel is open
  // null | 'profile' | 'password' | 'email' | 'email_verify'
  String? _panel;
  bool _isSaving = false;

  // Profile
  late TextEditingController _nameCtrl;

  // Password change
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  // Email change — step 1: verify current password; step 2: enter new email
  final _emailPassCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();
  bool _emailPassVerified = false;
  bool _showEmailPass = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.userData?['name'] ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _emailPassCtrl.dispose();
    _newEmailCtrl.dispose();
    super.dispose();
  }

  void _resetPanels() {
    setState(() {
      _panel = null;
      _emailPassVerified = false;
      _currentPassCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      _emailPassCtrl.clear();
      _newEmailCtrl.clear();
    });
  }

  // ── Save display name ──────────────────────────────────────────────
  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      Helpers.showErrorSnackBar(context, 'Name cannot be empty.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users').doc(uid).update({'name': name});
        if (mounted) {
          setState(() { _isSaving = false; _panel = null; });
          Helpers.showSuccessSnackBar(context, 'Name updated successfully!');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        Helpers.showErrorSnackBar(context, 'Failed to update name. Try again.');
      }
    }
  }


  bool get _isGoogleUser {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'google.com');
  }

  // ── Step 1: verify current password before password change ────────
  Future<void> _verifyCurrentPassword() async {
    // Google users cannot change password here — they use Google account settings
    if (_isGoogleUser) {
      Helpers.showErrorSnackBar(context,
          'You signed in with Google. Manage your password at myaccount.google.com');
      return;
    }
    if (_currentPassCtrl.text.isEmpty) {
      Helpers.showErrorSnackBar(context, 'Enter your current password.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: _currentPassCtrl.text);
      await user.reauthenticateWithCredential(cred);
      if (mounted) setState(() { _isSaving = false; _panel = 'password_new'; });
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        final msg = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'Incorrect password. Please try again.'
            : e.code == 'requires-recent-login'
            ? 'Session expired. Please log out and log back in, then try again.'
            : 'Verification failed. Please try again.';
        Helpers.showErrorSnackBar(context, msg);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        Helpers.showErrorSnackBar(context, 'Verification failed. Try again.');
      }
    }
  }

  // ── Step 2: set new password ───────────────────────────────────────
  Future<void> _setNewPassword() async {
    final newPass = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;
    if (newPass.length < 6) {
      Helpers.showErrorSnackBar(context, 'Password must be at least 6 characters.');
      return;
    }
    if (newPass != confirm) {
      Helpers.showErrorSnackBar(context, 'Passwords do not match.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await FirebaseAuth.instance.currentUser!.updatePassword(newPass);
      if (mounted) {
        _resetPanels();
        Helpers.showSuccessSnackBar(context, 'Password changed successfully!');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        Helpers.showErrorSnackBar(context, 'Failed to change password. Please log in again and retry.');
      }
    }
  }

  // ── Step 1 of email change: verify password ────────────────────────
  Future<void> _verifyPasswordForEmail() async {
    // Google users cannot change email here
    if (_isGoogleUser) {
      Helpers.showErrorSnackBar(context,
          'You signed in with Google. Manage your email at myaccount.google.com');
      return;
    }
    if (_emailPassCtrl.text.isEmpty) {
      Helpers.showErrorSnackBar(context, 'Enter your current password to continue.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: _emailPassCtrl.text);
      await user.reauthenticateWithCredential(cred);
      if (mounted) setState(() { _isSaving = false; _emailPassVerified = true; });
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        final msg = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'Incorrect password. Please try again.'
            : e.code == 'requires-recent-login'
            ? 'Session expired. Please log out and log back in, then try again.'
            : 'Verification failed. Please try again.';
        Helpers.showErrorSnackBar(context, msg);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        Helpers.showErrorSnackBar(context, 'Verification failed. Try again.');
      }
    }
  }

  // ── Step 2 of email change: send verification to new email ─────────
  Future<void> _sendEmailChangeVerification() async {
    final newEmail = _newEmailCtrl.text.trim();
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      Helpers.showErrorSnackBar(context, 'Enter a valid email address.');
      return;
    }
    final currentEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    if (newEmail == currentEmail) {
      Helpers.showErrorSnackBar(context, 'New email is the same as current email.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      // Send verification to new email — Firebase sends a link to verify the change
      await user.verifyBeforeUpdateEmail(newEmail);
      // Update Firestore immediately (will be confirmed when user clicks link)
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .update({'email': newEmail});
      if (mounted) {
        _resetPanels();
        _showEmailSentDialog(newEmail);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        String msg = 'Failed to update email.';
        if (e.code == 'email-already-in-use') {
          msg = 'This email is already used by another account.';
        } else if (e.code == 'invalid-email') {
          msg = 'Invalid email address format.';
        }
        Helpers.showErrorSnackBar(context, msg);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        Helpers.showErrorSnackBar(context, 'Failed to update email. Try again.');
      }
    }
  }

  void _showEmailSentDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 72, height: 72,
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.mark_email_unread_rounded,
                    color: AppColors.success, size: 36)),
            const SizedBox(height: 16),
            const Text('Verify Your New Email',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              'A verification link has been sent to\n$email\n\n'
                  'Click the link in that email to confirm your new address. '
                  'Your email will update after verification.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            CustomButton(text: 'Got it', onPressed: () => Navigator.pop(ctx)),
          ]),
        ),
      ),
    );
  }

  // ── Confirm logout ─────────────────────────────────────────────────
  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out?'),
        content: const Text('Are you sure you want to sign out of your account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              widget.onLogout();
            },
            child: const Text('Log Out',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.userData?['name'] ?? 'User';
    final email = FirebaseAuth.instance.currentUser?.email
        ?? widget.userData?['email'] ?? '';
    final matric = widget.userData?['matricNumber'] ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: const BoxDecoration(
            color: Color(0xFFF5F3FF),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),

            // Profile card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1A237E), Color(0xFF283593)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFF1A237E).withOpacity(0.3),
                      blurRadius: 12, offset: const Offset(0, 5))]),
              child: Row(children: [
                Container(width: 56, height: 56,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.2),
                        border: Border.all(color: Colors.white.withOpacity(0.4))),
                    child: Center(child: Text(Helpers.getInitials(name),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                            color: Colors.white)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w800, color: Colors.white)),
                  Text(email, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
                  if (matric.isNotEmpty)
                    Text('Matric: $matric',
                        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
                ])),
              ]),
            ),

            const SizedBox(height: 20),

            // ── PANELS ──────────────────────────────────────────────

            // Edit Name
            if (_panel == 'profile') ...[
              _PanelHeader('Edit Name', onBack: _resetPanels),
              const SizedBox(height: 16),
              _buildField('Full Name', _nameCtrl, Icons.person_outline_rounded),
              const SizedBox(height: 20),
              _buildActionButtons(
                onCancel: _resetPanels,
                onSave: _isSaving ? null : _saveName,
                saveLabel: 'Save Name',
                isLoading: _isSaving,
              ),

              // Change Password — Step 1: verify current
            ] else if (_panel == 'password') ...[
              _PanelHeader('Change Password', onBack: _resetPanels),
              const SizedBox(height: 8),
              _buildStepIndicator(1, 2, 'Verify identity'),
              const SizedBox(height: 16),
              _buildPasswordField('Current Password', _currentPassCtrl,
                  _showCurrent, () => setState(() => _showCurrent = !_showCurrent)),
              const SizedBox(height: 8),
              // Forgot password link
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user?.email != null) {
                      await FirebaseAuth.instance
                          .sendPasswordResetEmail(email: user!.email!);
                      if (mounted) {
                        Helpers.showSuccessSnackBar(context,
                            'Reset link sent to ${user.email}');
                      }
                    }
                  },
                  child: const Text('Forgot password?',
                      style: TextStyle(fontSize: 12, color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 8),
              _buildActionButtons(
                onCancel: _resetPanels,
                onSave: _isSaving ? null : _verifyCurrentPassword,
                saveLabel: 'Continue',
                isLoading: _isSaving,
              ),

              // Change Password — Step 2: enter new password
            ] else if (_panel == 'password_new') ...[
              _PanelHeader('Change Password', onBack: _resetPanels),
              const SizedBox(height: 8),
              _buildStepIndicator(2, 2, 'Set new password'),
              const SizedBox(height: 16),
              _buildPasswordField('New Password', _newPassCtrl,
                  _showNew, () => setState(() => _showNew = !_showNew)),
              const SizedBox(height: 12),
              _buildPasswordField('Confirm New Password', _confirmPassCtrl,
                  _showConfirm, () => setState(() => _showConfirm = !_showConfirm)),
              // Password strength hint
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Use at least 6 characters. Mix letters and numbers for a stronger password.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              _buildActionButtons(
                onCancel: _resetPanels,
                onSave: _isSaving ? null : _setNewPassword,
                saveLabel: 'Update Password',
                isLoading: _isSaving,
              ),

              // Change Email — Step 1: verify password
            ] else if (_panel == 'email' && !_emailPassVerified) ...[
              _PanelHeader('Change Email', onBack: _resetPanels),
              const SizedBox(height: 8),
              _buildStepIndicator(1, 2, 'Confirm your identity'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3))),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.security_rounded, size: 16, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'For your security, enter your current password to proceed.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                  )),
                ]),
              ),
              const SizedBox(height: 14),
              _buildPasswordField('Current Password', _emailPassCtrl,
                  _showEmailPass, () => setState(() => _showEmailPass = !_showEmailPass)),
              const SizedBox(height: 16),
              _buildActionButtons(
                onCancel: _resetPanels,
                onSave: _isSaving ? null : _verifyPasswordForEmail,
                saveLabel: 'Verify',
                isLoading: _isSaving,
              ),

              // Change Email — Step 2: enter new email
            ] else if (_panel == 'email' && _emailPassVerified) ...[
              _PanelHeader('Change Email', onBack: _resetPanels),
              const SizedBox(height: 8),
              _buildStepIndicator(2, 2, 'Enter new email'),
              const SizedBox(height: 16),
              _buildField('New Email Address', _newEmailCtrl,
                  Icons.email_outlined,
                  keyboard: TextInputType.emailAddress),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10)),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.mark_email_unread_rounded,
                      size: 16, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'A verification link will be sent to your new email. '
                        'Click the link to confirm the change.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              _buildActionButtons(
                onCancel: _resetPanels,
                onSave: _isSaving ? null : _sendEmailChangeVerification,
                saveLabel: 'Send Verification',
                isLoading: _isSaving,
              ),

              // ── Main menu ──────────────────────────────────────────
            ] else ...[
              _SettingTile(
                icon: Icons.badge_outlined,
                label: 'Edit Name',
                subtitle: widget.userData?['name'] ?? 'Update your display name',
                onTap: () => setState(() => _panel = 'profile'),
              ),
              _SettingTile(
                icon: Icons.email_outlined,
                label: 'Change Email',
                subtitle: FirebaseAuth.instance.currentUser?.email ?? 'Update your email',
                onTap: () => setState(() { _panel = 'email'; _emailPassVerified = false; }),
              ),
              _SettingTile(
                icon: Icons.lock_outline_rounded,
                label: 'Change Password',
                subtitle: 'Update your login password',
                onTap: () => setState(() => _panel = 'password'),
              ),
              const Divider(color: AppColors.divider, height: 24),
              _SettingTile(
                icon: Icons.tune_rounded,
                label: 'App Settings',
                subtitle: 'Theme & about ASSA',
                onTap: () {
                  // Capture navigator before closing the bottom sheet
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(
                      builder: (_) => const SettingsScreen()));
                },
              ),
              _SettingTile(
                icon: Icons.report_problem_outlined,
                label: 'Report Shuttle',
                subtitle: 'Submit a complaint to admin',
                color: AppColors.error,
                onTap: () {
                  // Capture navigator before closing the bottom sheet
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(
                      builder: (_) => ReportScreen(userData: widget.userData)));
                },
              ),
              _SettingTile(
                icon: Icons.logout_rounded,
                label: 'Log Out',
                subtitle: 'Sign out of your account',
                color: AppColors.error,
                onTap: _confirmLogout,
              ),
            ],

            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, IconData icon,
      {TextInputType keyboard = TextInputType.text}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController ctrl,
      bool show, VoidCallback toggle) {
    return TextFormField(
      controller: ctrl,
      obscureText: !show,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded,
            size: 20, color: AppColors.textSecondary),
        suffixIcon: IconButton(
          icon: Icon(show ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 20, color: AppColors.textSecondary),
          onPressed: toggle,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildStepIndicator(int current, int total, String label) {
    return Row(children: [
      ...List.generate(total, (i) {
        final active = i < current;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
      const SizedBox(width: 10),
      Text('Step $current of $total',
          style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
    ]);
  }

  Widget _buildActionButtons({
    required VoidCallback onCancel,
    required VoidCallback? onSave,
    required String saveLabel,
    required bool isLoading,
  }) {
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.inputBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton(
          onPressed: onSave,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0),
          child: isLoading
              ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(saveLabel,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

// ── Panel header with back arrow ───────────────────────────────────────
class _PanelHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _PanelHeader(this.title, {required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_rounded,
              size: 18, color: AppColors.textPrimary)),
      Text(title, style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
    ]);
  }
}

// ── Settings list tile ─────────────────────────────────────────────────
class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color? color;
  final VoidCallback onTap;
  const _SettingTile({required this.icon, required this.label,
    required this.subtitle, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(width: 38, height: 38,
          decoration: BoxDecoration(color: c.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: c, size: 18)),
      title: Text(label, style: TextStyle(fontSize: 14,
          fontWeight: FontWeight.w600, color: c)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded,
          color: c.withOpacity(0.5), size: 20),
      onTap: onTap,
    );
  }
}
