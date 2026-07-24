// admin_chat_screen.dart (full file with image support)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:assa/core/utils/helpers.dart';

// ======================================================================
// ADMIN PRIVATE MESSAGES + SUPPORT CHAT VIEWER
// Tabs: Users | Drivers | Support (complaint panel chats)
// ======================================================================

// ── Colour palette ─────────────────────────────────────────────────────
const _kAdminGrad   = [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFF9C27B0)];
const _kDriverGrad  = [Color(0xFF0D47A1), Color(0xFF1565C0)];
const _kSupportGrad = [Color(0xFF004D40), Color(0xFF00695C)];
const _kUserColor   = Color(0xFF7B1FA2);
const _kDriverColor = Color(0xFF1565C0);
const _kSupportColor= Color(0xFF00695C);

class AdminChatScreen extends StatefulWidget {
  final String? preOpenUserId;
  final String? preOpenUserName;
  const AdminChatScreen({super.key, this.preOpenUserId, this.preOpenUserName});
  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    if (widget.preOpenUserId != null && widget.preOpenUserId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _SupportChatViewer(
            chatId:   'support_${widget.preOpenUserId}',
            userName: widget.preOpenUserName ?? 'Finder',
            userId:   widget.preOpenUserId!,
          ),
        ));
      });
    }
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F0F8),
      body: SafeArea(child: Column(children: [
        _Header(onBack: () => Navigator.pop(context)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                  blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: TextField(
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search name or email...',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.grey, size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07),
                  blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: TabBar(
              controller: _tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700),
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                    colors: _kAdminGrad,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [BoxShadow(
                    color: const Color(0xFF7B1FA2).withOpacity(0.4),
                    blurRadius: 6, offset: const Offset(0, 2))],
              ),
              tabs: const [
                Tab(text: 'Users'),
                Tab(text: 'Drivers'),
                Tab(text: '🛡️ Support'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: TabBarView(controller: _tab, children: [
          _PersonList(role: 'user',    search: _search),
          _PersonList(role: 'driver',  search: _search),
          _SupportList(search: _search),
        ])),
      ])),
    );
  }
}

// ── Gradient header ────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: _kAdminGrad,
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black26,
            blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 14),
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.15),
              border: Border.all(color: Colors.white30, width: 1.5),
            ),
            child: const Center(child: Icon(Icons.chat_bubble_rounded,
                color: Colors.white, size: 22)),
          ),
          Positioned(right: -2, bottom: -2,
            child: Container(
              width: 16, height: 16,
              decoration: const BoxDecoration(
                  color: Color(0xFF69F0AE), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 10),
            ),
          ),
        ]),
        const SizedBox(width: 12),
        const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Private Messages', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800,
              color: Colors.white, letterSpacing: 0.2)),
          SizedBox(height: 2),
          Text('Warn · Congratulate · View complaints',
              style: TextStyle(fontSize: 11, color: Colors.white70)),
        ])),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('support_chats').snapshots(),
          builder: (_, snap) {
            final count = snap.data?.docs.length ?? 0;
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$count', style: const TextStyle(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w900)),
                const Text('chats', style: TextStyle(
                    color: Colors.white70, fontSize: 9)),
              ]),
            );
          },
        ),
      ]),
    );
  }
}

// ── User / Driver list ─────────────────────────────────────────────────
class _PersonList extends StatelessWidget {
  final String role, search;
  const _PersonList({required this.role, required this.search});

  @override
  Widget build(BuildContext context) {
    Query q = FirebaseFirestore.instance.collection('users')
        .where('role', isEqualTo: role);
    if (role == 'driver') q = q.where('status', isEqualTo: 'approved');

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: _kUserColor));

        final docs = snap.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final n = (data['name']  ?? '').toString().toLowerCase();
          final e = (data['email'] ?? '').toString().toLowerCase();
          return search.isEmpty || n.contains(search) || e.contains(search);
        }).toList();

        if (docs.isEmpty) return _EmptyState(
            icon: Icons.people_outline_rounded,
            label: 'No ${role}s found');

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data    = docs[i].data() as Map<String, dynamic>;
            final uid     = data['uid'] ?? data['userId'] ?? docs[i].id;
            final name    = data['name']     ?? 'Unknown';
            final email   = data['email']    ?? '';
            final shuttle = data['shuttleId']?? '';
            return _PersonTile(uid: uid, name: name,
                email: email, role: role, shuttle: shuttle);
          },
        );
      },
    );
  }
}

class _PersonTile extends StatelessWidget {
  final String uid, name, email, role, shuttle;
  const _PersonTile({required this.uid, required this.name,
    required this.email, required this.role, required this.shuttle});

  @override
  Widget build(BuildContext context) {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final chatId   = _sortedChatId(adminUid, uid);
    final isDriver = role == 'driver';
    final grad     = isDriver ? _kDriverGrad
        : [_kUserColor, const Color(0xFF9C27B0)];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('private_chats').doc(chatId)
          .collection('messages')
          .where('isAdmin', isEqualTo: false)
          .where('read',    isEqualTo: false)
          .snapshots(),
      builder: (_, unreadSnap) {
        final unread = unreadSnap.data?.docs.length ?? 0;
        return GestureDetector(
          onTap: () {
            if (role == 'user') {
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _SupportChatViewer(
                      chatId: 'support_$uid',
                      userName: name, userId: uid)));
            } else {
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _ChatRoom(targetUid: uid,
                      targetName: name, targetRole: role)));
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: grad,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(
                      color: grad.last.withOpacity(0.35),
                      blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Center(child: Text(
                  Helpers.getInitials(name),
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 16),
                )),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E))),
                const SizedBox(height: 2),
                Text(
                  isDriver && shuttle.isNotEmpty
                      ? '🚌 $shuttle · $email' : email,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ])),
              const SizedBox(width: 8),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFE53935), Color(0xFFB71C1C)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Text('$unread', style: const TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w800)),
                )
              else
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: grad.first.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chevron_right_rounded,
                      color: grad.first, size: 18),
                ),
            ]),
          ),
        );
      },
    );
  }
}

// ── Support / complaint chat list ──────────────────────────────────────
class _SupportList extends StatelessWidget {
  final String search;
  const _SupportList({required this.search});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('support_chats').snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(
            child: CircularProgressIndicator(color: _kSupportColor));

        final docs = snap.data!.docs;
        if (docs.isEmpty) return _EmptyState(
            icon: Icons.support_agent_rounded,
            label: 'No support conversations yet');

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final chatId = docs[i].id;
            final uid    = chatId.replaceFirst('support_', '');
            return _SupportTile(chatId: chatId, userId: uid);
          },
        );
      },
    );
  }
}

class _SupportTile extends StatelessWidget {
  final String chatId, userId;
  const _SupportTile({required this.chatId, required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users').doc(userId).get(),
      builder: (_, userSnap) {
        final userData  = userSnap.data?.data() as Map<String, dynamic>?;
        final name      = userData?['name'] ?? 'User';
        final email     = userData?['email'] ?? '';

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('support_chats').doc(chatId)
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .limit(1)
              .snapshots(),
          builder: (_, msgSnap) {
            final lastMsg   = msgSnap.data?.docs.isNotEmpty == true
                ? (msgSnap.data!.docs.first.data()
            as Map<String, dynamic>)['text'] ?? ''
                : 'No messages yet';
            final isBot     = msgSnap.data?.docs.isNotEmpty == true
                ? (msgSnap.data!.docs.first.data()
            as Map<String, dynamic>)['isBot'] == true
                : false;

            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _SupportChatViewer(
                      chatId: chatId, userName: name, userId: userId))),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: _kSupportGrad,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                    ),
                    child: Center(child: Text(
                      Helpers.getInitials(name),
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w800, fontSize: 16),
                    )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E))),
                        const SizedBox(height: 3),
                        Row(children: [
                          if (isBot)
                            const Text('🛡️ ', style: TextStyle(fontSize: 10)),
                          Expanded(child: Text(
                            lastMsg,
                            style: const TextStyle(fontSize: 11,
                                color: Colors.grey),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          )),
                        ]),
                      ])),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _kSupportColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.visibility_rounded,
                        color: _kSupportColor, size: 18),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Support chat viewer ────────────────────────────────────────────────
class _SupportChatViewer extends StatefulWidget {
  final String chatId, userName, userId;
  const _SupportChatViewer({required this.chatId, required this.userName,
    required this.userId});
  @override
  State<_SupportChatViewer> createState() => _SupportChatViewerState();
}

class _SupportChatViewerState extends State<_SupportChatViewer> {
  final _msgCtrl  = TextEditingController();
  final _scroll   = ScrollController();
  bool  _sending  = false;
  bool  _isPrivate = false;

  String get _adminUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference get _messages => FirebaseFirestore.instance
      .collection('support_chats').doc(widget.chatId)
      .collection('messages');

  @override
  void dispose() { _msgCtrl.dispose(); _scroll.dispose(); super.dispose(); }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('users').doc(_adminUid).get();
      final adminName = adminDoc.data()?['name'] ?? 'Admin';
      await _messages.add({
        'senderId':   _adminUid,
        'senderName': adminName,
        'text':       text,
        'isBot':      false,
        'isAdmin':    true,
        'isPrivate':  _isPrivate,
        'timestamp':  FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId':    widget.userId,
        'title':     _isPrivate
            ? '🔒 Private message from Admin'
            : 'Admin replied to your complaint',
        'body':      text.length > 80
            ? '${text.substring(0, 80)}...' : text,
        'type':      'admin_chat',
        'read':      false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _msgCtrl.clear();
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      body: SafeArea(child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: _kSupportGrad,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black26,
                blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 19),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2)),
              child: Center(child: Text(
                Helpers.getInitials(widget.userName),
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 14),
              )),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.userName, style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: Colors.white)),
              const Text('Support & Complaints thread',
                  style: TextStyle(fontSize: 10, color: Colors.white70)),
            ])),
          ]),
        ),

        // Messages
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _messages
                .orderBy('timestamp', descending: false).snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const Center(
                  child: CircularProgressIndicator(color: _kSupportColor));
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Center(
                  child: Text('No messages yet',
                      style: TextStyle(color: Colors.grey)));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d         = docs[i].data() as Map<String, dynamic>;
                  final isAdmin   = d['isAdmin']   == true;
                  final isBot     = d['isBot']     == true;
                  final isPrivate = d['isPrivate'] == true;
                  final text      = d['text']      ?? '';
                  final image     = d['image']     ?? '';  // image field
                  final sender    = d['senderName'] ?? '';
                  final ts        = d['timestamp']  as Timestamp?;
                  final time      = ts != null
                      ? TimeOfDay.fromDateTime(ts.toDate()).format(context)
                      : '';
                  return _SupportBubble(
                      text: text,
                      image: image,
                      sender: sender,
                      time: time,
                      isAdmin: isAdmin,
                      isBot: isBot,
                      isPrivate: isPrivate);
                },
              );
            },
          ),
        ),

        // Reply bar
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12,
                blurRadius: 6, offset: Offset(0, -2))],
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(children: [
                _ModeChip(
                  label: '💬 Reply',
                  selected: !_isPrivate,
                  onTap: () => setState(() => _isPrivate = false),
                  activeColor: const Color(0xFF004D40),
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: '🔒 Private',
                  selected: _isPrivate,
                  onTap: () => setState(() => _isPrivate = true),
                  activeColor: const Color(0xFFE65100),
                ),
                const Spacer(),
                if (_isPrivate)
                  const Text('User sees 🔒 badge',
                      style: TextStyle(fontSize: 10,
                          color: Color(0xFFE65100))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                        color: _isPrivate
                            ? const Color(0xFFFFF3E0)
                            : const Color(0xFFF0F4F0),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _isPrivate
                            ? const Color(0xFFFFCC80)
                            : Colors.grey.shade200)),
                    child: TextField(
                      controller: _msgCtrl,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _isPrivate
                            ? '🔒 Private message...'
                            : 'Reply to complaint...',
                        hintStyle: const TextStyle(
                            color: Colors.grey, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sending ? null : _send,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: _sending ? null : LinearGradient(
                          colors: _isPrivate
                              ? [const Color(0xFFE65100),
                            const Color(0xFFEF6C00)]
                              : [const Color(0xFF004D40),
                            const Color(0xFF00695C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      color: _sending ? Colors.grey.shade300 : null,
                      shape: BoxShape.circle,
                      boxShadow: _sending ? [] : [BoxShadow(
                          color: (_isPrivate
                              ? const Color(0xFFE65100)
                              : const Color(0xFF004D40)).withOpacity(0.4),
                          blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: _sending
                        ? const Padding(padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                        : Icon(_isPrivate
                        ? Icons.lock_rounded
                        : Icons.send_rounded,
                        color: Colors.white, size: 19),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ])),
    );
  }
}

// ── Mode toggle chip ───────────────────────────────────────────────────
class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;
  const _ModeChip({required this.label, required this.selected,
    required this.onTap, required this.activeColor});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? activeColor : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: selected ? activeColor : Colors.grey.shade300),
        boxShadow: selected ? [BoxShadow(
            color: activeColor.withOpacity(0.3),
            blurRadius: 6, offset: const Offset(0, 2))] : [],
      ),
      child: Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: selected ? Colors.white : Colors.grey.shade600)),
    ),
  );
}

// ── Support Bubble with image support ─────────────────────────────────
class _SupportBubble extends StatelessWidget {
  final String text, image, sender, time;
  final bool isAdmin, isBot, isPrivate;
  const _SupportBubble({
    required this.text,
    this.image = '',
    required this.sender,
    required this.time,
    required this.isAdmin,
    required this.isBot,
    this.isPrivate = false,
  });

  @override
  Widget build(BuildContext context) {
    final isRight = isAdmin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isRight
            ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isRight) ...[
            Container(
              width: 30, height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isBot
                      ? [const Color(0xFF004D40), const Color(0xFF00897B)]
                      : [const Color(0xFF1A237E), const Color(0xFF3949AB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(child: Text(isBot ? '🛡️' : '👤',
                  style: const TextStyle(fontSize: 12))),
            ),
          ],
          Flexible(child: Column(
            crossAxisAlignment: isRight
                ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isRight)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 3),
                  child: Text(
                    isBot ? 'ASSA Bot' : sender,
                    style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isBot ? _kSupportColor
                            : const Color(0xFF1A237E)),
                  ),
                ),
              // Display image if present
              if (image.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: image.startsWith('data:image')
                      ? Image.memory(
                    base64Decode(image.split(',').last),
                    height: 150,
                    width: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, size: 40),
                  )
                      : Image.network(
                    image,
                    height: 150,
                    width: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, size: 40),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isRight
                      ? const LinearGradient(
                      colors: _kSupportGrad,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)
                      : null,
                  color: isRight ? null : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft:     const Radius.circular(18),
                    topRight:    const Radius.circular(18),
                    bottomLeft:  Radius.circular(isRight ? 18 : 4),
                    bottomRight: Radius.circular(isRight ? 4 : 18),
                  ),
                  boxShadow: [BoxShadow(
                      color: isRight
                          ? _kSupportColor.withOpacity(0.3)
                          : Colors.black.withOpacity(0.06),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Text(text, style: TextStyle(
                    fontSize: 13.5,
                    color: isRight ? Colors.white
                        : const Color(0xFF1A1A2E),
                    height: 1.45)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Text(time, style: const TextStyle(
                    fontSize: 9.5, color: Colors.grey)),
              ),
            ],
          )),
        ],
      ),
    );
  }
}

// ── Private chat room ────────────────────────────────────────────────────
class _ChatRoom extends StatefulWidget {
  final String targetUid, targetName, targetRole;
  const _ChatRoom({required this.targetUid, required this.targetName,
    required this.targetRole});
  @override
  State<_ChatRoom> createState() => _ChatRoomState();
}

class _ChatRoomState extends State<_ChatRoom> {
  final _msgCtrl = TextEditingController();
  final _scroll  = ScrollController();
  bool  _sending = false;

  String get _adminUid  => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _chatId    => _sortedChatId(_adminUid, widget.targetUid);
  String get _collection => 'private_chats';
  String get _docId      => _chatId;

  CollectionReference get _messages => FirebaseFirestore.instance
      .collection(_collection).doc(_docId).collection('messages');

  static const List<Map<String, String>> _templates = [
    {'label': '⚠️ Warning',
      'text':  'This is an official warning regarding your conduct on the ASSA platform. '
          'Please review the shuttle usage rules to avoid suspension.'},
    {'label': '🎉 Congrats',
      'text':  'Congratulations! Your honesty in returning a found item has been noted. '
          'Thank you for making ASSA better for everyone.'},
    {'label': '📋 Rules',
      'text':  'Reminder: Please follow all ASSA shuttle guidelines. '
          'Misuse may result in account suspension.'},
    {'label': '✅ Item Ready',
      'text':  'Your lost item has been recovered and is ready for pickup. '
          'Please contact the admin to arrange collection.'},
    {'label': '🚌 Ride Credit',
      'text':  'A complimentary ride credit has been added to your account '
          'as a reward for returning a found item.'},
  ];

  @override
  void initState() {
    super.initState();
    _markRead();
  }

  @override
  void dispose() { _msgCtrl.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _markRead() async {
    final unread = await _messages
        .where('isAdmin', isEqualTo: false)
        .where('read',    isEqualTo: false).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in unread.docs) batch.update(d.reference, {'read': true});
    await batch.commit();
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _msgCtrl.text).trim();
    if (msg.isEmpty) return;
    setState(() => _sending = true);
    try {
      final adminDoc  = await FirebaseFirestore.instance
          .collection('users').doc(_adminUid).get();
      final adminName = adminDoc.data()?['name'] ?? 'Admin';
      await _messages.add({
        'senderId':   _adminUid,
        'senderName': adminName,
        'text':       msg,
        'isAdmin':    true,
        'read':       false,
        'timestamp':  FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId':    widget.targetUid,
        'title':     'Message from Admin',
        'body':      msg.length > 80 ? '${msg.substring(0, 80)}...' : msg,
        'type':      'admin_chat',
        'chatId':    _chatId,
        'isRead':    false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _msgCtrl.clear();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
      });
    } catch (e) {
      if (mounted) Helpers.showErrorSnackBar(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.targetRole == 'driver';
    final grad     = isDriver ? _kDriverGrad
        : [_kUserColor, const Color(0xFF9C27B0)];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F0F8),
      body: SafeArea(child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: grad,
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20)),
            boxShadow: const [BoxShadow(color: Colors.black26,
                blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 19),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2)),
              child: Center(child: Text(
                Helpers.getInitials(widget.targetName),
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 14),
              )),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.targetName, style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: Colors.white)),
              Text(
                  isDriver
                      ? 'DRIVER · Private Chat'
                      : '🔒 Private Contact — not in complaint panel',
                  style: const TextStyle(fontSize: 10,
                      color: Colors.white70)),
            ])),
          ]),
        ),

        // Private notice
        if (!isDriver)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 9),
            color: const Color(0xFFFFF3E0),
            child: const Row(children: [
              Icon(Icons.lock_person_rounded,
                  color: Color(0xFFE65100), size: 15),
              SizedBox(width: 8),
              Expanded(child: Text(
                'This is a private thread. The user sees these messages in their Admin Inbox, separate from their Complaint Panel.',
                style: TextStyle(fontSize: 11,
                    color: Color(0xFFBF360C), height: 1.4),
              )),
            ]),
          ),

        // Quick templates
        Container(
          height: 46,
          color: Colors.white,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            itemCount: _templates.length,
            itemBuilder: (_, i) {
              final t = _templates[i];
              return GestureDetector(
                onTap: () => _send(t['text']),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: grad,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(
                        color: grad.last.withOpacity(0.3),
                        blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Text(t['label']!, style: const TextStyle(
                      fontSize: 11, color: Colors.white,
                      fontWeight: FontWeight.w700)),
                ),
              );
            },
          ),
        ),

        // Messages
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _messages
                .orderBy('timestamp', descending: false).snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const Center(
                  child: CircularProgressIndicator(
                      color: _kUserColor));

              final docs = snap.data!.docs;
              if (docs.isEmpty) return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 48,
                      color: Colors.grey.withOpacity(0.3)),
                  const SizedBox(height: 10),
                  const Text('No messages yet',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 4),
                  const Text('Use a template or type below',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              );

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });

              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d    = docs[i].data() as Map<String, dynamic>;
                  final isMe = d['isAdmin'] == true;
                  final text = d['text']    ?? '';
                  final image = d['image']  ?? '';
                  final sender = d['senderName'] ?? '';
                  final ts   = d['timestamp'] as Timestamp?;
                  final time = ts != null
                      ? TimeOfDay.fromDateTime(ts.toDate()).format(context)
                      : '';
                  return _PrivateBubble(
                      text: text,
                      image: image,
                      time: time,
                      isMe: isMe,
                      sender: sender,
                      grad: grad);
                },
              );
            },
          ),
        ),

        // Input bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          color: Colors.white,
          child: Row(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    color: const Color(0xFFF3F0F8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade200)),
                child: TextField(
                  controller: _msgCtrl,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : () => _send(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: _sending ? null : LinearGradient(
                      colors: grad,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  color: _sending ? Colors.grey.shade300 : null,
                  shape: BoxShape.circle,
                  boxShadow: _sending ? [] : [BoxShadow(
                      color: grad.last.withOpacity(0.4),
                      blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: _sending
                    ? const Padding(padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ])),
    );
  }
}

// ── Private Bubble with image support ─────────────────────────────────
class _PrivateBubble extends StatelessWidget {
  final String text, image, time, sender;
  final bool isMe;
  final List<Color> grad;
  const _PrivateBubble({
    required this.text,
    this.image = '',
    required this.time,
    required this.isMe,
    required this.sender,
    required this.grad,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 30, height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: grad,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)),
              child: Center(child: Text(
                Helpers.getInitials(sender),
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 11),
              )),
            ),
          ],
          Flexible(child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 3),
                  child: Text(sender, style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: grad.first)),
                ),
              if (image.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: image.startsWith('data:image')
                      ? Image.memory(
                    base64Decode(image.split(',').last),
                    height: 150,
                    width: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, size: 40),
                  )
                      : Image.network(
                    image,
                    height: 150,
                    width: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, size: 40),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isMe ? LinearGradient(
                      colors: grad,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight) : null,
                  color: isMe ? null : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft:     const Radius.circular(18),
                    topRight:    const Radius.circular(18),
                    bottomLeft:  Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [BoxShadow(
                      color: isMe
                          ? grad.last.withOpacity(0.3)
                          : Colors.black.withOpacity(0.06),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Text(text, style: TextStyle(
                    fontSize: 13.5,
                    color: isMe ? Colors.white : const Color(0xFF1A1A2E),
                    height: 1.45)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Text(time, style: const TextStyle(
                    fontSize: 9.5, color: Colors.grey)),
              ),
            ],
          )),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyState({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 52, color: Colors.grey.withOpacity(0.35)),
      const SizedBox(height: 12),
      Text(label, style: const TextStyle(
          color: Colors.grey, fontSize: 14)),
    ]),
  );
}

// ── Helpers ────────────────────────────────────────────────────────────
String _sortedChatId(String a, String b) {
  final s = [a, b]..sort();
  return '${s[0]}_${s[1]}';
}