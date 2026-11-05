import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/settings_controller.dart';
import 'chat_screen.dart';
import 'engineering_screen.dart';

/// ShELL 入口：Simple Mode（对话）/ Developer Mode（工程工具）。
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key, required this.settings});

  final SettingsController settings;

  static const _violet = Color(0xFF7C3AED);
  static const _violetSoft = Color(0xFFA78BFA);
  static const _bg = Color(0xFF0B0B12);
  static const _card = Color(0xFF15151F);

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final logoSize = landscape ? size.height * 0.38 : size.width * 0.42;

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/branding/app_icon_source.png',
            width: logoSize, height: logoSize),
        const SizedBox(height: 20),
        RichText(
          text: const TextSpan(
            style: TextStyle(
                fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white),
            children: [
              TextSpan(text: 'S/eng '),
              TextSpan(text: 'ai', style: TextStyle(color: _violet)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('app_title'.tr(),
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
        const SizedBox(height: 10),
        Text('entry_tagline'.tr(),
            style: const TextStyle(color: _violetSoft, fontSize: 13)),
        const SizedBox(height: 28),
        _ModeCard(
          icon: Icons.bolt,
          title: 'entry_simple_mode'.tr(),
          subtitle: 'entry_simple_desc'.tr(),
          onTap: () => _open(context, ChatScreen(settings: settings)),
        ),
        const SizedBox(height: 12),
        _ModeCard(
          icon: Icons.code,
          title: 'entry_developer_mode'.tr(),
          subtitle: 'entry_developer_desc'.tr(),
          dim: true,
          onTap: () => _open(context, const EngineeringScreen()),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: landscape
                  ? SingleChildScrollView(child: content)
                  : content,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.dim = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final border = dim ? const Color(0xFF2A2A36) : EntryScreen._violet;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: EntryScreen._card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: dim ? 1 : 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: EntryScreen._violetSoft, size: 26),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
          ],
        ),
      ),
    );
  }
}
