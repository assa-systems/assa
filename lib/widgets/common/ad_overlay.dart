import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

/// Converts any Google Drive sharing URL into a direct-loadable image URL.
/// Uses lh3.googleusercontent.com which works on Android without auth redirects.
String _toDirectImageUrl(String url) {
  if (url.isEmpty) return url;
  if (url.contains('drive.google.com')) {
    final m = RegExp(r'(?:/file/d/|[?&]id=)([a-zA-Z0-9_-]+)').firstMatch(url);
    if (m != null) {
      final id = m.group(1)!;
      return 'https://lh3.googleusercontent.com/d/$id';
    }
  }
  return url;
}

/// Shows a full-screen ad (if one is active) as a modal over the current route.
/// Call this after a successful booking submission.
Future<void> showFullScreenAd(BuildContext context) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('ads')
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return;

    final adDoc  = snap.docs.first;
    final adData = adDoc.data();

    // Track impression
    FirebaseFirestore.instance.collection('ads').doc(adDoc.id).update({
      'impressions': FieldValue.increment(1),
      'lastSeen':    FieldValue.serverTimestamp(),
    }).catchError((_) {});

    if (!context.mounted) return;

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => _AdFullScreenPage(
          ad:    {...adData, '_id': adDoc.id},
          onLink: (url) async {
            try {
              String safeUrl = url.trim();
              if (!safeUrl.startsWith('http://') && !safeUrl.startsWith('https://')) {
                safeUrl = 'https://$safeUrl';
              }
              final uri = Uri.parse(safeUrl);
              final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!launched) {
                await launchUrl(uri, mode: LaunchMode.inAppWebView,
                    webViewConfiguration: const WebViewConfiguration(
                      enableDomStorage: true,
                      enableJavaScript: true,
                    ));
              }
            } catch (_) {}
          },
        ),
      ),
    );
  } catch (_) {}
}

/// Full-screen ad shown as a push route (awaitable — caller resumes after dismiss).
class _AdFullScreenPage extends StatefulWidget {
  final Map<String, dynamic> ad;
  final Future<void> Function(String) onLink;
  const _AdFullScreenPage({required this.ad, required this.onLink});
  @override
  State<_AdFullScreenPage> createState() => _AdFullScreenPageState();
}

class _AdFullScreenPageState extends State<_AdFullScreenPage> {
  int _countdown = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 1) {
        t.cancel();
        Navigator.of(context).pop();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _recordTap() {
    final adId = widget.ad['_id'] as String?;
    if (adId != null) {
      FirebaseFirestore.instance.collection('ads').doc(adId).update({
        'taps':    FieldValue.increment(1),
        'lastTap': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _AdFullScreen(
        ad: widget.ad,
        onDismiss: () => Navigator.of(context).pop(),
        onLink: widget.onLink,
        onTap: _recordTap,
        countdown: _countdown,
      ),
    );
  }
}

// AdOverlayWrapper removed — ads now shown at controlled placements only:
//   • showFullScreenAd()  — after booking submission
//   • AdDashboardCard     — inline in user_dashboard scroll (bottom)
//   • Game Hub ad boost   — between rounds / after results

class _AdFullScreen extends StatelessWidget {
  final Map<String, dynamic> ad;
  final VoidCallback onDismiss;
  final Future<void> Function(String) onLink;
  final VoidCallback onTap;
  final int countdown;

  const _AdFullScreen({
    required this.ad,
    required this.onDismiss,
    required this.onLink,
    required this.onTap,
    this.countdown = 0,
  });

  @override
  Widget build(BuildContext context) {
    final rawImg   = (ad['imageUrl'] ?? '').toString();
    final imageUrl = _toDirectImageUrl(rawImg);
    final title    = (ad['title']   ?? '').toString();
    final body     = (ad['body']    ?? '').toString();
    final linkUrl  = (ad['linkUrl'] ?? '').toString();
    final hasImg   = imageUrl.isNotEmpty;
    final hasLink  = linkUrl.isNotEmpty;

    return Material(
      color: Colors.black,
      child: GestureDetector(
        onTap: hasLink ? () {
          onTap();
          onLink(linkUrl);
        } : null,
        child: SizedBox.expand(
          child: Stack(children: [

            // Full screen image
            if (hasImg)
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  httpHeaders: const {'User-Agent': 'Mozilla/5.0'},
                  placeholder: (_, __) => Container(
                    color: const Color(0xFF1A237E),
                    child: const Center(child: CircularProgressIndicator(
                        color: Colors.white54, strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => _placeholder(),
                ),
              )
            else
              Positioned.fill(child: _placeholder()),

            // Dark gradient at bottom
            Positioned(
              bottom: 0, left: 0, right: 0, height: 220,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // Top bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.campaign_rounded, color: Colors.white54, size: 11),
                      SizedBox(width: 4),
                      Text('ADVERTISEMENT', style: TextStyle(
                          color: Colors.white54, fontSize: 9,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                    ]),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: countdown <= 0 ? onDismiss : null,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (countdown > 0) ...[
                          Text('Skip in ${countdown}s', style: const TextStyle(
                              color: Colors.white70, fontSize: 12,
                              fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                        ] else ...[
                          const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 5),
                          const Text('SKIP', style: TextStyle(
                              color: Colors.white, fontSize: 12,
                              fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        ],
                      ]),
                    ),
                  ),
                ]),
              ),
            ),

            // Bottom text overlay
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w900,
                          color: Colors.white, height: 1.2,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 8)]),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(body, style: TextStyle(
                            fontSize: 13, color: Colors.white.withOpacity(0.85),
                            height: 1.4),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                      if (hasLink) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.open_in_new_rounded,
                                color: Color(0xFF1A237E), size: 14),
                            SizedBox(width: 6),
                            Text('Tap to open', style: TextStyle(
                                color: Color(0xFF1A237E), fontSize: 12,
                                fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          ]),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: const Color(0xFF1A237E),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.campaign_rounded, color: Colors.white.withOpacity(0.25), size: 64),
      const SizedBox(height: 8),
      Text('Advertisement', style: TextStyle(
          color: Colors.white.withOpacity(0.25), fontSize: 13)),
    ])),
  );
}

// ── Ad Dashboard Card (used directly in user_dashboard for inline display) ───
// This is the card you see in the dashboard scroll — separate from the overlay.
class AdDashboardCard extends StatelessWidget {
  final Map<String, dynamic> ad;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const AdDashboardCard({
    super.key,
    required this.ad,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final rawImg   = (ad['imageUrl'] ?? '').toString();
    final imageUrl = _toDirectImageUrl(rawImg);
    final title    = (ad['title']   ?? '').toString();
    final body     = (ad['body']    ?? '').toString();
    final linkUrl  = (ad['linkUrl'] ?? '').toString();
    final hasImg   = imageUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
            color: const Color(0xFF0D47A1).withOpacity(0.25),
            blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GestureDetector(
          onTap: onTap,
          child: Stack(children: [
            // Background image or gradient
            if (hasImg)
              CachedNetworkImage(
                imageUrl: imageUrl,
                height: 160, width: double.infinity,
                fit: BoxFit.cover,
                httpHeaders: const {'User-Agent': 'Mozilla/5.0'},
                errorWidget: (_, __, ___) => _gradientBg(),
              )
            else
              SizedBox(height: 160, child: _gradientBg()),

            // Dark overlay
            if (hasImg)
              Container(
                height: 160,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  ),
                ),
              ),

            // AD chip + dismiss
            Positioned(top: 8, right: 8,
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: const Text('AD', style: TextStyle(
                      color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 14),
                  ),
                ),
              ]),
            ),

            // Text content
            Positioned(left: 0, right: 0, bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: const TextStyle(
                      color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w800, height: 1.2,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(body, style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  if (linkUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.open_in_new_rounded,
                            color: Color(0xFF1A237E), size: 12),
                        SizedBox(width: 4),
                        Text('Tap to open', style: TextStyle(
                            color: Color(0xFF1A237E), fontSize: 11,
                            fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _gradientBg() => Container(
    height: 160,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
    child: Center(child: Icon(Icons.campaign_rounded,
        color: Colors.white.withOpacity(0.2), size: 48)),
  );
}