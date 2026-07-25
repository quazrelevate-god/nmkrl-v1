import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/constituencies.dart';
import '../../domain/coordinator_data.dart';
import '../../state/providers.dart';
import '../shared/wave_mark.dart';

// ─── Citizen sign-in palette (spec) ─────────────────────────────────────
const _kBg = Color(0xFF122B46);
const _kCard = Color(0xFFF7F1DE);
const _kNavy = Color(0xFF122B46);
const _kGold = Color(0xFFC8A04A);
const _kMuted = Color(0xFF8B93A0);
const _kGreen = Color(0xFF2F9E6E);
const _kBlue = Color(0xFF3F8FD1);

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

  void _setRole(bool coord) {
    if (_coordinator == coord) return;
    HapticFeedback.selectionClick();
    setState(() => _coordinator = coord);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        // Coordinator side keeps the old navy gradient; the citizen form
        // paints its own solid navy + arc-decoration background on top.
        body: Container(
          decoration: const BoxDecoration(gradient: nkNavyGradient),
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
                    ? const _CoordinatorLoginForm(key: ValueKey('coordinator'))
                    : _CitizenLoginForm(
                        key: const ValueKey('citizen'),
                        onSwitchRole: _setRole,
                      ),
              ),

              // Coordinator side keeps its outer floating toggle so the user
              // can flip back; the citizen card has its own toggle inside.
              if (_coordinator)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  right: 16,
                  child: _OuterRoleToggle(onSelect: _setRole),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unchanged floating toggle overlay — shown only on the coordinator screen
/// (citizen has an in-card variant that matches the new visual language).
class _OuterRoleToggle extends StatelessWidget {
  const _OuterRoleToggle({required this.onSelect});

  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              onTap: () => onSelect(coord),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: NkMotion.settle,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: coord ? NkColors.gold300 : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Icon(icon,
                        size: 14,
                        color: coord
                            ? NkColors.brandDark
                            : Colors.white.withValues(alpha: 0.7)),
                    if (coord) ...[
                      const SizedBox(width: 5),
                      Text(tip,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: NkColors.brandDark,
                          )),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Faint arc-cluster background decoration for the citizen screen ────

class _ArcBackgroundPainter extends CustomPainter {
  const _ArcBackgroundPainter();

  static const _opacity = 0.08;
  static const _stroke = Color(0xFFEADFBF);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _stroke.withValues(alpha: _opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Bottom-left cluster: arcs opening up-and-right from a source just
    // outside the corner (matches the app's signal-wave motif, scaled up).
    final bl = Offset(size.width * -0.02, size.height * 1.02);
    for (var i = 0; i < 4; i++) {
      paint.strokeWidth = 11 - i * 1.5;
      canvas.drawArc(
        Rect.fromCircle(center: bl, radius: size.width * (0.30 + i * 0.22)),
        -math.pi / 2,
        math.pi / 2,
        false,
        paint,
      );
    }

    // Top-right cluster: reflected, opening down-and-left.
    final tr = Offset(size.width * 1.02, size.height * -0.02);
    for (var i = 0; i < 3; i++) {
      paint.strokeWidth = 10 - i * 1.5;
      canvas.drawArc(
        Rect.fromCircle(center: tr, radius: size.width * (0.28 + i * 0.20)),
        math.pi / 2,
        math.pi / 2,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcBackgroundPainter old) => false;
}

/* ═══════════════════════ Citizen form ═══════════════════════ */

class _CitizenLoginForm extends ConsumerStatefulWidget {
  const _CitizenLoginForm({super.key, required this.onSwitchRole});

  final ValueChanged<bool> onSwitchRole;

  @override
  ConsumerState<_CitizenLoginForm> createState() => _CitizenLoginFormState();
}

class _CitizenLoginFormState extends ConsumerState<_CitizenLoginForm> {
  /// Phase-1 OTP is a static mock — the backend never sees it.
  static const _mockOtp = '246813';

  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _otp = TextEditingController();

  bool _otpSent = false;
  bool _busy = false;
  String? _error;

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

  bool get _otpVerified => _otpSent && _otp.text == _mockOtp;

  bool get _canLogin =>
      !_busy &&
      _name.text.trim().length >= 2 &&
      _mobileDigits.length >= 10 &&
      _otpVerified;

  void _sendOtp() {
    if (_mobileDigits.length < 10) {
      setState(() => _error = 'Enter a valid 10-digit mobile number first.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _otpSent = true;
      _otp.clear();
    });
  }

  Future<void> _submit() async {
    if (!_canLogin) {
      setState(() {
        if (_otpSent && _otp.text.length == 6 && !_otpVerified) {
          _error = 'Incorrect OTP. The demo code is $_mockOtp.';
        } else {
          _error =
              'Enter your name, verify your mobile number with the OTP, then log in.';
        }
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .signIn(name: _name.text.trim(), phone: _mobileDigits);
      HapticFeedback.mediumImpact();
      if (mounted) context.go('/home');
    } catch (e) {
      // Backend rejections surface here — e.g. the phone number is already
      // registered under a different name.
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Field decoration for the reskinned cream card — white fill, hairline
  /// navy-tinted border, navy focus ring.
  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kMuted, fontSize: 14),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kNavy.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kNavy, width: 1.6),
        ),
      );

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: _kNavy,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) {
        return Stack(
          children: [
            // Solid navy background — covers the outer nkNavyGradient so the
            // citizen screen reads as pure #122B46.
            const Positioned.fill(child: ColoredBox(color: _kBg)),
            // Faint radiating-arc decoration (2 clusters, low opacity).
            const Positioned.fill(
              child: CustomPaint(painter: _ArcBackgroundPainter()),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: viewport.maxHeight -
                        MediaQuery.paddingOf(context).vertical -
                        48,
                  ),
                  child: Center(child: _buildCard()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Role toggle (top-right of card) ──
          Align(
            alignment: Alignment.centerRight,
            child: _InCardRoleToggle(
              coordinator: false,
              onSelect: widget.onSwitchRole,
            ),
          ),
          const SizedBox(height: 6),

          // ── Wordmark + signal-wave ──
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: const [
                Text(
                  'நம்குரல்',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1,
                    color: _kNavy,
                  ),
                ),
                Positioned(
                  right: -26,
                  top: -8,
                  child: WaveMark(size: 24),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'CITIZEN SIGN IN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.6,
                color: _kGold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'One account per mobile number',
              style: TextStyle(fontSize: 11, color: _kMuted),
            ),
          ),

          // ── Status legend (decorative, no interaction) ──
          const SizedBox(height: 16),
          const _StatusLegendStrip(),

          // ── Full name ──
          const SizedBox(height: 22),
          _fieldLabel('FULL NAME'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('As per your records'),
          ),

          // ── Mobile number row (+91 chip is read-only) ──
          const SizedBox(height: 16),
          _fieldLabel('MOBILE NUMBER'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Read-only +91 chip — a plain Container/Text (NOT a TextField)
              // so it can never be tapped, focused, or edited.
              Container(
                height: 52,
                width: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kNavy.withValues(alpha: 0.15)),
                ),
                child: const Text(
                  '+91',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _kNavy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: _dec('98xxx xxxxx'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _mobileDigits.length >= 10 ? _sendOtp : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kNavy,
                    disabledBackgroundColor: _kNavy.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _otpSent ? 'Resend' : 'Send OTP',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _kGold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── OTP section (hidden until Send OTP tapped; fade + slide in) ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.12),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                child: child,
              ),
            ),
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.topCenter,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: _otpSent
                ? Padding(
                    key: const ValueKey('otp'),
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _fieldLabel('ENTER OTP'),
                        Stack(
                          alignment: Alignment.centerRight,
                          children: [
                            TextField(
                              controller: _otp,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 8,
                                color: _kNavy,
                              ),
                              decoration:
                                  _dec('••••••').copyWith(counterText: ''),
                            ),
                            if (_otpVerified)
                              const Padding(
                                padding: EdgeInsets.only(right: 12),
                                child: Icon(Icons.check_circle,
                                    size: 20, color: _kGreen),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'OTP sent to +91 ${_mobile.text.isEmpty ? '98xxx xxxxx' : _mobile.text} · demo code $_mockOtp',
                          style: const TextStyle(fontSize: 11, color: _kMuted),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('no-otp')),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

          // ── Login button (gold, always visible, disabled state) ──
          const SizedBox(height: 20),
          _LoginCta(enabled: _canLogin, busy: _busy, onTap: _submit),

          // ── Footnote ──
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 14,
                width: 14,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: _kGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 9, color: Colors.white),
              ),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'New numbers are registered automatically on first login',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _kMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// In-card citizen/coordinator toggle matching the reskinned design.
class _InCardRoleToggle extends StatelessWidget {
  const _InCardRoleToggle({
    required this.coordinator,
    required this.onSelect,
  });

  final bool coordinator;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _kNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (coord, icon, tip) in [
            (false, Icons.person_outline, 'Citizen'),
            (true, Icons.account_balance_outlined, 'Coordinator'),
          ])
            GestureDetector(
              onTap: () => onSelect(coord),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: coordinator == coord ? _kNavy : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 14,
                        color: coordinator == coord ? _kCard : _kMuted),
                    if (coordinator == coord) ...[
                      const SizedBox(width: 5),
                      Text(
                        tip,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _kCard,
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
  }
}

/// Decorative status legend on the login card — 4 colored dots + labels.
/// No interactive behavior (spec).
class _StatusLegendStrip extends StatelessWidget {
  const _StatusLegendStrip();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Color(0xFF122B46), 'Assigned'),
      (_kBlue, 'In progress'),
      (_kGold, 'Pending'),
      (_kGreen, 'Resolved'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kNavy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final (color, label) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 8,
                  width: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _kMuted,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Gold "Login →" CTA. Always visible; opacity + hit-test disabled until
/// the parent's validation allows submission.
class _LoginCta extends StatelessWidget {
  const _LoginCta({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Always tappable — `_submit` runs the existing validation and surfaces
    // a specific error ("Incorrect OTP" / "Enter your name…"). The reduced
    // opacity is the visual "disabled" signal per spec.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.5,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: _kGold,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _kGold.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: busy
              ? const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: _kNavy,
                    ),
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _kNavy,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 17, color: _kNavy),
                  ],
                ),
        ),
      ),
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
    setState(() => _error = null);
    final c = await ref
        .read(coordinatorAuthProvider.notifier)
        .signIn(_username.text, _password.text);
    if (c == null) {
      setState(() => _error = 'Invalid username or password.');
      return;
    }
    HapticFeedback.mediumImpact();
    if (mounted) context.go('/coordinator');
  }

  void _quickPick(Coordinator c) {
    HapticFeedback.selectionClick();
    setState(() {
      _username.text = c.username;
      _password.text = c.password;
      _error = null;
    });
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

  @override
  Widget build(BuildContext context) {
    final canSubmit = _username.text.isNotEmpty && _password.text.isNotEmpty;

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
                'COORDINATOR CONSOLE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3.1,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Constituency staff portal',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Welcome back 👋',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: NkColors.slate900,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Sign in to manage grievances and community posts.',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: NkColors.rose50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style:
                        const TextStyle(fontSize: 12, color: NkColors.rose600),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: canSubmit ? _submit : null,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: canSubmit ? 1 : 0.5,
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
                    child: const Row(
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
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'DEMO COORDINATORS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
        for (final c in kCoordinators)
          GestureDetector(
            onTap: () => _quickPick(c),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: nkGoldGradient,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3), width: 2),
                    ),
                    child: Text(
                      c.initials,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: NkColors.brandDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${c.role} · ${shortAC(c.constituency)} · Ward ${c.homeWard}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            for (final cred in [c.username, c.password])
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  cred,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: NkColors.gold200,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward,
                      size: 16, color: NkColors.gold200),
                ],
              ),
            ),
          ),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Tap a row to autofill · illustrative PoC auth',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
