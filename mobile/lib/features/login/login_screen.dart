import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../shared/splash_wordmark.dart';

/// Combined sign-in — one screen, two roles, switched by the toggle at the
/// top corner:
///   • Citizen     — phase-1 protocol: name + OTP-verified mobile number
///                   (static mock OTP). The backend users table authenticates
///                   a known (phone, name) pair or auto-registers a new one.
///   • Coordinator — username/password with the 4 seeded staff accounts as
///                   tap-to-fill cards.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.intro = false});

  /// True when arriving straight from the splash. The wordmark then starts at
  /// the splash's final size and place — the splash hands over without a
  /// transition — and glides up into the header while the fields fade in.
  /// Any other arrival (signing out) shows the settled layout at once.
  final bool intro;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _coordinator = false;

  /// Resting logo width, as a fraction of the screen.
  static const _restWidthFrac = 0.46;

  /// Gap from the top safe edge to the resting logo, clearing the toggles.
  static const _restTop = 60.0;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
    value: widget.intro ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.intro) {
      // A beat on the splash's final frame before anything moves, so the
      // hand-off reads as the same moment continuing rather than a cut.
      Future.delayed(const Duration(milliseconds: 140), () {
        if (mounted) _intro.forward();
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Widget _roleToggle() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient:
                        _coordinator == coord ? nkWarmWhiteGradient : null,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 14,
                        color: _coordinator == coord
                            ? NkColors.brandDark
                            : Colors.white.withValues(alpha: 0.7),
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
      );

  @override
  Widget build(BuildContext context) {
    final forms = AnimatedSwitcher(
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
          ? const _CoordinatorLoginForm(key: ValueKey('coordinator'))
          : const _CitizenLoginForm(key: ValueKey('citizen')),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        // Flat, and the same navy as the splash: this screen's first frame IS
        // the splash's last one.
        backgroundColor: NkColors.navyPrimary,
        // The logo is placed against the full screen. Letting the keyboard
        // shrink the body would drag it off its mark; the form pads itself
        // for the keyboard instead.
        resizeToAvoidBottomInset: false,
        body: AnimatedBuilder(
          animation: _intro,
          child: forms,
          builder: (context, forms) {
            final screen = MediaQuery.sizeOf(context);
            final safeTop = MediaQuery.paddingOf(context).top;
            final fullW = screen.width * kSplashWordmarkWidthFrac;
            final restScale = _restWidthFrac / kSplashWordmarkWidthFrac;
            final restH = SplashWordmark.heightFor(context, fullW) * restScale;
            final restCenterY = safeTop + _restTop + restH / 2;
            final formTop = safeTop + _restTop + restH + 14;

            final t = _intro.value;
            // The logo glides over the first part, eased at both ends so it
            // settles rather than snaps…
            final move =
                Curves.easeInOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
            // …and the fields fade up through the end of that move.
            final show =
                Curves.easeOut.transform(((t - 0.42) / 0.58).clamp(0.0, 1.0));
            final ready = show > 0.95;

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: formTop,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !ready,
                    child: Opacity(
                      opacity: show,
                      child: Transform.translate(
                        offset: Offset(0, 16 * (1 - show)),
                        child: forms,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: safeTop + 8,
                  left: 16,
                  child: IgnorePointer(
                    ignoring: !ready,
                    child: Opacity(
                      opacity: show,
                      child: const LangToggle(onDark: true),
                    ),
                  ),
                ),
                Positioned(
                  top: safeTop + 8,
                  right: 16,
                  child: IgnorePointer(
                    ignoring: !ready,
                    child: Opacity(opacity: show, child: _roleToggle()),
                  ),
                ),
                // The splash's wordmark, carried on: centred at full size (the
                // splash's last frame), scaling and rising into the header.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Transform.translate(
                      offset: Offset(0, (restCenterY - screen.height / 2) * move),
                      child: Center(
                        child: Transform.scale(
                          scale: 1 + (restScale - 1) * move,
                          child: SplashWordmark(width: fullW),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

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
    // Name first: the server checks the name/number pairing before sending, so
    // require the name here too rather than letting a code go out to a number
    // that login would then reject.
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter your full name first.');
      return;
    }
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
          .requestCitizenOtp(_mobileDigits, name: _name.text.trim());
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

  /// Flat fields sitting directly on the navy — no card behind them.
  ///
  /// Same surface language as the PIN screens and the home bar's search: a
  /// barely-there fill, a hairline edge, and gold only on focus. White-filled
  /// inputs needed the frosted panel to sit on; without it they would be four
  /// bright slabs floating on a dark screen.
  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.38),
          fontSize: 14,
        ),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF0E9DC), width: 1.5),
        ),
      );

  /// Input text has to be light now that the field is dark.
  static const _inputStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  Widget _label(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.55)),
            const SizedBox(width: 6),
            Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Bottom inset by hand: the shell no longer resizes for the keyboard.
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      children: [
        const SizedBox(height: 2),
        Center(
          child: Column(
            children: [
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
        Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label(Icons.person_outline, 'Full name'),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                style: _inputStyle,
                decoration: _dec('As per your records'),
              ),
              const SizedBox(height: 16),
              _label(Icons.smartphone, 'Mobile number'),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20)),
                    ),
                    child: Text(
                      '+91',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      style: _inputStyle,
                      decoration: _dec('98xxx xxxxx'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 46,
                    // Gold, like the Login CTA — a navy button on the navy
                    // sign-in background read as plain text and was easy to miss.
                    child: GestureDetector(
                      onTap: (_name.text.trim().length >= 2 &&
                              _mobileDigits.length >= 10 &&
                              !_sendingOtp)
                          ? _sendOtp
                          : null,
                      child: Opacity(
                        opacity: (_name.text.trim().length >= 2 &&
                                _mobileDigits.length >= 10 &&
                                !_sendingOtp)
                            ? 1
                            : 0.5,
                        child: Container(
                          alignment: Alignment.center,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            gradient: nkWarmWhiteGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _sendingOtp
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: NkColors.brandDark),
                                )
                              : Text(
                                  context.tr(_otpSent ? 'Resend' : 'Send OTP'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: NkColors.brandDark,
                                  ),
                                ),
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
                                    color: Colors.white,
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
                    color: NkColors.rose500.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: NkColors.rose500.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFFB4B4),
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
                      gradient: nkWarmWhiteGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 18,
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
                                color: NkColors.brandDark,
                              ),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login,
                                  size: 16, color: NkColors.brandDark),
                              SizedBox(width: 8),
                              Text(
                                'Login',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: NkColors.brandDark,
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
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _otp = TextEditingController();
  bool _otpSent = false;
  bool _sendingOtp = false;
  String? _devOtp;
  String? _error;
  bool _busy = false;

  String get _mobileDigits => _mobile.text.replaceAll(RegExp(r'\D'), '');

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _mobile.addListener(() => setState(() {}));
    _otp.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _otp.dispose();
    super.dispose();
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      );

  Future<void> _sendOtp() async {
    // The server checks the name + mobile against an admin-created account
    // before sending, so require both here too.
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter your full name first.');
      return;
    }
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
          .coordinatorRequestOtp(_name.text.trim(), _mobileDigits);
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(coordinatorAuthProvider.notifier).signIn(
            name: _name.text.trim(),
            phone: _mobileDigits,
            otp: _otp.text.trim(),
          );
      HapticFeedback.mediumImpact();
      if (mounted) context.go('/coordinator');
    } catch (e) {
      // Backend rejections surface here (bad OTP / mismatch → ApiException).
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Flat fields sitting directly on the navy — no card behind them.
  ///
  /// Same surface language as the PIN screens and the home bar's search: a
  /// barely-there fill, a hairline edge, and gold only on focus. White-filled
  /// inputs needed the frosted panel to sit on; without it they would be four
  /// bright slabs floating on a dark screen.
  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.38),
          fontSize: 14,
        ),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF0E9DC), width: 1.5),
        ),
      );

  /// Input text has to be light now that the field is dark.
  static const _inputStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    final canSubmit = _name.text.trim().length >= 2 &&
        _mobileDigits.length >= 10 &&
        _otpSent &&
        _otp.text.replaceAll(RegExp(r'\D'), '').length == 6;

    return ListView(
      // Bottom inset by hand: the shell no longer resizes for the keyboard.
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      children: [
        const SizedBox(height: 2),
        Center(
          child: Column(
            children: [
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
        Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label('FULL NAME'),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                style: _inputStyle,
                decoration: _dec('As registered by the MLA office'),
              ),
              const SizedBox(height: 14),
              _label('MOBILE NUMBER'),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                    ),
                    child: Text('+91',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.75))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      style: _inputStyle,
                      decoration: _dec('98xxx xxxxx'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 46,
                    child: GestureDetector(
                      onTap: (_name.text.trim().length >= 2 &&
                              _mobileDigits.length >= 10 &&
                              !_sendingOtp)
                          ? _sendOtp
                          : null,
                      child: Opacity(
                        opacity: (_name.text.trim().length >= 2 &&
                                _mobileDigits.length >= 10 &&
                                !_sendingOtp)
                            ? 1
                            : 0.5,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            gradient: nkWarmWhiteGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _sendingOtp
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: NkColors.brandDark))
                              : Text(context.tr(_otpSent ? 'Resend' : 'Send OTP'),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: NkColors.brandDark)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_otpSent
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 14),
                          _label('ENTER OTP'),
                          TextField(
                            controller: _otp,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: _inputStyle.copyWith(letterSpacing: 6),
                            decoration: _dec('••••••'),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _devOtp != null
                                ? 'OTP sent to +91 ${_mobile.text} · demo code $_devOtp'
                                : 'OTP sent to +91 ${_mobile.text}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.45)),
                          ),
                        ],
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
                      gradient: nkWarmWhiteGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 18,
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
                                color: NkColors.brandDark,
                              ),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login,
                                  size: 16, color: NkColors.brandDark),
                              SizedBox(width: 8),
                              Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: NkColors.brandDark,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
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
