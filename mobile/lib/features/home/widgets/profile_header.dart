import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/profile_data.dart';
import '../../../state/providers.dart';
import '../../profile/profile_screen.dart';
import '../../search/search_overlay.dart';
import '../../shared/notification_bell.dart';
import '../../shared/wave_mark.dart';

/// Home app bar (v4) — a frosted capsule floating directly over the full-bleed
/// map. Gold wordmark on the left; search, notifications and the avatar on the
/// right. There is no solid bar, no greeting and no language toggle: the map
/// reads through the blur, and language now lives in [ProfileScreen].
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
    return FrostedCapsule(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const BrandLogo(height: 30),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AiSearchButton(
                onTap: () => SearchOverlay.open(
                  context,
                  issues: searchIssues,
                  onUpvote: onUpvote,
                ),
              ),
              const SizedBox(width: 2),
              NotificationBell(
                recipientType: 'citizen',
                recipientId: ref.watch(userIdProvider),
                dark: true, // white glyph on the smoky capsule
              ),
              const SizedBox(width: 4),
              _ProfileAvatar(initials: ProfileData.initialsOf(accountName)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The shared frosted-glass surface used by the floating map overlays (app bar
/// + ward chip): a real backdrop blur under a translucent white fill, so the
/// map stays legible underneath. Popups deliberately do NOT use this — they
/// are solid white.
class FrostedCapsule extends StatelessWidget {
  const FrostedCapsule({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            // Smoky white — light enough for dark glyphs, deep enough that the
            // gold wordmark still reads against pale map tiles.
            color: const Color(0xFF5A6577).withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Magnifier with a small sparkle — the AI-assisted grievance search.
class _AiSearchButton extends StatelessWidget {
  const _AiSearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.search, size: 22, color: Colors.white),
            Positioned(
              top: 8,
              right: 6,
              child: Icon(Icons.auto_awesome,
                  size: 10, color: NkColors.gold300.withValues(alpha: 0.95)),
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
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          gradient: nkGoldGradient,
          shape: BoxShape.circle,
        ),
        child: Container(
          height: 34,
          width: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            // Brand blue from the logo SVG, not an approximated navy.
            color: NkColors.refBlue,
            shape: BoxShape.circle,
          ),
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: NkColors.gold300,
            ),
          ),
        ),
      ),
    );
  }
}
