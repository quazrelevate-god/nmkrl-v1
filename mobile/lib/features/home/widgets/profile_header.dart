import 'dart:io';

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

/// Rendered height of the floating app-bar capsule.
///
/// The home screens position the masthead around this, so it is a shared
/// constant rather than a literal repeated in three places; the capsule's own
/// padding and the round controls inside it add up to exactly this.
///
/// Back up from 48 — but the extra 10dp buys SIZE, not air. The bar had a bay
/// of empty white between the wordmark and the controls, which made both look
/// undersized in a bar that was mostly nothing; spending that space on the
/// wordmark and the three round controls is what makes them prominent. It
/// also costs the map nothing, because the band's height is the sky image's
/// height and the bar fits inside it either way.
const double kAppBarHeight = 58;

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
    // Everything below is coordinator-mode; defaults keep the citizen home
    // bit-for-bit what it was. When [profile] is supplied the citizen
    // providers (name, id, avatar file) are not touched at all.
    this.recipientType = 'citizen',
    this.recipientId,
    this.profile,
    this.badge,
  });

  /// Pool the search overlay looks through (ward feed + own reports).
  final List<Issue> searchIssues;
  final ValueChanged<Issue>? onUpvote;

  /// Who the notification bell polls for. Citizens leave both defaults; the
  /// coordinator screen passes 'coordinator' and its own username.
  final String recipientType;
  final String? recipientId;

  /// Coordinator profile — initials fallback and the office-uploaded photo.
  /// Non-null switches the bar to coordinator mode.
  final ({String initials, String? photoUrl})? profile;

  /// Optional right-of-wordmark tag, e.g. the coordinator's STAFF pill.
  final String? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = profile != null
        ? (initials: profile!.initials, photo: profile!.photoUrl)
        : null;
    final accountName =
        coordinator != null ? '' : ref.watch(prefsProvider).citizenName;
    final bellId = coordinator != null
        ? (recipientId ?? '')
        : ref.watch(userIdProvider);
    return SolidCapsule(
      // 7 top and bottom around a 44-tall row of controls = [kAppBarHeight].
      // Still tighter on the right: the bell and avatar are round, so they
      // carry their own optical margin and an equal numeric inset reads as
      // too much.
      padding: const EdgeInsets.fromLTRB(16, 7, 9, 7),
      child: Row(
        children: [
          // The primary element in the bar. It is a vector wordmark, so size
          // is the only weight lever there is — the stroke weights are baked
          // into the asset.
          const BrandLogo(height: 34, onLight: true),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                // Solid dark pill on the white bar, gold lettering.
                color: NkColors.refBlueDeep,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: NkColors.gold200,
                  )),
            ),
          ],
          // Both modes: a standalone search button, so the wordmark is the
          // only thing competing for the bar's width and the three round
          // controls read as one family on the right.
          const Spacer(),
          _SearchIconButton(
            onTap: () => SearchOverlay.open(
              context,
              issues: searchIssues,
              onUpvote: onUpvote,
            ),
          ),
          const SizedBox(width: 6),
          NotificationBell(
            recipientType: recipientType,
            recipientId: bellId,
            // Dark glyph — the bar is white now.
            dark: false,
          ),
          _ProfileAvatar(
            initials: coordinator?.initials ?? ProfileData.initialsOf(accountName),
            avatarPath: coordinator == null ? ref.watch(avatarProvider) : null,
            networkPhoto: coordinator?.photo,
          ),
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

/// The search entry point in both apps: a standalone round button matching
/// the bell's and the avatar's proportions, so the bar stays one clean row of
/// round controls. Opens [SearchOverlay], which owns the actual input and the
/// placeholder that says what can be searched for.
class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 42,
        width: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // A soft light ground at the avatar's size, so the three right-side
          // controls read as one family.
          color: const Color(0xFFEFF2F6),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE2E7ED)),
        ),
        // Navy, not grey: this is now the only search affordance in the bar,
        // so it has to look like a control rather than a hint.
        child: const Icon(Icons.search, size: 22, color: NkColors.brand),
      ),
    );
  }
}

/// Gold-ringed avatar circle. Tapping navigates to [ProfileScreen].
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.initials, this.avatarPath, this.networkPhoto});

  final String initials;

  /// Local profile-picture path, or null to fall back to initials.
  final String? avatarPath;

  /// Office-uploaded photo URL (coordinator mode), which never existed
  /// locally: the fallback also covers a URL that fails to load, so a broken
  /// image never replaces the initials.
  final String? networkPhoto;

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
        padding: const EdgeInsets.all(2.5),
        decoration: const BoxDecoration(
          gradient: nkGoldGradient,
          shape: BoxShape.circle,
        ),
        child: Container(
          height: 37,
          width: 37,
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            // Brand blue from the logo SVG, not an approximated navy.
            color: NkColors.refBlue,
            shape: BoxShape.circle,
          ),
          child: _photoWidget(),
        ),
      ),
    );
  }

  Widget _photoWidget() {
    if (networkPhoto != null) {
      return Image.network(
        networkPhoto!,
        height: 37,
        width: 37,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialsText(),
      );
    }
    if (avatarPath != null) {
      return Image.file(
        File(avatarPath!),
        height: 37,
        width: 37,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialsText(),
      );
    }
    return _initialsText();
  }

  Widget _initialsText() => Text(
        initials,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: NkColors.gold300,
        ),
      );
}
