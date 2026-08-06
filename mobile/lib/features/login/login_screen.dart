import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../shared/wave_mark.dart';

/// Combined sign-in — one screen, two roles, switched by the toggle at the
/// top corner:
///   • Citizen     — phase-1 protocol: name + OTP-verified mobile number
///                   (static mock OTP). The backend users table authenticates
///                   a known (phone, name) pair or auto-registers a new one.
///   • Coordinator — username/password with the 4 seeded staff accounts as
///                   tap-to-fill cards.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _coordinator = false;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: nkNavyGradient),
          child: SafeArea(
            child: Stack(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchInCurve: NkMotion.settle,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.02),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _coordinator
                      ? const _CoordinatorLoginForm(
                          key: ValueKey('coordinator'))
                      : const _CitizenLoginForm(key: ValueKey('citizen')),
                ),

                // ── Language toggle (top-left corner) ──
                const Positioned(
                  top: 8,
                  left: 16,
                  child: LangToggle(onDark: true),
                ),

                // ── Role toggle (top corner) ──
                Positioned(
                  top: 8,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (coord, icon, tip) in [
                          (false, Icons.person_outline, 'Citizen'),
                          (true, Icons.account_balance_outlined, 'Coordinator'),
                        ])
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _coordinator = coord);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              curve: NkMotion.settle,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _coordinator == coord
                                    ? NkColors.gold300
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    icon,
                                    size: 14,
                                    color: _coordinator == coord
                                        ? NkColors.brandDark
                                        : Colors.white
                                            .withValues(alpha: 0.7),
                                  ),
                                  if (_coordinator == coord) ...[
                                    const SizedBox(width: 5),
                                    Text(
                                      tip,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: NkColors.brandDark,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ═══════════════════════ Citizen form ═══════════════════════ */

class _CitizenLoginForm extends ConsumerStatefulWidget {
  const _CitizenLoginForm({super.key});

  @override
  ConsumerState<_CitizenLoginForm> createState() => _CitizenLoginFormState();
}

class _CitizenLoginFormState extends ConsumerState<_CitizenLoginForm> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _otp = TextEditingController();

  bool _otpSent = false;
  bool _sendingOtp = false;
  bool _busy = false;
  String? _error;

  /// In dummy mode (no live SMS gateway) the backend returns the code so the
  /// demo flow works; we surface it as a hint. Null once a real gateway sends.
  String? _devOtp;

  @override
  void initState() {
    super.initState();
    // Prefill for returning users (kept across sign-out).
    final prefs = ref.read(prefsProvider);
    if (prefs.accountId != null) {
      _name.text = prefs.citizenName == 'Citizen' ? '' : prefs.citizenName;
      _mobile.text = prefs.citizenPhone;
    }
    for (final c in [_name, _mobile, _otp]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _otp.dispose();
    super.dispose();
  }

  String get _mobileDigits => _mobile.text.replaceAll(RegExp(r'\D'), '');

  bool get _canLogin =>
      !_busy &&
      _name.text.trim().length >= 2 &&
      _mobileDigits.length >= 10 &&
      _otpSent &&
      _otp.text.replaceAll(RegExp(r'\D'), '').length == 6;

  Future<void> _sendOtp() async {
    if (_mobileDigits.length < 10) {
      setState(() => _error = 'Enter a valid 10-digit mobile number first.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _sendingOtp = true;
    });
    try {
      final dev = await ref
          .read(apiClientProvider)
          .requestCitizenOtp(_mobileDigits);
      setState(() {
        _otpSent = true;
        _devOtp = dev;
        _otp.clear();
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _submit() async {
    if (!_canLogin) {
      setState(() => _error = _otpSent
          ? 'Enter the 6-digit OTP sent to your mobile.'
          : 'Enter your name and mobile number, then tap Send OTP.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // OTP is verified server-side inside signIn (login gates on it).
      await ref.read(authProvider.notifier).signIn(
            name: _name.text.trim(),
            phone: _mobileDigits,
            otp: _otp.text.replaceAll(RegExp(r'\D'), ''),
          );
      HapticFeedback.mediumImpact();
      if (mounted) context.go('/home');
    } catch (e) {
      // Backend rejections surface here — wrong OTP, or the phone number is
      // already registered under a different name.
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: NkColors.slate400, fontSize: 14),
        isDense: true,
        filled: true,
        // Brighter than the frosted panel behind it, so the field reads as a
        // lit inset in the glass rather than a flat white block on white.
        fillColor: Colors.white.withValues(alpha: 0.92),
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
            // slate700, not slate500: the frosted panel is translucent over
            // navy, so mid-grey labels lose contrast against it.
            Icon(icon, size: 12, color: NkColors.slate700),
            const SizedBox(width: 6),
            Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: NkColors.slate700,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        // Clears the role toggle floating at the top corner.
        const SizedBox(height: 56),
        Center(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: const [
                  Text(
                    'நம்குரல்',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      height: 1,
                      color: Color(0xFFEADFBF),
                    ),
                  ),
                  Positioned(
                    right: -26,
                    top: -8,
                    child: WaveMark(size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('CITIZEN SIGN IN'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3.1,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('One account per mobile number'),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label(Icons.person_outline, 'Full name'),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _dec('As per your records'),
              ),
              const SizedBox(height: 16),
              _label(Icons.smartphone, 'Mobile number'),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: NkColors.slate50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NkColors.slate200),
                    ),
                    child: const Text(
                      '+91',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: NkColors.slate500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      decoration: _dec('98xxx xxxxx'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: (_mobileDigits.length >= 10 && !_sendingOtp)
                          ? _sendOtp
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: NkColors.brand,
                        disabledBackgroundColor:
                            NkColors.brand.withValues(alpha: 0.4),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _sendingOtp
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _otpSent ? 'Resend' : 'Send OTP',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: NkMotion.settle,
                alignment: Alignment.topCenter,
                child: !_otpSent
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _label(Icons.key, 'Enter OTP'),
                            Stack(
                              alignment: Alignment.centerRight,
                              children: [
                                TextField(
                                  controller: _otp,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  textAlign: TextAlign.center,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 8,
                                  ),
                                  decoration:
                                      _dec('••••••').copyWith(counterText: ''),
                                ),
                                if (_otp.text
                                        .replaceAll(RegExp(r'\D'), '')
                                        .length ==
                                    6)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 12),
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 20,
                                      color: NkColors.emerald500,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _devOtp != null
                                  ? 'OTP sent to +91 ${_mobile.text} · demo code $_devOtp'
                                  : 'OTP sent to +91 ${_mobile.text}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: NkColors.slate500,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: NkColors.rose50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: NkColors.rose600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _submit,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _canLogin ? 1 : 0.45,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: nkBrandGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: NkColors.brand.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _busy
                        ? const Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login,
                                  size: 16, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Login',
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
              ),
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user,
                      size: 11, color: NkColors.emerald500),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'New numbers are registered automatically on first login',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        // slate600 on the translucent panel; slate400 was
                        // legible on solid white but not on frosted glass.
                        color: NkColors.slate600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

/* ═══════════════════════ Coordinator form ═══════════════════════ */

class _CoordinatorLoginForm extends ConsumerStatefulWidget {
  const _CoordinatorLoginForm({super.key});

  @override
  ConsumerState<_CoordinatorLoginForm> createState() =>
      _CoordinatorLoginFormState();
}

class _CoordinatorLoginFormState extends ConsumerState<_CoordinatorLoginForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _username.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(coordinatorAuthProvider.notifier)
          .signIn(_username.text.trim(), _password.text);
      HapticFeedback.mediumImpact();
      if (mounted) context.go('/coordinator');
    } catch (e) {
      // Backend rejections surface here (invalid creds → ApiException).
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: NkColors.slate400, fontSize: 14),
        isDense: true,
        filled: true,
        // Brighter than the frosted panel behind it, so the field reads as a
        // lit inset in the glass rather than a flat white block on white.
        fillColor: Colors.white.withValues(alpha: 0.92),
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

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _username.text.isNotEmpty && _password.text.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        // Clears the role toggle floating at the top corner.
        const SizedBox(height: 56),
        Center(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: const [
                  Text(
                    'நம்குரல்',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      height: 1,
                      color: Color(0xFFEADFBF),
                    ),
                  ),
                  Positioned(
                    right: -26,
                    top: -8,
                    child: WaveMark(size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('COORDINATOR CONSOLE'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3.1,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('Constituency staff portal'),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('Welcome back 👋'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: NkColors.slate900,
                ),
              ),
              const SizedBox(height: 2),
              Text(context.tr('Sign in to manage grievances and community posts.'),
                style: TextStyle(fontSize: 13, color: NkColors.slate500),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'USERNAME',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: NkColors.slate500,
                  ),
                ),
              ),
              TextField(
                controller: _username,
                autocorrect: false,
                decoration: _dec('e.g. raja'),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'PASSWORD',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: NkColors.slate500,
                  ),
                ),
              ),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: _dec('••••••••'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: NkColors.rose50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        fontSize: 12, color: NkColors.rose600),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: canSubmit && !_busy ? _submit : null,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: canSubmit && !_busy ? 1 : 0.5,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: nkBrandGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: NkColors.brand.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _busy
                        ? const Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login, size: 16, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Sign In',
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
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            context.tr('Accounts are created in the /admin coordinators panel — no demo profiles are shipped in the app.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.45),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// The sign-in panel: a frosted glass card over the navy wash.
///
/// A real backdrop blur under a translucent white fill, so the gradient behind
/// reads through the panel instead of being hidden by a flat white block. The
/// fill stays high enough that the dark labels and inputs inside keep their
/// contrast — frosted, not see-through.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            // Top-lit: brighter at the top edge, as glass catches light.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.82),
                Colors.white.withValues(alpha: 0.70),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
