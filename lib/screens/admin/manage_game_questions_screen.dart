import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/core/utils/helpers.dart';
import 'package:assa/widgets/common/common_widgets.dart';

// ════════════════════════════════════════════════════════════════════
// MANAGE GAME QUESTIONS SCREEN (Admin)
// Admin adds MCQ or True/False quiz questions.
// Questions are stored in game_questions/ collection.
// Admin can toggle active/inactive and delete questions.
// ════════════════════════════════════════════════════════════════════

class ManageGameQuestionsScreen extends StatefulWidget {
  const ManageGameQuestionsScreen({super.key});
  @override
  State<ManageGameQuestionsScreen> createState() =>
      _ManageGameQuestionsScreenState();
}

class _ManageGameQuestionsScreenState extends State<ManageGameQuestionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        backgroundColor: AppColors.adminColor,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Question',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Container(
            color: AppColors.adminColor,
            child: TabBar(
              controller:           _tab,
              indicatorColor:       Colors.white,
              labelColor:           Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(icon: Icon(Icons.list_alt_rounded, size: 16), text: 'All Questions'),
                Tab(icon: Icon(Icons.toggle_on_rounded, size: 16),  text: 'Active Only'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _QuestionsTab(activeOnly: false),
                _QuestionsTab(activeOnly: true),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.adminColor, AppColors.adminColor.withOpacity(0.85)]),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        ),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Quiz Questions', style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700)),
          Text('Add MCQ and True/False questions for the quiz game',
              style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 11)),
        ])),
        const Icon(Icons.quiz_rounded, color: Colors.white, size: 26),
      ]),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _AddQuestionSheet(),
    );
  }
}

// ── Questions list tab ────────────────────────────────────────────
class _QuestionsTab extends StatelessWidget {
  final bool activeOnly;
  const _QuestionsTab({required this.activeOnly});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance.collection('game_questions');
    if (activeOnly) query = query.where('isActive', isEqualTo: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(
              color: AppColors.adminColor));
        }
        final docs = (snap.data?.docs ?? [])
            .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
            .toList();
        // Sort by createdAt descending — client side
        docs.sort((a, b) {
          final at = a['createdAt'] as Timestamp?;
          final bt = b['createdAt'] as Timestamp?;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });

        if (docs.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.quiz_outlined, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(activeOnly ? 'No active questions' : 'No questions yet',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('Tap + Add Question to get started',
                style: TextStyle(color: AppColors.textHint, fontSize: 12)),
          ]));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: docs.length,
          itemBuilder: (_, i) => _QuestionCard(doc: docs[i]),
        );
      },
    );
  }
}

// ── Question card ─────────────────────────────────────────────────
class _QuestionCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _QuestionCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final id       = doc['id']       as String;
    final question = doc['question'] as String? ?? '';
    final type     = doc['type']     as String? ?? 'mcq';
    final answer   = doc['answer']   as String? ?? '';
    final isActive = doc['isActive'] as bool?   ?? true;
    final options  = (doc['options'] as List<dynamic>?)
        ?.map((e) => e.toString()).toList()
        ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:  AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isActive
                ? AppColors.adminColor.withOpacity(0.2)
                : AppColors.cardBorder),
        boxShadow: [BoxShadow(color: AppColors.shadow,
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (type == 'tf'
                    ? AppColors.success : AppColors.adminColor).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(type == 'tf' ? 'TRUE/FALSE' : 'MCQ',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                      color: type == 'tf' ? AppColors.success : AppColors.adminColor,
                      letterSpacing: 0.8)),
            ),
            const Spacer(),
            // Active toggle
            GestureDetector(
              onTap: () => FirebaseFirestore.instance
                  .collection('game_questions').doc(id)
                  .update({'isActive': !isActive}),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.successLight : AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isActive
                          ? AppColors.success : AppColors.divider),
                ),
                child: Text(isActive ? 'Active ✓' : 'Inactive',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: isActive ? AppColors.success : AppColors.textHint)),
              ),
            ),
            const SizedBox(width: 8),
            // Delete
            GestureDetector(
              onTap: () async {
                final ok = await showDialog<bool>(context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Text('Delete Question?'),
                      content: const Text('This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error),
                          child: const Text('Delete',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ));
                if (ok == true) {
                  await FirebaseFirestore.instance
                      .collection('game_questions').doc(id).delete();
                }
              },
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 20),
            ),
          ]),
          const SizedBox(height: 10),
          Text(question, style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4)),
          if (options.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...options.map((opt) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(opt == answer
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                    size: 14,
                    color: opt == answer ? AppColors.success : AppColors.textHint),
                const SizedBox(width: 6),
                Expanded(child: Text(opt, style: TextStyle(
                    fontSize: 12,
                    color: opt == answer ? AppColors.success : AppColors.textSecondary,
                    fontWeight: opt == answer ? FontWeight.w700 : FontWeight.w400))),
              ]),
            )),
          ],
        ]),
      ),
    );
  }
}

// ── Add Question Bottom Sheet ─────────────────────────────────────
class _AddQuestionSheet extends StatefulWidget {
  const _AddQuestionSheet();
  @override
  State<_AddQuestionSheet> createState() => _AddQuestionSheetState();
}

class _AddQuestionSheetState extends State<_AddQuestionSheet> {
  final _questionCtrl = TextEditingController();
  String _type   = 'mcq'; // 'mcq' | 'tf'
  String _answer = '';
  bool   _saving = false;

  // MCQ options (up to 4)
  final List<TextEditingController> _optionCtrls =
  List.generate(4, (_) => TextEditingController());

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = _questionCtrl.text.trim();
    if (q.isEmpty) {
      Helpers.showErrorSnackBar(context, 'Please enter a question.');
      return;
    }
    if (_answer.isEmpty) {
      Helpers.showErrorSnackBar(context, 'Please select the correct answer.');
      return;
    }

    List<String> options;
    if (_type == 'tf') {
      options = ['True', 'False'];
    } else {
      options = _optionCtrls
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (options.length < 2) {
        Helpers.showErrorSnackBar(context, 'Add at least 2 options.');
        return;
      }
      if (!options.contains(_answer)) {
        Helpers.showErrorSnackBar(context, 'The correct answer must match one of the options.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
      await FirebaseFirestore.instance.collection('game_questions').add({
        'question':  q,
        'type':      _type,
        'options':   options,
        'answer':    _answer,
        'isActive':  true,
        'addedBy':   uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Helpers.showSuccessSnackBar(context, 'Question added!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        Helpers.showErrorSnackBar(context, 'Failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Handle
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Add Quiz Question',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 20),

            // Type toggle
            const Text('Question Type', style: TextStyle(fontSize: 13,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Row(children: [
              _TypeChip('Multiple Choice', 'mcq', _type, (v) {
                setState(() { _type = v; _answer = ''; });
              }),
              const SizedBox(width: 10),
              _TypeChip('True / False', 'tf', _type, (v) {
                setState(() { _type = v; _answer = ''; });
              }),
            ]),
            const SizedBox(height: 16),

            // Question text
            CustomTextField(
              label:      'Question',
              hint:       'Enter your question here...',
              controller: _questionCtrl,
              prefixIcon: Icons.help_outline_rounded,
              maxLines:   3,
            ),
            const SizedBox(height: 16),

            // Options
            if (_type == 'mcq') ...[
              const Text('Answer Options', style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('Tap an option to mark it as correct',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              ...List.generate(4, (i) {
                final isCorrect = _optionCtrls[i].text.trim() == _answer
                    && _answer.isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () {
                        final val = _optionCtrls[i].text.trim();
                        if (val.isNotEmpty) setState(() => _answer = val);
                      },
                      child: Icon(
                        isCorrect
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isCorrect ? AppColors.success : AppColors.textHint,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(
                      controller: _optionCtrls[i],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Option ${i + 1}',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColors.inputBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: AppColors.adminColor, width: 1.5)),
                      ),
                    )),
                  ]),
                );
              }),
            ] else ...[
              // True/False
              const Text('Correct Answer', style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Row(children: ['True', 'False'].map((opt) {
                final sel = _answer == opt;
                return Expanded(child: GestureDetector(
                  onTap: () => setState(() => _answer = opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.only(right: opt == 'True' ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.success : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: sel ? AppColors.success : AppColors.inputBorder),
                    ),
                    child: Center(child: Text(opt, style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : AppColors.textPrimary))),
                  ),
                ));
              }).toList()),
            ],

            const SizedBox(height: 24),
            CustomButton(
              text:      'Save Question',
              onPressed: _saving ? null : _save,
              isLoading: _saving,
              backgroundColor: AppColors.adminColor,
              icon: Icons.save_rounded,
            ),
          ]),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label, value, selected;
  final void Function(String) onTap;
  const _TypeChip(this.label, this.value, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? AppColors.adminColor : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? AppColors.adminColor : AppColors.inputBorder),
        ),
        child: Text(label, style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w700,
            color: sel ? Colors.white : AppColors.textPrimary)),
      ),
    );
  }
}