import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/glass.dart';
import '../../../core/theme.dart';
import '../../../domain/profile_data.dart';
import '../../../state/providers.dart';
import '../../shared/notification_bell.dart';
import '../../shared/wave_mark.dart';

/// Home header — port of components/citizen/CitizenProfileHeader.js.
/// Frosted glass bar with rounded bottom: brand + avatar (tap → the gamified
/// profile expands in place with a spring). Name + initials come from the
/// authenticated account (backend users table), not mock data.
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({
    super.key,
    required this.profileOpen,
    required this.onToggleProfile,
    required this.onSignOut,
    this.stats,
  });

  final bool profileOpen;
  final VoidCallback onToggleProfile;
  final VoidCallback onSignOut;

  /// Real per-account counters (null → shows "—" until loaded).
  final ({int reports, int upvotes, int resolved, int open})? stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountName = ref.watch(prefsProvider).citizenName;
    return GlassContainer(
      variant: Glass.clear,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      boxShadow: [
        BoxShadow(
          color: NkColors.slate900.withValues(alpha: 0.25),
          blurRadius: 36,
          offset: const Offset(0, 16),
          spreadRadius: -22,
        ),
      ],
      child: Column(
        children: [
          // Brand bar + avatar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const BrandMark(),
                Row(
                  children: [
                    NotificationBell(
                      recipientType: 'citizen',
                      recipientId: ref.watch(userIdProvider),
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
                            color: NkColors.slate100,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Text(
                            ProfileData.initialsOf(accountName),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: NkColors.brand,
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
                            border: Border.all(color: Colors.white, width: 2),
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

          // Expandable profile panel
          AnimatedSize(
            duration: const Duration(milliseconds: 420),
            curve: NkMotion.settle,
            alignment: Alignment.topCenter,
            child: profileOpen
                ? _ProfilePanel(
                    accountName: accountName,
                    stats: stats,
                    onCollapse: onToggleProfile,
                    onSignOut: onSignOut)
                : const SizedBox(width: double.infinity),
          ),
          // Breathing room above the rounded bottom edge.
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({
    required this.accountName,
    required this.stats,
    required this.onCollapse,
    required this.onSignOut,
  });

  final String accountName;
  final ({int reports, int upvotes, int resolved, int open})? stats;
  final VoidCallback onCollapse;
  final VoidCallback onSignOut;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Hero row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  gradient: nkGoldGradient,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  height: 56,
                  width: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NkColors.slate100,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    ProfileData.initialsOf(accountName),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: NkColors.brand,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_greeting,',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: NkColors.slate400)),
                    Text(
                      '$accountName 👋',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: NkColors.slate900,
                        height: 1.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onCollapse,
                icon: const Icon(Icons.keyboard_arrow_up,
                    size: 20, color: NkColors.slate400),
              ),
            ],
          ),

          const SizedBox(height: 12),
          // Stat tiles
          Row(
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: NkColors.slate200.withValues(alpha: 0.7)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 28,
                          width: 28,
                          alignment: Alignment.center,
                          decoration:
                              BoxDecoration(color: bg, shape: BoxShape.circle),
                          child: Icon(icon, size: 15, color: fg),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: NkColors.slate800,
                          ),
                        ),
                        Text(
                          label,
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: NkColors.slate500),
                        ),
                      ],
                    ),
                  ),
                ),
                if (label != 'Open') const SizedBox(width: 8),
              ],
            ],
          ),

          const SizedBox(height: 12),
          // Sign out
          GestureDetector(
            onTap: onSignOut,
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NkColors.slate200),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout, size: 13, color: NkColors.slate600),
                  SizedBox(width: 6),
                  Text(
                    'Sign out',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: NkColors.slate600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
