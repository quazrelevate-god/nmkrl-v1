import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/glass.dart';
import '../../../core/theme.dart';
import '../../../domain/constituencies.dart';
import '../../../domain/profile_data.dart';
import '../../shared/wave_mark.dart';

/// Home header — port of components/citizen/CitizenProfileHeader.js.
/// Frosted glass bar with rounded bottom: brand + avatar (tap → the gamified
/// profile expands in place with a spring), then the Constituency-highlights
/// strip (AC selector + story tiles).
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profileOpen,
    required this.onToggleProfile,
    required this.onOpenStory,
    required this.constituency,
    required this.onConstituencyChanged,
    required this.onSignOut,
  });

  final bool profileOpen;
  final VoidCallback onToggleProfile;
  final ValueChanged<Story> onOpenStory;
  final String constituency;
  final ValueChanged<String> onConstituencyChanged;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
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
                            ProfileData.initials,
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
          ),

          // Expandable profile panel
          AnimatedSize(
            duration: const Duration(milliseconds: 420),
            curve: NkMotion.settle,
            alignment: Alignment.topCenter,
            child: profileOpen
                ? _ProfilePanel(
                    onCollapse: onToggleProfile, onSignOut: onSignOut)
                : const SizedBox(width: double.infinity),
          ),

          // Constituency highlights
          _ConstituencyHighlights(
            constituency: constituency,
            onConstituencyChanged: onConstituencyChanged,
            onOpenStory: onOpenStory,
          ),
        ],
      ),
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.onCollapse, required this.onSignOut});

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
    final pctInTier =
        (ProfileData.levelSpan - ProfileData.toNext) / ProfileData.levelSpan;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Hero row
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
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
                        ProfileData.initials,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: NkColors.brand,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [NkColors.amber300, NkColors.amber500],
                        ),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        ProfileData.level.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: NkColors.brandDark,
                        ),
                      ),
                    ),
                  ),
                ],
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
                    const Text(
                      '${ProfileData.name} 👋',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: NkColors.slate900,
                        height: 1.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: NkColors.brand50,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_fire_department,
                              size: 10, color: NkColors.brand),
                          SizedBox(width: 3),
                          Text(
                            '${ProfileData.streak}-day streak',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: NkColors.brand,
                            ),
                          ),
                        ],
                      ),
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
          // Civic score card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [NkColors.brand, NkColors.brand700, NkColors.brandDark],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: NkColors.brand.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 13, color: NkColors.emerald100),
                            SizedBox(width: 4),
                            Text(
                              'Civic Score',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: NkColors.emerald100,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text(
                              '${ProfileData.civicScore}',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Golden-ticket tier chip with notch dots
                            Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: nkGoldGradient,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ProfileData.level.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                      color: NkColors.brandDark,
                                    ),
                                  ),
                                ),
                                for (final side in [-1, 1])
                                  Positioned(
                                    left: side == -1 ? -4 : null,
                                    right: side == 1 ? -4 : null,
                                    child: Container(
                                      height: 8,
                                      width: 8,
                                      decoration: const BoxDecoration(
                                        color: NkColors.brand,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              Icons.star,
                              size: 12,
                              color: i < ProfileData.rating.round()
                                  ? NkColors.amber300
                                  : Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '${ProfileData.rating}/5 rating',
                          style: TextStyle(
                              fontSize: 10, color: NkColors.emerald100),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(ProfileData.level,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: NkColors.emerald100)),
                    const Text(
                      '${ProfileData.toNext} pts to ${ProfileData.nextLevel}',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: NkColors.emerald100),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    children: [
                      Container(
                          height: 8,
                          color: Colors.white.withValues(alpha: 0.2)),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: pctInTier),
                        duration: const Duration(milliseconds: 800),
                        curve: NkMotion.settle,
                        builder: (context, v, _) => FractionallySizedBox(
                          widthFactor: v,
                          child: Container(
                            height: 8,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  NkColors.amber300,
                                  Color(0xFFFEF08A),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          // Stat tiles
          Row(
            children: [
              for (final (icon, value, label, fg, bg) in [
                (
                  Icons.assignment_outlined,
                  '${ProfileData.reports}',
                  'Reports',
                  NkColors.brand,
                  NkColors.brand50
                ),
                (
                  Icons.thumb_up_outlined,
                  '${ProfileData.upvotes}',
                  'Upvotes',
                  NkColors.teal700,
                  NkColors.teal50
                ),
                (
                  Icons.check_circle_outline,
                  '${ProfileData.resolved}',
                  'Resolved',
                  NkColors.emerald700,
                  NkColors.emerald50
                ),
                (
                  Icons.emoji_events_outlined,
                  ProfileData.rank,
                  'Rank',
                  NkColors.slate600,
                  NkColors.slate100
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
                if (label != 'Rank') const SizedBox(width: 8),
              ],
            ],
          ),

          const SizedBox(height: 12),
          // Impact banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [NkColors.emerald50, NkColors.teal50],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NkColors.emerald100),
            ),
            child: Row(
              children: [
                const Text('🙌', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: "You've improved ",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: NkColors.emerald900,
                            height: 1.35,
                          ),
                          children: [
                            TextSpan(
                              text:
                                  '${ProfileData.streets}+ streets & public spaces',
                              style:
                                  const TextStyle(color: NkColors.emerald700),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "Thank you for building a better Tamil Nadu. — Hon'ble CM",
                        style: TextStyle(
                          fontSize: 11,
                          color: NkColors.emerald700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

class _ConstituencyHighlights extends StatelessWidget {
  const _ConstituencyHighlights({
    required this.constituency,
    required this.onConstituencyChanged,
    required this.onOpenStory,
  });

  final String constituency;
  final ValueChanged<String> onConstituencyChanged;
  final ValueChanged<Story> onOpenStory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Constituency highlights',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: NkColors.slate900,
                ),
              ),
              // AC selector pill
              Container(
                padding: const EdgeInsets.only(left: 10, right: 6),
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: NkColors.slate200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place, size: 12, color: NkColors.brand),
                    const SizedBox(width: 2),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: constituency,
                        isDense: true,
                        borderRadius: BorderRadius.circular(14),
                        icon: const Icon(Icons.keyboard_arrow_down,
                            size: 14, color: NkColors.slate400),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: NkColors.slate700,
                        ),
                        items: [
                          for (final c in kConstituencies)
                            DropdownMenuItem(
                              value: c,
                              child: Text(shortAC(c),
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) onConstituencyChanged(v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: kStories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final s = kStories[i];
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onOpenStory(s);
                  },
                  child: SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    NkColors.gold200,
                                    NkColors.gold300,
                                    NkColors.gold400,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Image.asset(
                                    s.slides.first.asset,
                                    height: 60,
                                    width: 60,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            if (s.count > 0)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  height: 20,
                                  constraints:
                                      const BoxConstraints(minWidth: 20),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: NkColors.brand,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  child: Text(
                                    '${s.count}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          s.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            color: NkColors.slate600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
