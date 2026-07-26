import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/core/utils/validators.dart';
import 'package:assa/services/auth_service.dart';
import 'package:assa/widgets/common/common_widgets.dart';

class ManageAdminsScreen extends StatefulWidget {
  const ManageAdminsScreen({super.key});
  @override
  State<ManageAdminsScreen> createState() => _ManageAdminsScreenState();
}

class _ManageAdminsScreenState extends State<ManageAdminsScreen> {
  bool _showAddForm = false;
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isCreating = false;
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isCreating = true);
    final result = await _auth.createAdmin(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      createdByUid: _currentUid,
    );
    if (!mounted) return;
    setState(() { _isCreating = false; _showAddForm = false; });
    if (result['success'] == true) {
      _nameCtrl.clear(); _emailCtrl.clear(); _passCtrl.clear();
      Helpers.showSuccessSnackBar(context, 'Admin account created successfully!');
    } else {
      Helpers.showErrorSnackBar(context, result['error'] ?? 'Failed to create admin.');
    }
  }

  Future<void> _removeAdmin(String uid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Admin?'),
        content: Text(
          'Remove $name as an admin?\n\n'
              'Their account will be disabled. They will no longer be able to access the admin panel.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(
                color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // Mark as removed in Firestore (cannot delete Firebase Auth users from client)
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': 'removed_admin',
        'removedAt': FieldValue.serverTimestamp(),
        'removedBy': _currentUid,
      });
      if (mounted) Helpers.showSuccessSnackBar(context, '$name has been removed as admin.');
    } catch (_) {
      if (mounted) Helpers.showErrorSnackBar(context, 'Failed to remove admin. Try again.');
    }
  }

  Future<void> _reinstateAdmin(String uid, String name) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': 'admin',
        'reinstatedAt': FieldValue.serverTimestamp(),
        'reinstatedBy': _currentUid,
      });
      if (mounted) Helpers.showSuccessSnackBar(context, '$name reinstated as admin.');
    } catch (_) {
      if (mounted) Helpers.showErrorSnackBar(context, 'Failed to reinstate. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Add Admin Form ─────────────────────────────────
                if (_showAddForm) ...[
                  _buildAddForm(),
                  const SizedBox(height: 20),
                ],

                // ── Active Admins ──────────────────────────────────
                Row(children: [
                  const Text('Active Admins',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  if (!_showAddForm)
                    TextButton.icon(
                      onPressed: () => setState(() => _showAddForm = true),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Admin'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.adminColor),
                    ),
                ]),
                const SizedBox(height: 12),

                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'admin')
                      .snapshots(),
                  builder: (ctx, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator(
                          color: AppColors.adminColor));
                    }
                    final admins = snap.data!.docs;
                    if (admins.isEmpty) {
                      return _emptyState('No active admins found.');
                    }
                    return Column(
                      children: admins.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final isCurrentUser = doc.id == _currentUid;
                        return _AdminCard(
                          uid: doc.id,
                          data: data,
                          isCurrentUser: isCurrentUser,
                          isActive: true,
                          onRemove: isCurrentUser ? null : () =>
                              _removeAdmin(doc.id, data['name'] ?? 'Admin'),
                        );
                      }).toList(),
                    );
                  },
                ),

                // ── Removed Admins ─────────────────────────────────
                const SizedBox(height: 24),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'removed_admin')
                      .snapshots(),
                  builder: (ctx, snap) {
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Removed Admins',
                            style: TextStyle(fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 12),
                        ...snap.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _AdminCard(
                            uid: doc.id,
                            data: data,
                            isCurrentUser: false,
                            isActive: false,
                            onReinstate: () =>
                                _reinstateAdmin(doc.id, data['name'] ?? 'Admin'),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildAddForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.adminColor.withOpacity(0.3)),
      ),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.adminColor, size: 20),
            const SizedBox(width: 8),
            const Text('New Admin Account',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const Spacer(),
            IconButton(
              onPressed: () => setState(() => _showAddForm = false),
              icon: const Icon(Icons.close_rounded, size: 20,
                  color: AppColors.textSecondary),
            ),
          ]),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.adminColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10)),
            child: const Text(
              'The new admin will have full access to the admin panel — manage drivers, bookings, notifications, reports, and more.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.5),
            ),
          ),
          CustomTextField(
            label: 'Full Name', hint: 'Enter admin name',
            controller: _nameCtrl,
            prefixIcon: Icons.person_outline_rounded,
            validator: Validators.name,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            label: 'Email Address', hint: 'Enter email',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
            validator: Validators.email,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            label: 'Password', hint: 'Create a strong password',
            controller: _passCtrl,
            isPassword: true,
            prefixIcon: Icons.lock_outline_rounded,
            validator: Validators.password,
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _showAddForm = false),
                style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createAdmin,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.adminColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0),
                child: _isCreating
                    ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Admin',
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _emptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder)),
      child: Row(children: [
        const Icon(Icons.person_off_outlined,
            color: AppColors.textHint, size: 20),
        const SizedBox(width: 10),
        Text(message, style: const TextStyle(
            fontSize: 13, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.adminColor, AppColors.adminColor.withOpacity(0.8)]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(children: [
        IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white, size: 20)),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Manage Admins', style: TextStyle(fontSize: 18,
              fontWeight: FontWeight.w700, color: Colors.white)),
          Text('Add and remove administrator accounts',
              style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 12)),
        ])),
        const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 24),
      ]),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final bool isCurrentUser;
  final bool isActive;
  final VoidCallback? onRemove;
  final VoidCallback? onReinstate;
  const _AdminCard({
    required this.uid, required this.data, required this.isCurrentUser,
    required this.isActive, this.onRemove, this.onReinstate,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] ?? 'Admin';
    final email = data['email'] ?? '';
    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate() : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isCurrentUser
                ? AppColors.adminColor.withOpacity(0.4)
                : AppColors.cardBorder),
        boxShadow: [BoxShadow(color: AppColors.shadow,
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Stack(children: [
          Container(width: 48, height: 48,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isActive
                      ? AppColors.adminColor : AppColors.textHint).withOpacity(0.12)),
              child: Center(child: Text(Helpers.getInitials(name),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      color: isActive ? AppColors.adminColor : AppColors.textHint)))),
          if (isActive)
            Positioned(bottom: 0, right: 0,
                child: Container(width: 14, height: 14,
                    decoration: BoxDecoration(color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)))),
        ]),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary))),
            if (isCurrentUser)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.adminColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('You', style: TextStyle(fontSize: 10,
                    color: AppColors.adminColor, fontWeight: FontWeight.w700)),
              ),
          ]),
          Text(email, style: const TextStyle(fontSize: 11,
              color: AppColors.textSecondary)),
          if (createdAt != null)
            Text('Added ${Helpers.formatDateTime(createdAt)}',
                style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
        ])),
        if (onRemove != null)
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.person_remove_rounded,
                color: AppColors.error, size: 20),
            tooltip: 'Remove admin',
          ),
        if (onReinstate != null)
          TextButton(
            onPressed: onReinstate,
            style: TextButton.styleFrom(foregroundColor: AppColors.adminColor),
            child: const Text('Reinstate', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}