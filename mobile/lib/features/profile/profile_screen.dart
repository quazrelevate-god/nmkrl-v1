import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../domain/constituencies.dart';
import '../../domain/coordinator_data.dart';
import '../../domain/profile_data.dart';
import '../../state/providers.dart';

/// App bar + role pill + coordinator avatar — the app's one brand navy.
const _kBlue = NkColors.navyPrimary;
const _kDarkNavy = Color(0xFF1A2A3A);

/// Public privacy policy, required by Google Play (location, mic, phone number)
/// and linked from here. Served by the web app alongside the admin console.
const _kPrivacyUrl = 'https://nmkrl-v1-production.up.railway.app/privacy';
const _kRose = Color(0xFFE53935);

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.watch(coordinatorAuthProvider);
    final isCoordinator = coordinator != null;
    final prefs = ref.watch(prefsProvider);
    // Citizen-only profile picture (local to the device).
    final avatarPath = isCoordinator ? null : ref.watch(avatarProvider);

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
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: isCoordinator
                                  ? _kBlue
                                  : NkColors.slate100,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2.5),
                            ),
                            child: avatarPath != null
                                ? Image.file(
                                    File(avatarPath),
                                    height: 84,
                                    width: 84,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Text(
                                      initials,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: NkColors.brand,
                                      ),
                                    ),
                                  )
                                : Text(
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
                        // Citizens can set a profile picture; a camera badge
                        // opens the picker. Coordinators keep the online dot.
                        if (!isCoordinator)
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: GestureDetector(
                              onTap: () => _changeAvatar(context, ref, hasAvatar: avatarPath != null),
                              child: Container(
                                height: 28,
                                width: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _kBlue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2.5),
                                ),
                                child: const Icon(Icons.camera_alt,
                                    size: 13, color: Colors.white),
                              ),
                            ),
                          )
                        else
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile editing coming soon'),
                              duration: Duration(seconds: 2),
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

                  // Language — moved off the home app bar so that bar matches
                  // the reference (wordmark + search + bell + avatar only).
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                    child: Row(
                      children: [
                        const Icon(Icons.translate,
                            size: 18, color: NkColors.slate500),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.tr('Language'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: NkColors.slate800,
                            ),
                          ),
                        ),
                        const LangToggle(),
                      ],
                    ),
                  ),

                  // Privacy policy + account deletion. Citizens only — a
                  // coordinator account is created and removed by the MLA
                  // office, not self-service, and the privacy link is a Play
                  // Store requirement for the citizen app people install.
                  if (!isCoordinator) ...[
                    const SizedBox(height: 16),
                    Container(
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
                        children: [
                          _actionRow(
                            context,
                            icon: Icons.privacy_tip_outlined,
                            label: context.tr('Privacy policy'),
                            onTap: () => _openPrivacy(context),
                          ),
                          _div(),
                          _actionRow(
                            context,
                            icon: Icons.delete_outline,
                            label: context.tr('Delete account'),
                            tone: _kRose,
                            onTap: () => _confirmDelete(context, ref),
                          ),
                        ],
                      ),
                    ),
                  ],
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

  Widget _actionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? tone,
  }) {
    final color = tone ?? NkColors.slate800;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: tone ?? NkColors.slate500),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: color),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _changeAvatar(BuildContext context, WidgetRef ref,
      {required bool hasAvatar}) async {
    HapticFeedback.selectionClick();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: _kBlue),
              title: Text(context.tr('Take a photo')),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: _kBlue),
              title: Text(context.tr('Choose from gallery')),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: _kRose),
                title: Text(context.tr('Remove photo'),
                    style: const TextStyle(color: _kRose)),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'remove') {
      await ref.read(avatarProvider.notifier).clear();
      return;
    }
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (file == null) return;
      await ref.read(avatarProvider.notifier).setFromFile(file.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Could not set the photo.'))),
        );
      }
    }
  }

  Future<void> _openPrivacy(BuildContext context) async {
    final uri = Uri.parse(_kPrivacyUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Could not open the privacy policy.'))),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Delete your account?')),
        content: Text(context.tr(
          'This removes your name, phone number and voice notes for good. The '
          'grievances you reported stay as anonymous civic records so they can '
          'still be fixed. This cannot be undone.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: _kRose),
            child: Text(context.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).deleteAccount();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
      return;
    }
    // The account is gone on the server; end the local session and leave.
    await ref.read(authProvider.notifier).signOut();
    if (context.mounted) context.go('/login');
  }
}
