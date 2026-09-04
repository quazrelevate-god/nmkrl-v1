import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/profile_data.dart';
import '../../../state/providers.dart';
import '../../profile/profile_screen.dart';
import '../../search/search_overlay.dart';
import '../../shared/notification_bell.dart';
import '../../shared/wave_mark.dart';

/// Home app bar (v5) — a SOLID white capsule floating over the full-bleed map.
///
/// It used to be a frosted panel with a bare magnifier. Solid white lets the
/// navy wordmark and the dark glyphs hold their contrast over any tile the map
/// happens to draw underneath, and the search is a real field rather than an
/// icon, so what it does is legible without tapping it.
///
/// Left to right: wordmark, the search field taking the free space, the
/// notification bell, the avatar.
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({
    super.key,
    this.searchIssues = const [],
    this.onUpvote,
  });

  /// Pool the search overlay looks through (ward feed + own reports).
  final List<Issue> searchIssues;
  final ValueChanged<Issue>? onUpvote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountName = ref.watch(prefsProvider).citizenName;
    return SolidCapsule(
      // Tighter on the right: the bell and avatar are round, so they carry
      // their own optical margin and an equal numeric inset reads as too much.
      padding: const EdgeInsets.fromLTRB(13, 8, 7, 8),
      child: Row(
        children: [
          // Every point spent here is a point the placeholder loses, and the
          // placeholder is what tells a first-time user what can be searched.
          const BrandLogo(height: 23, onLight: true),
          const SizedBox(width: 8),
          Expanded(
            child: _SearchField(
              onTap: () => SearchOverlay.open(
                context,
                issues: searchIssues,
                onUpvote: onUpvote,
              ),
            ),
          ),
          const SizedBox(width: 4),
          NotificationBell(
            recipientType: 'citizen',
            recipientId: ref.watch(userIdProvider),
            // Dark glyph — the bar is white now.
            dark: false,
          ),
          _ProfileAvatar(initials: ProfileData.initialsOf(accountName)),
        ],
      ),
    );
  }
}

/// Solid white capsule for the floating map overlays (app bar, ward chip,
/// demo jump). Opaque rather than frosted, so dark type keeps its contrast
/// whatever the map draws underneath; a hairline edge and a soft drop shadow
/// separate it from the tiles without a heavy border.
class SolidCapsule extends StatelessWidget {
  const SolidCapsule({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE8EBEF), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The search entry point: a real field, not a bare icon. It does not take
/// focus — tapping anywhere on it opens [SearchOverlay], which owns the actual
/// input — so the placeholder is free to say what can be searched for.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 16, color: NkColors.slate500),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                context.tr('Search location, issue or ward'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: NkColors.slate400,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gold-ringed avatar circle. Tapping navigates to [ProfileScreen].
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: const BoxDecoration(
          gradient: nkGoldGradient,
          shape: BoxShape.circle,
        ),
        child: Container(
          height: 31,
          width: 31,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            // Brand blue from the logo SVG, not an approximated navy.
            color: NkColors.refBlue,
            shape: BoxShape.circle,
          ),
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: NkColors.gold300,
            ),
          ),
        ),
      ),
    );
  }
}
