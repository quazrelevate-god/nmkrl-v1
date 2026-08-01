import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/i18n.dart';
import '../../../domain/profile_data.dart';
import '../../../state/providers.dart';
import '../../profile/profile_screen.dart';
import '../../shared/notification_bell.dart';
import '../../shared/wave_mark.dart';

/// Home header — floats directly over the full-bleed map (v3). Gold brand mark
/// + language toggle + notification bell + avatar, with the greeting always
/// visible below. There is no solid bar: the background is a vertical gradient
/// running from brand blue at the status bar to fully transparent at the bottom
/// edge, so the map reads through with no hard seam. Tapping the avatar
/// navigates to [ProfileScreen].
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key});

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
      // Deep navy holds full opacity behind the wordmark and greeting, then
      // releases to alpha 0 over the last quarter so the bar reads as a solid
      // block with a soft bottom edge rather than a long wash. The transparent
      // stop keeps the same RGB so the fade does not shift hue on the way out.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1F3C), Color(0xFF0D1F3C), Color(0x000D1F3C)],
          stops: [0.0, 0.75, 1.0],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, topInset + 10, 16, 18),
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
                  _ProfileAvatar(
                    initials: ProfileData.initialsOf(accountName),
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
              '${context.tr(_greeting)}, $accountName \u{1F44B}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: Colors.white,
                // The gradient is near-transparent this far down, so the
                // greeting needs its own contrast against the map tiles.
                shadows: [
                  Shadow(color: Color(0x661A3556), blurRadius: 8),
                  Shadow(color: Color(0x4D000000), blurRadius: 2),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
          MaterialPageRoute<void>(
            builder: (_) => const ProfileScreen(),
          ),
        );
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
    );
  }
}
