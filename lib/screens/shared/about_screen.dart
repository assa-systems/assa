import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:assa/core/constants/app_colors.dart';

// ════════════════════════════════════════════════════════════════════
// ABOUT SCREEN — ASSA
//
// Combines: About ASSA, Our Purpose, Acknowledgements,
// Meet the Team, FAQ, What's New / Update Info, and App Version.
// ════════════════════════════════════════════════════════════════════

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _appVersion = '';
  String _buildNumber = '';
  bool _loadingVersion = true;

  // ── TEAM MEMBERS (BUILDERS) ──────────────────────────────────────
  // Class of 2026 Graduating Set
  // Department of Telecommunications Engineering
  // Faculty of Ground and Communication Engineering
  // Air Force Institute of Technology (AFIT), Kaduna
  static const List<Map<String, String>> _teamMembers = [
    {
      'name': 'Aminu Abdulrahman',
      'matric': 'U21TE1031',
      'role': 'Mobile App Developer / Team Lead & Integrator',
      'bio': 'Led the team, built the cross-platform Flutter application, '
          'integrated Firebase backend, and ensured seamless communication '
          'between the mobile app and the LoRa network.',
    },
    {
      'name': 'Edet Promise',
      'matric': 'U20TE1034',
      'role': 'Hardware Integration',
      'bio': 'Developed and optimized the Arduino firmware for the Nano '
          'microcontrollers, focusing on LoRa communication stack and '
          'memory efficiency across all node types.',
    },
    {
      'name': 'Adegoke Victor',
      'matric': 'U21TE1006',
      'role': 'Hardware Engineer',
      'bio': 'Designed and assembled the hardware modules including the '
          'Gateway, Access Points, Repeater, and Shuttle Units.',
    },
    {
      'name': 'Adegbola Abdulazeem Adebayo',
      'matric': 'U21TE1021',
      'role': 'UI/UX Designer & Frontend Developer',
      'bio': 'Designed the user interface and user experience for the '
          'Flutter application, ensuring intuitive navigation and a '
          'polished visual design.',
    },
    {
      'name': 'Odebumi Adedayo Feyintoluwani',
      'matric': 'U21TE1043',
      'role': 'QA / Testing Engineer',
      'bio': 'Conducted all system-level testing, including range tests, '
          'latency measurements, and end-to-end functional validation.',
    },
    {
      'name': 'Akaa Elisha Terzungwe',
      'matric': 'U21TE1044',
      'role': 'Networking Engineer',
      'bio': 'Configured the LoRa radio parameters, performed duty-cycle '
          'analysis, and ensured NCC regulatory compliance.',
    },
    {
      'name': 'Okonkwo Micheal Chiemerie',
      'matric': 'U21TE1045',
      'role': 'Documentation / Technical Writer',
      'bio': 'Authored the project report, prepared the technical '
          'documentation, and managed the project repository.',
    },
  ];

  // ── ACKNOWLEDGEMENTS ──────────────────────────────────────────────
  static const List<Map<String, String>> _acknowledgements = [
    {
      'name': 'Engr. J. Raymond',
      'role': 'Project Supervisor',
      'contribution': 'Whose sharp insight, patient guidance, and '
          'constructive advice steered this project from concept to reality.',
    },
    {
      'name': 'Squadron Leader O.K. Olatunji',
      'role': 'Head of Department',
      'contribution': 'For his invaluable support throughout the '
          'implementation of this project.',
    },
    {
      'name': 'Engr. Christopher A. Alabi',
      'role': 'Project Coordinator',
      'contribution': 'Whose contributions played a major role in shaping '
          'this project into a polished, presentable work.',
    },
    {
      'name': 'Engr. Dr. F.C. Njoku',
      'role': 'Level Adviser',
      'contribution': 'For his guidance throughout our academic journey.',
    },
    {
      'name': 'Engr. Dr. Z. Augustine',
      'role': 'Lecturer',
      'contribution': 'For the knowledge imparted throughout our studies.',
    },
    {
      'name': 'Mrs. O.O. Adekogba',
      'role': 'Lecturer',
      'contribution': 'For the knowledge imparted throughout our studies.',
    },
  ];

  // ── RELEASE NOTES ──────────────────────────────────────────────────
  static const List<Map<String, String>> _updateLog = [
    // {'version': '1.0.0', 'date': 'July 2026', 'content': 'Initial release'},
  ];

  static const List<Map<String, String>> _faqs = [
    {
      'q': 'How do I request a shuttle?',
      'a': 'Go to "Book a Ride" on your dashboard, choose your pickup and '
          'destination, select Shared or Chartered, then send your request. '
          'You can request online (with internet) or offline via the campus '
          'hotspot when you have no internet connection.',
    },
    {
      'q': 'What is my Pickup ID for?',
      'a': 'Your Pickup ID is a unique 3-character code (e.g. K47) shown to '
          'the driver so they can identify you at your pickup point, both '
          'online and offline.',
    },
    {
      'q': 'What happens if I have no internet?',
      'a': 'Connect to the campus shuttle hotspot. ASSA automatically '
          'detects this and switches to Offline Mode, letting you request a '
          'ride directly through the shuttle access point.',
    },
    {
      'q': 'How do I report a lost or found item?',
      'a': 'Open Lost & Found from your dashboard and post a Lost or Found '
          'item with a description, location, and optional photo. Owners '
          'can claim found items, and finders may receive ride credits once '
          'admin approves the return.',
    },
    {
      'q': 'Who do I contact if I have an issue?',
      'a': 'Use the Complaint Panel to chat directly with admin, or submit '
          'a report describing your issue and the shuttle involved.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
          _buildNumber = info.buildNumber;
          _loadingVersion = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingVersion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildLogoBlock(),
                  const SizedBox(height: 20),
                  _sectionCard(
                    title: 'About ASSA',
                    icon: Icons.info_outline_rounded,
                    child: const Text(
                      'ASSA (AFIT Shuttle Service App) connects students, '
                          'drivers, and administrators to make campus shuttle '
                          'transport faster and more reliable — whether you are '
                          'online or offline via the campus hotspot.',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'Our Purpose',
                    icon: Icons.flag_rounded,
                    child: const Text(
                      'To eliminate the uncertainty of waiting for campus '
                          'shuttles by giving every passenger real-time visibility '
                          'into their ride status, a reliable offline fallback '
                          'when there is no internet, and simple tools for lost '
                          'items, complaints, and driver coordination.',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'Acknowledgements',
                    icon: Icons.emoji_people_rounded,
                    child: Column(
                      children: [
                        // Institutional acknowledgement
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.15)),
                          ),
                          child: const Text(
                            'This project was developed as part of the '
                                'Telecommunications Engineering program at '
                                'AFIT (Air Force Institute of Technology), Kaduna.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.6),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Individual acknowledgements
                        ..._acknowledgements.map((a) => _AcknowledgementTile(
                          name: a['name'] ?? '',
                          role: a['role'] ?? '',
                          contribution: a['contribution'] ?? '',
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'Meet the Team — Class of 2026',
                    icon: Icons.groups_rounded,
                    child: Column(
                      children: [
                        // Department and Faculty header
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primary.withOpacity(0.08),
                                AppColors.primary.withOpacity(0.03),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.15)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.school_rounded,
                                      size: 16, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Department of Telecommunications Engineering',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Faculty of Ground and Communication Engineering',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary.withOpacity(0.8),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '🎓 Graduating Set — July 2026',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary.withOpacity(0.8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._teamMembers.map((p) => _TeamMemberTile(
                          name: p['name'] ?? '',
                          matric: p['matric'] ?? '',
                          role: p['role'] ?? '',
                          bio: p['bio'] ?? '',
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'Frequently Asked Questions',
                    icon: Icons.quiz_outlined,
                    child: Column(
                      children: _faqs
                          .map((f) => _FaqTile(
                        question: f['q'] ?? '',
                        answer: f['a'] ?? '',
                      ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: "What's New",
                    icon: Icons.new_releases_outlined,
                    child: _updateLog.isEmpty
                        ? const Text(
                      'No update history recorded yet.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textHint),
                    )
                        : Column(
                      children: _updateLog
                          .map((u) => _UpdateLogTile(
                        version: u['version'] ?? '',
                        date: u['date'] ?? '',
                        content: u['content'] ?? '',
                      ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'App Version',
                    icon: Icons.smartphone_rounded,
                    child: _loadingVersion
                        ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary)),
                    )
                        : Row(
                      children: [
                        const Icon(Icons.tag_rounded,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          _appVersion.isNotEmpty
                              ? 'Version $_appVersion (build $_buildNumber)'
                              : 'Version unavailable',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)]),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                Text('ASSA · Purpose · Acknowledgements · Team 2026',
                    style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 26),
        ],
      ),
    );
  }

  Widget _buildLogoBlock() {
    return Center(
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF0D47A1)]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF1565C0).withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5)),
              ],
            ),
            child: const Icon(Icons.directions_bus_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 10),
          const Text('ASSA',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const Text('AFIT Shuttle Service App',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── ACKNOWLEDGEMENT TILE ─────────────────────────────────────────────
class _AcknowledgementTile extends StatelessWidget {
  final String name, role, contribution;
  const _AcknowledgementTile({
    required this.name,
    required this.role,
    required this.contribution,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.08),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary.withOpacity(0.7),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  contribution,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── TEAM MEMBER TILE ──────────────────────────────────────────────────
class _TeamMemberTile extends StatelessWidget {
  final String name, matric, role, bio;
  const _TeamMemberTile({
    required this.name,
    required this.matric,
    required this.role,
    required this.bio,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.12),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        matric,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary.withOpacity(0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        role,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary.withOpacity(0.7),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  bio,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── FAQ EXPANDABLE TILE ─────────────────────────────────────────────
class _FaqTile extends StatefulWidget {
  final String question, answer;
  const _FaqTile({required this.question, required this.answer});
  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.question,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.answer,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.6)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── UPDATE LOG TILE ──────────────────────────────────────────────────
class _UpdateLogTile extends StatelessWidget {
  final String version, date, content;
  const _UpdateLogTile({
    required this.version,
    required this.date,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('v$version',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ),
              const SizedBox(width: 8),
              Text(date,
                  style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 6),
          Text(content,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}