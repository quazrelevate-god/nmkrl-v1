import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/i18n.dart';
import '../../../domain/profile_data.dart';
import '../../../state/providers.dart';
import '../../shared/notification_bell.dart';
import '../../shared/wave_mark.dart';

/// Home header — a flat, full-bleed navy bar (v2). Gold brand mark + language
/// toggle + notification bell + avatar, with the greeting always visible below.
/// The header is a fixed-height rectangle (no rounded corners, no expansion):
/// tapping the avatar opens a lightweight floating [MenuAnchor] dropdown, not a
/// panel that resizes the bar. The map card below overlaps the bottom edge, and
/// the per-account stats live in [HomeStatsRow] in the body.
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountName = ref.watch(prefsProvider).citizenName;
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      // Flat full-bleed rectangle — navy runs edge to edge and up behind the
      // status bar (topInset). The overlapping map card owns all rounding.
      decoration: const BoxDecoration(gradient: nkNavyGradient),
      padding: EdgeInsets.fromLTRB(16, topInset + 10, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Brand bar + avatar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const BrandMark(color: NkColors.gold300),
              Row(
                children: [
                  const LangToggle(onDark: true),
                  const SizedBox(width: 6),
                  NotificationBell(
                    recipientType: 'citizen',
                    recipientId: ref.watch(userIdProvider),
                    dark: true,
                  ),
                  const SizedBox(width: 4),
                  _AvatarMenu(
                    initials: ProfileData.initialsOf(accountName),
                    onSignOut: onSignOut,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),
          // Persistent greeting
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${context.tr(_greeting)}, $accountName 👋',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar + floating sign-out dropdown (Material 3 [MenuAnchor]). Tapping the
/// avatar toggles a small rounded menu anchored just below it; tapping outside
/// dismisses it. The menu floats over content — the page layout never moves.
class _AvatarMenu extends StatelessWidget {
  const _AvatarMenu({required this.initials, required this.onSignOut});

  final String initials;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(-96, 8),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        elevation: const WidgetStatePropertyAll(10),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon:
              const Icon(Icons.logout, size: 16, color: NkColors.rose600),
          onPressed: onSignOut,
          child: Text(
            context.tr('Sign out'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: NkColors.slate800,
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          controller.isOpen ? controller.close() : controller.open();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                gradient: nkGoldGradient,
                shape: BoxShape.circle,
              ),
              child: Container(
                height: 36,
                width: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NkColors.brandDark,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: NkColors.gold300,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -1,
              right: -1,
              child: Container(
                height: 12,
                width: 12,
                decoration: BoxDecoration(
                  color: NkColors.emerald500,
                  shape: BoxShape.circle,
                  border: Border.all(color: NkColors.brand, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four per-account counters (Reports / Upvotes / Resolved / Open) as a
/// permanent white card row in the home body (v2). `stats` is null until the
/// first history load, so tiles show "—".
class HomeStatsRow extends StatelessWidget {
  const HomeStatsRow({super.key, required this.stats});

  final ({int reports, int upvotes, int resolved, int open})? stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (icon, value, label, fg, bg) in [
          (
            Icons.assignment_outlined,
            stats == null ? '—' : '${stats!.reports}',
            'Reports',
            NkColors.brand,
            NkColors.brand50
          ),
          (
            Icons.thumb_up_outlined,
            stats == null ? '—' : '${stats!.upvotes}',
            'Upvotes',
            NkColors.teal700,
            NkColors.teal50
          ),
          (
            Icons.check_circle_outline,
            stats == null ? '—' : '${stats!.resolved}',
            'Resolved',
            NkColors.emerald700,
            NkColors.emerald50
          ),
          (
            Icons.schedule,
            stats == null ? '—' : '${stats!.open}',
            'Open',
            NkColors.amber700,
            NkColors.amber50
          ),
        ]) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border:
                    Border.all(color: NkColors.slate200.withValues(alpha: 0.8)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 30,
                    width: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    child: Icon(icon, size: 16, color: fg),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: NkColors.slate900,
                    ),
                  ),
                  Text(
                    context.tr(label),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: NkColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (label != 'Open') const SizedBox(width: 9),
        ],
      ],
    );
  }
}
