import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/i18n.dart';
import '../../../domain/profile_data.dart';
import '../../../state/providers.dart';
import '../../shared/notification_bell.dart';
import '../../shared/wave_mark.dart';

/// Home header — navy bar (v2). Gold brand mark + language toggle + notification
/// bell + avatar, with the greeting always visible below. Tapping the avatar
/// expands a small sign-out panel. The per-account stats live in [HomeStatsRow]
/// in the body now, not in this header.
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({
    super.key,
    required this.profileOpen,
    required this.onToggleProfile,
    required this.onSignOut,
  });

  final bool profileOpen;
  final VoidCallback onToggleProfile;
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
    return Container(
      decoration: const BoxDecoration(
        gradient: nkNavyGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 30,
            offset: Offset(0, 14),
            spreadRadius: -16,
          ),
        ],
      ),
      child: Column(
        children: [
          // Brand bar + avatar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
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
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onToggleProfile();
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
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              child: Text(
                                ProfileData.initialsOf(accountName),
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
                                border:
                                    Border.all(color: NkColors.brand, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Persistent greeting
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 16, 0),
            child: Align(
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
          ),

          // Expandable sign-out panel (avatar tap)
          AnimatedSize(
            duration: const Duration(milliseconds: 360),
            curve: NkMotion.settle,
            alignment: Alignment.topCenter,
            child: profileOpen
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: GestureDetector(
                      onTap: onSignOut,
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.logout,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              context.tr('Sign out'),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),

          const SizedBox(height: 14),
        ],
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
