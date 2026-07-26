import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../domain/profile_data.dart';
import '../../../state/providers.dart';
import '../../profile/profile_screen.dart';
import '../../shared/wave_mark.dart';

/// Home header — royal blue bar with white wordmark + greeting, notification
/// bell, gold-ringed avatar. Tapping the avatar navigates to ProfileScreen.
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key});

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawName = ref.watch(prefsProvider).citizenName;
    final accountName = rawName.isNotEmpty
        ? '${rawName[0].toUpperCase()}${rawName.substring(1)}'
        : rawName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandMark(color: Colors.white),
              const Spacer(),
              const _NotificationBell(),
              const SizedBox(width: 12),
              _Avatar(
                accountName: accountName,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfileScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_greeting()}, $accountName',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.notifications_outlined,
            size: 24, color: Colors.white.withValues(alpha: 0.9)),
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            height: 16,
            width: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4D4D),
              shape: BoxShape.circle,
              border:
                  Border.all(color: const Color(0xFF1A3A8F), width: 1.5),
            ),
            child: const Text(
              '3',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.accountName, required this.onTap});

  final String accountName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
    );
  }
}

