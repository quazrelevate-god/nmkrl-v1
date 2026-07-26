import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/constituencies.dart';
import '../../domain/coordinator_data.dart';
import '../../domain/profile_data.dart';
import '../../state/providers.dart';
import 'edit_profile_screen.dart';

const _kBlue = Color(0xFF1A3A8F);
const _kDarkNavy = Color(0xFF1A2A3A);
const _kMuted = Color(0xFF7A8799);

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.watch(coordinatorAuthProvider);
    final isCoordinator = coordinator != null;
    final prefs = ref.watch(prefsProvider);

    final name = isCoordinator ? coordinator.name : prefs.citizenName;
    final initials = isCoordinator
        ? coordinator.initials
        : ProfileData.initialsOf(name);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F3FA),
        body: Column(
          children: [
            Container(
              color: _kBlue,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 16, 14),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back,
                            size: 22, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Profile',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                children: [
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: const BoxDecoration(
                            gradient: nkGoldGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            height: 84,
                            width: 84,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isCoordinator
                                  ? _kBlue
                                  : NkColors.slate100,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2.5),
                            ),
                            child: Text(
                              initials,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: isCoordinator
                                    ? const Color(0xFFDDC689)
                                    : NkColors.brand,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            height: 16,
                            width: 16,
                            decoration: BoxDecoration(
                              color: NkColors.emerald500,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          name.isNotEmpty ? name : 'User',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _kDarkNavy,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const EditProfileScreen(),
                            ),
                          );
                        },
                        child: Container(
                          height: 28,
                          width: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: NkColors.slate100,
                            shape: BoxShape.circle,
                            border: Border.all(color: NkColors.slate200),
                          ),
                          child: const Icon(Icons.edit_outlined,
                              size: 14, color: NkColors.slate600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kBlue,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isCoordinator
                            ? 'Staff · ${coordinator.role}'
                            : 'Citizen',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (isCoordinator)
                    _StatsRow(items: [
                      (Icons.star_outline, '${coordinator.civicScore}',
                          'Civic Score', const Color(0xFFD97706)),
                      (Icons.assignment_outlined, '${coordinator.reports}',
                          'Reports', const Color(0xFF3FA8A0)),
                      (Icons.check_circle_outline,
                          '${coordinator.resolved}', 'Resolved',
                          const Color(0xFF2F9E6E)),
                      (Icons.schedule, coordinator.tenure, 'Tenure',
                          const Color(0xFFFF9500)),
                    ])
                  else
                    _StatsRow(items: [
                      (Icons.assignment_outlined, '${ProfileData.reports}',
                          'Reports', const Color(0xFF3FA8A0)),
                      (Icons.thumb_up_outlined, '${ProfileData.upvotes}',
                          'Upvotes', const Color(0xFF2F9E6E)),
                      (Icons.check_circle_outline,
                          '${ProfileData.resolved}', 'Resolved',
                          const Color(0xFF2F9E6E)),
                      (Icons.schedule, '${ProfileData.open}', 'Open',
                          const Color(0xFFFF9500)),
                    ]),
                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: isCoordinator
                          ? _coordTiles(coordinator)
                          : _citizenTiles(prefs, ref),
                    ),
                  ),
                ],
              ),
            ),

            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: GestureDetector(
                  onTap: () async {
                    if (isCoordinator) {
                      await ref
                          .read(coordinatorAuthProvider.notifier)
                          .signOut();
                    } else {
                      await ref.read(authProvider.notifier).signOut();
                    }
                    if (context.mounted) context.go('/login');
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDECEA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout,
                            size: 18, color: Color(0xFFE53935)),
                        SizedBox(width: 8),
                        Text(
                          'Sign out',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE53935),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _citizenTiles(dynamic prefs, WidgetRef ref) {
    final phone = prefs.citizenPhone as String;
    final masked = phone.length >= 6
        ? '+91 ${phone.substring(0, 5)}${'x' * (phone.length - 5)}'
        : (phone.isNotEmpty ? phone : '—');
    return [
      _tile(Icons.smartphone, 'Mobile number', masked),
      _div(),
      _tile(Icons.person_outline, 'Full name',
          (prefs.citizenName as String).isNotEmpty
              ? prefs.citizenName as String
              : '—'),
      _div(),
      _tile(Icons.badge_outlined, 'User ID', ref.read(userIdProvider)),
    ];
  }

  List<Widget> _coordTiles(Coordinator me) {
    return [
      _tile(Icons.person_outline, 'Full name', me.name),
      _div(),
      _tile(Icons.work_outline, 'Role', me.role),
      _div(),
      _tile(Icons.account_balance, 'Constituency', shortAC(me.constituency)),
      _div(),
      _tile(Icons.place_outlined, 'Home ward', 'Ward ${me.homeWard}'),
      _div(),
      _tile(Icons.badge_outlined, 'Username', me.username),
    ];
  }

  Widget _tile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: NkColors.slate400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: NkColors.slate400)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kDarkNavy)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _div() =>
      Divider(height: 1, color: NkColors.slate200.withValues(alpha: 0.7));
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.items});

  final List<(IconData, String, String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 30,
                    width: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: items[i].$4.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(items[i].$1, size: 16, color: items[i].$4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i].$2,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _kDarkNavy,
                    ),
                  ),
                  Text(
                    items[i].$3,
                    style: const TextStyle(fontSize: 11, color: _kMuted),
                  ),
                ],
              ),
            ),
          ),
          if (i < items.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}
