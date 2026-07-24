import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/profile_data.dart';
import '../../state/providers.dart';

/// Edit Profile — reached from the pencil icon on the home profile panel.
/// Placeholder form for now (name / photo / mobile); the save flow lands in
/// a follow-up. Pushed with Navigator so back returns to the home screen
/// with the profile panel state untouched.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _name;
  final _mobile = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: ref.read(prefsProvider).citizenName);
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    super.dispose();
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: NkColors.slate400, fontSize: 14),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NkColors.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NkColors.brand, width: 1.6),
        ),
      );

  Widget _label(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 12, color: NkColors.slate500),
            const SizedBox(width: 6),
            Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: NkColors.slate500,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCFD),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: back + title
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back,
                        size: 20, color: NkColors.slate700),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Edit Profile',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: NkColors.slate900,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: NkColors.slate200),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                children: [
                  // Photo placeholder
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            gradient: nkGoldGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            height: 84,
                            width: 84,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: NkColors.slate100,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                            ),
                            child: Text(
                              ProfileData.initialsOf(_name.text),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: NkColors.brand,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            height: 30,
                            width: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: NkColors.brand,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.photo_camera_outlined,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Change photo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: NkColors.brand,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  _label(Icons.person_outline, 'Full name'),
                  TextField(
                    controller: _name,
                    decoration: _dec('As per your ID'),
                  ),

                  const SizedBox(height: 16),
                  _label(Icons.smartphone, 'Aadhaar-linked mobile'),
                  TextField(
                    controller: _mobile,
                    keyboardType: TextInputType.phone,
                    decoration: _dec('98xxx xxxxx'),
                  ),

                  const SizedBox(height: 28),
                  // Save is wired up in a follow-up; disabled for now.
                  Opacity(
                    opacity: 0.45,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: nkBrandGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check, size: 16, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Save changes',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      'Profile editing is illustrative in this pilot.',
                      style:
                          TextStyle(fontSize: 11, color: NkColors.slate400),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
