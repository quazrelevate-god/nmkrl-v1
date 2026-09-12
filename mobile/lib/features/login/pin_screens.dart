import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../shared/wave_mark.dart';

/// The four digits are never stored or transmitted — only
/// `sha256("<userId>:<pin>")`. The account id doubles as the salt, so the same
/// PIN on two accounts produces two different hashes.
String pinDigest(String userId, String pin) =>
    sha256.convert(utf8.encode('$userId:$pin')).toString();

const _kPinLength = 4;

/* ══════════════════════ Shared shell ══════════════════════ */

/// Both PIN screens share one surface: the app's navy wash, blurred, with the
/// wordmark and a single column of content over it. The blur is the point —
/// what is behind stays recognisably the app while being unreadable until the
/// PIN lands.
class _PinScaffold extends StatelessWidget {
  const _PinScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NkColors.navyPrimary,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.12),
                radius: 1.05,
                colors: [
                  NkColors.refBlueGlow,
                  NkColors.navyPrimary,
                  NkColors.brandDark,
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: const SizedBox.expand(),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandLogo(height: 34),
                    const SizedBox(height: 26),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 30),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four rounded boxes that fill as digits arrive.
class _PinBoxes extends StatelessWidget {
  const _PinBoxes({
    required this.filled,
    this.error = false,
    this.shake = 0,
  });

  final int filled;
  final bool error;

  /// 0 → 1 progress of the wrong-PIN shake.
  final double shake;

  @override
  Widget build(BuildContext context) {
    // Three damped swings — enough to read as "no", short enough not to nag.
    final dx = shake == 0
        ? 0.0
        : (1 - shake) * 12 * math.sin(shake * 3 * math.pi * 2);
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_kPinLength, (i) {
          final on = i < filled;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            height: 58,
            width: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: on ? 0.16 : 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: error
                    ? NkColors.rose500
                    : on
                        ? NkColors.gold300
                        : Colors.white.withValues(alpha: 0.22),
                width: on || error ? 1.6 : 1,
              ),
            ),
            // The dot pops rather than appears — the only motion on the
            // screen, so it carries the feedback on its own.
            child: AnimatedScale(
              scale: on ? 1 : 0,
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutBack,
              child: Container(
                height: 12,
                width: 12,
                decoration: BoxDecoration(
                  color: error ? NkColors.rose500 : NkColors.gold300,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Hidden field that owns the real input, so the platform keyboard behaves
/// normally and the boxes are just its visible state.
class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 0,
      width: 0,
      child: Opacity(
        opacity: 0,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_kPinLength),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

Widget _pinError(String? message) => AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: message == null
          ? const SizedBox(height: 0, width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, color: NkColors.rose500),
              ),
            ),
    );

/* ══════════════════════ Create a PIN ══════════════════════ */

/// Shown once, straight after the first successful login — and to every
/// account that predates PINs, which is every account created during testing.
class SetPinScreen extends ConsumerStatefulWidget {
  const SetPinScreen({super.key});

  @override
  ConsumerState<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<SetPinScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _first = '';
  String? _error;
  bool _busy = false;
  /// True once the server has told us this account no longer exists, which no
  /// amount of retyping can fix.
  bool _stranded = false;

  bool get _confirming => _first.isNotEmpty;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String value) async {
    setState(() => _error = null);
    if (value.length < _kPinLength) {
      setState(() {});
      return;
    }
    HapticFeedback.selectionClick();
    if (!_confirming) {
      // First pass: remember it and ask again rather than trusting one entry
      // of four blind digits.
      setState(() {
        _first = value;
        _ctrl.clear();
      });
      return;
    }
    if (value != _first) {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = context.tr('Those did not match. Start again.');
        _first = '';
        _ctrl.clear();
      });
      return;
    }
    await _save(value);
  }

  Future<void> _save(String pin) async {
    setState(() => _busy = true);
    final prefs = ref.read(prefsProvider);
    final userId = prefs.userId;
    final digest = pinDigest(userId, pin);
    try {
      await ref.read(apiClientProvider).setPin(userId: userId, pinHash: digest);
      await prefs.setPinHash(digest);
      ref.read(pinLockProvider.notifier).unlock();
      if (mounted) context.go('/home');
    } catch (e) {
      if (!mounted) return;
      // A 404 here means the device is holding a session for an account the
      // server no longer has — a restored backup, a wiped database, a user
      // deleted in admin. Retyping cannot fix that, so offer the way out
      // rather than leaving the person on a screen they cannot leave.
      final gone = '$e'.toLowerCase().contains('not found');
      setState(() {
        _busy = false;
        _stranded = gone;
        _error = gone
            ? context.tr('This account is no longer available. Sign in again.')
            : '$e';
        _first = '';
        _ctrl.clear();
      });
    }
  }

  Future<void> _signOut() async {
    await ref.read(authProvider.notifier).signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return _PinScaffold(
      title: context.tr(_confirming ? 'Confirm your PIN' : 'Create a PIN'),
      subtitle: context.tr(_confirming
          ? 'Enter the same four digits once more.'
          : 'Four digits to open the app. You will be asked for this each time.'),
      children: [
        _PinField(controller: _ctrl, focusNode: _focus, onChanged: _onChanged),
        _PinBoxes(filled: _ctrl.text.length, error: _error != null),
        _pinError(_error),
        const SizedBox(height: 22),
        if (_stranded)
          TextButton(
            onPressed: _signOut,
            child: Text(
              context.tr('Sign in again'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: NkColors.gold300,
              ),
            ),
          )
        else if (_busy)
          const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: NkColors.gold300),
          )
        else
          GestureDetector(
            onTap: () => _focus.requestFocus(),
            child: Text(
              context.tr('Tap to enter'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
      ],
    );
  }
}

/* ══════════════════════ Unlock ══════════════════════ */

/// The app's front door on every cold start once a PIN exists. Replaces the
/// mobile-number screen entirely — that only comes back on sign-out.
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  String? _error;
  int _attempts = 0;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String value) async {
    setState(() => _error = null);
    if (value.length < _kPinLength) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    final prefs = ref.read(prefsProvider);
    final digest = pinDigest(prefs.userId, value);

    // Local first: the phone is already in this person's hand, and making them
    // wait on a round trip to open their own app would be the wrong trade.
    var ok = prefs.hasPin && prefs.pinHash == digest;
    if (!ok && !prefs.hasPin) {
      // Nothing cached — a reinstall or a second device. Ask the server, and
      // cache the hash on success so the next unlock is instant.
      ok = await ref
          .read(apiClientProvider)
          .verifyPin(userId: prefs.userId, pinHash: digest);
      if (ok) await prefs.setPinHash(digest);
    }
    if (!mounted) return;

    if (ok) {
      HapticFeedback.mediumImpact();
      ref.read(pinLockProvider.notifier).unlock();
      context.go('/home');
      return;
    }

    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _busy = false;
      _attempts++;
      _error = context.tr('Wrong PIN. Try again.');
      _ctrl.clear();
    });
  }

  Future<void> _forgot() async {
    // No reset flow to build: signing out returns them to the OTP login they
    // already know, and setting a PIN again is the next screen after it.
    await ref.read(authProvider.notifier).signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(prefsProvider).citizenName;
    return _PinScaffold(
      title: context.tr('Enter your PIN'),
      subtitle: name.isEmpty || name == 'Citizen'
          ? context.tr('Four digits to unlock the app.')
          : '${context.tr('Welcome back')}, $name.',
      children: [
        _PinField(controller: _ctrl, focusNode: _focus, onChanged: _onChanged),
        AnimatedBuilder(
          animation: _shake,
          builder: (_, __) => _PinBoxes(
            filled: _ctrl.text.length,
            error: _error != null,
            shake: _shake.value,
          ),
        ),
        _pinError(_error),
        const SizedBox(height: 22),
        if (_busy)
          const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: NkColors.gold300),
          )
        else
          GestureDetector(
            onTap: () => _focus.requestFocus(),
            child: Text(
              context.tr('Tap to enter'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
        // Offered only after a couple of failures, so it does not invite a
        // sign-out on the first fumble.
        if (_attempts >= 2) ...[
          const SizedBox(height: 26),
          TextButton(
            onPressed: _forgot,
            child: Text(
              context.tr('Forgot PIN? Sign in again'),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: NkColors.gold300,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
