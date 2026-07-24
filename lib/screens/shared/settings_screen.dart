import 'package:flutter/material.dart';
import 'package:assa/core/constants/app_colors.dart';
import 'package:assa/screens/shared/theme_screen.dart';
import 'package:assa/screens/shared/about_screen.dart';
import 'package:assa/services/theme_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SettingsTile(
                    icon: Icons.palette_rounded,
                    title: 'Theme',
                    subtitle: 'Light, dark, or system default',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ThemeScreen())),
                  ),
                  const SizedBox(height: 8),
                  const _AccessibilityZoomTile(),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About ASSA',
                    subtitle: 'Purpose · FAQ · Updates · Version',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AboutScreen())),
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
                Text('App Settings',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                Text('Appearance & information',
                    style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.settings_rounded, color: Colors.white, size: 26),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _AccessibilityZoomTile extends StatefulWidget {
  const _AccessibilityZoomTile();

  @override
  State<_AccessibilityZoomTile> createState() => _AccessibilityZoomTileState();
}

class _AccessibilityZoomTileState extends State<_AccessibilityZoomTile> {
  @override
  Widget build(BuildContext context) {
    final scale = ThemeController.instance.textScaleFactor;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.zoom_in_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Accessibility Zoom',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text('Enlarge text & UI up to ${(scale * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text('${(scale * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primary.withOpacity(0.15),
              thumbColor: AppColors.primary,
            ),
            child: Slider(
              value: scale,
              min: 1.0,
              max: 2.0,
              divisions: 10,
              label: '${(scale * 100).round()}%',
              onChanged: (newScale) {
                setState(() {
                  ThemeController.instance.setTextScaleFactor(newScale);
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}