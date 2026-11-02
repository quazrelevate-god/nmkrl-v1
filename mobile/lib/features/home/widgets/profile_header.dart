import 'dart:io';

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
      // Tighter on the right: the bell and avatar are round, so they carry
      // their own optical margin and an equal numeric inset reads as too much.
      padding: const EdgeInsets.fromLTRB(13, 8, 7, 8),
      child: Row(
        children: [
          // Every point spent here is a point the placeholder loses, and the
          // placeholder is what tells a first-time user what can be searched.
          const BrandLogo(height: 23, onLight: true),
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
          const SizedBox(width: 8),
          // Coordinator mode: a compact icon button for search instead of the
          // always-visible field — the wordmark + STAFF badge already eat most
          // of the bar. Citizen mode keeps the real field untouched.
          if (coordinator != null) ...[
            _SearchIconButton(
              onTap: () => SearchOverlay.open(
                context,
                issues: searchIssues,
                onUpvote: onUpvote,
              ),
            ),
            const SizedBox(width: 4),
          ] else ...[
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
          ],
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

/// The citizen search entry point: a real field, not a bare icon. It does not take
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

/// Coordinator search entry point: a compact round button matching the bell's
/// proportions, so the bar stays one clean row of round controls. Opens the
/// same [SearchOverlay] the citizen field does.
class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 31,
        width: 31,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Same recessed grey as the citizen field, at the avatar's size —
          // the three right-side controls read as one family.
          color: const Color(0xFFF1F3F6),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE8EBEF)),
        ),
        child: const Icon(Icons.search, size: 17, color: NkColors.slate500),
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
        padding: const EdgeInsets.all(1.5),
        decoration: const BoxDecoration(
          gradient: nkGoldGradient,
          shape: BoxShape.circle,
        ),
        child: Container(
          height: 31,
          width: 31,
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
        height: 31,
        width: 31,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialsText(),
      );
    }
    if (avatarPath != null) {
      return Image.file(
        File(avatarPath!),
        height: 31,
        width: 31,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialsText(),
      );
    }
    return _initialsText();
  }

  Widget _initialsText() => Text(
        initials,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: NkColors.gold300,
        ),
      );
}
