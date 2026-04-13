import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/widgets/common/common_widgets.dart';

// ════════════════════════════════════════════════════════════════════
// PAYOUT CLAIM SCREEN
// Shown to winners after a cycle ends.
// Winner chooses:
//   • Bank Transfer — fills in bank name, account number, account name
//   • Ride Credits  — shown on dashboard only (no bank details needed)
//
// On submit: updates payout_requests/{payoutId} with choice + details.
// Admin then sees it in manage_payouts_screen.dart.
// ════════════════════════════════════════════════════════════════════

class PayoutClaimScreen extends StatefulWidget {
  final String payoutId;
  const PayoutClaimScreen({super.key, required this.payoutId});
  @override
  State<PayoutClaimScreen> createState() => _PayoutClaimScreenState();
}

class _PayoutClaimScreenState extends State<PayoutClaimScreen> {
  Map<String, dynamic>? _payout;
  bool   _loading    = true;
  bool   _submitting = false;
  String _prizeType  = 'cash'; // 'cash' | 'credits'

  final _bankNameCtrl = TextEditingController();
  final _accNumCtrl   = TextEditingController();
  final _accNameCtrl  = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPayout();
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _accNumCtrl.dispose();
    _accNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPayout() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('payout_requests')
          .doc(widget.payoutId)
          .get();
      if (mounted) {
        setState(() {
          _payout  = doc.exists ? {'id': doc.id, ...doc.data()!} : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_prizeType == 'cash') {
      if (_bankNameCtrl.text.trim().isEmpty) {
        Helpers.showErrorSnackBar(context, 'Please enter your bank name.');
        return;
      }
      if (_accNumCtrl.text.trim().length != 10) {
        Helpers.showErrorSnackBar(context, 'Account number must be 10 digits.');
        return;
      }
      if (_accNameCtrl.text.trim().isEmpty) {
        Helpers.showErrorSnackBar(context, 'Please enter your account name.');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final update = <String, dynamic>{
        'prizeType':   _prizeType,
        'claimedAt':   FieldValue.serverTimestamp(),
        'claimStatus': 'submitted',
      };

      if (_prizeType == 'cash') {
        update['bankName']      = _bankNameCtrl.text.trim();
        update['accountNumber'] = _accNumCtrl.text.trim();
        update['accountName']   = _accNameCtrl.text.trim();
      } else {
        // Mark ride credits on dashboard — write to a separate field
        // that user_dashboard listens for
        update['creditsAwarded'] = true;
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        if (uid.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('game_scores').doc(uid).set({
            'hasUnclaimedPrize': false,
            'lastPrizeType':     'credits',
            'lastPrizeAmount':   _payout?['amount'] ?? 0,
            'lastPrizeAt':       FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      await FirebaseFirestore.instance
          .collection('payout_requests')
          .doc(widget.payoutId)
          .update(update);

      if (mounted) {
        Helpers.showSuccessSnackBar(context,
            _prizeType == 'cash'
                ? 'Bank details submitted! Admin will process your payment.'
                : 'Ride credits noted! You\'ll see it on your dashboard.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        Helpers.showErrorSnackBar(context, 'Failed to submit. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _payout == null
                ? _buildNotFound()
                : _buildForm(),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 24),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF3E2000)),
        ),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Claim Your Prize 🏆',
              style: TextStyle(color: Color(0xFF3E2000), fontSize: 18,
                  fontWeight: FontWeight.w800)),
          Text('Choose how you want your winnings',
              style: TextStyle(color: Color(0xFF5D3200), fontSize: 11)),
        ])),
        const Text('🎉', style: TextStyle(fontSize: 28)),
      ]),
    );
  }

  Widget _buildNotFound() {
    return const Center(child: Text('Payout not found.',
        style: TextStyle(color: AppColors.textSecondary)));
  }

  Widget _buildForm() {
    final p        = _payout!;
    final gameType = p['gameType']  as String? ?? '';
    final rank     = p['rank']      as int?    ?? 0;
    final amount   = p['amount']    as num?    ?? 0;
    final suffix   = rank == 1 ? 'st' : rank == 2 ? 'nd' : rank == 3 ? 'rd' : 'th';
    final gameName = gameType == 'puzzle' ? 'Puzzle'
        : gameType == 'quiz' ? 'Quiz' : 'Tap Challenge';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Win summary card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFFFF8E1), Color(0xFFFFF3CD)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5)),
          ),
          child: Row(children: [
            const Text('🏆', style: TextStyle(fontSize: 40)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$rank$suffix Place — $gameName',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                      color: Color(0xFF3E2000))),
              const SizedBox(height: 6),
              Text('Prize Pool: ₦${amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                      color: Color(0xFFFFA000))),
              const SizedBox(height: 4),
              const Text('Choose below how you want to receive this',
                  style: TextStyle(fontSize: 11, color: Color(0xFF5D3200))),
            ])),
          ]),
        ),
        const SizedBox(height: 24),

        // Prize type selector
        const Text('How would you like your prize?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),

        // Cash option
        GestureDetector(
          onTap: () => setState(() => _prizeType = 'cash'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _prizeType == 'cash'
                  ? AppColors.primary.withOpacity(0.06)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _prizeType == 'cash'
                      ? AppColors.primary : AppColors.cardBorder,
                  width: _prizeType == 'cash' ? 2 : 1),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.account_balance_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bank Transfer', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
                Text('Receive cash to your Nigerian bank account',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ])),
              if (_prizeType == 'cash')
                const Icon(Icons.check_circle_rounded, color: AppColors.primary),
            ]),
          ),
        ),
        const SizedBox(height: 10),

        // Credits option
        GestureDetector(
          onTap: () => setState(() => _prizeType = 'credits'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _prizeType == 'credits'
                  ? const Color(0xFF00897B).withOpacity(0.06)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _prizeType == 'credits'
                      ? const Color(0xFF00897B) : AppColors.cardBorder,
                  width: _prizeType == 'credits' ? 2 : 1),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.stars_rounded,
                    color: Color(0xFF00897B), size: 20),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ride Credits', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
                Text('Show as a winner badge on your dashboard',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ])),
              if (_prizeType == 'credits')
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF00897B)),
            ]),
          ),
        ),
        const SizedBox(height: 24),

        // Bank details form (only for cash)
        if (_prizeType == 'cash') ...[
          const Text('Your Bank Details',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Your details are only visible to the ASSA admin.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          CustomTextField(
            label:      'Bank Name',
            hint:       'e.g. First Bank, GTBank, Opay...',
            controller: _bankNameCtrl,
            prefixIcon: Icons.account_balance_rounded,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            label:        'Account Number',
            hint:         '10-digit NUBAN',
            controller:   _accNumCtrl,
            keyboardType: TextInputType.number,
            prefixIcon:   Icons.pin_rounded,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            label:      'Account Name',
            hint:       'As it appears on your bank account',
            controller: _accNameCtrl,
            prefixIcon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 14),
              SizedBox(width: 6),
              Expanded(child: Text(
                'Admin processes payments manually. '
                    'Allow 1–3 business days after submission.',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary,
                    height: 1.4),
              )),
            ]),
          ),
          const SizedBox(height: 24),
        ] else ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF00897B).withOpacity(0.2)),
            ),
            child: const Text(
              'Your prize will appear as a winner banner on your dashboard. '
                  'No bank details needed for this option.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary,
                  height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
        ],

        CustomButton(
          text:      'Submit Claim',
          onPressed: _submitting ? null : _submit,
          isLoading: _submitting,
          icon: Icons.send_rounded,
        ),
      ],
    );
  }
}