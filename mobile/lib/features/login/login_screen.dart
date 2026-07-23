import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../shared/wave_mark.dart';

/// Citizen sign-in — port of app/login/page.js. Aadhaar/Voter-ID + MOCK OTP
/// (illustrative PoC auth: any 6-digit code verifies; demo code shown inline).
/// The "Continue as Raj Kumar" pill autofills everything and signs in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _demo = (
    name: 'Raj Kumar',
    idType: 'aadhaar',
    id: '4271 8890 1123',
    mobile: '98840 12345',
    password: 'raj@2026',
    otp: '246813',
  );

  final _name = TextEditingController();
  final _id = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();

  String _idType = 'aadhaar';
  bool _otpSent = false;
  String? _error;
  bool _leaving = false;
  Timer? _demoTimer;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _id, _mobile, _password, _otp]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    for (final c in [_name, _id, _mobile, _password, _otp]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _mobileDigits => _mobile.text.replaceAll(RegExp(r'\D'), '');

  bool get _verified =>
      _otpSent && _otp.text.replaceAll(RegExp(r'\D'), '').length == 6;

  bool get _canLogin =>
      _name.text.trim().isNotEmpty &&
      _id.text.trim().isNotEmpty &&
      _mobileDigits.length >= 10 &&
      _password.text.isNotEmpty &&
      _verified;

  void _sendOtp() {
    if (_mobileDigits.length < 10) {
      setState(() => _error = 'Enter the Aadhaar-linked mobile number first.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _otpSent = true;
    });
  }

  Future<void> _finishLogin() async {
    if (_leaving) return;
    _leaving = true;
    await ref
        .read(authProvider.notifier)
        .signIn(_name.text.trim().isEmpty ? _demo.name : _name.text.trim());
    if (mounted) context.go('/home');
  }

  void _submit() {
    if (!_canLogin) {
      setState(
          () => _error = 'Complete every field and verify the OTP to continue.');
      return;
    }
    HapticFeedback.mediumImpact();
    _finishLogin();
  }

  void _demoLogin() {
    HapticFeedback.mediumImpact();
    setState(() {
      _name.text = _demo.name;
      _idType = _demo.idType;
      _id.text = _demo.id;
      _mobile.text = _demo.mobile;
      _password.text = _demo.password;
      _otpSent = true;
      _otp.text = _demo.otp;
      _error = null;
    });
    _demoTimer = Timer(const Duration(milliseconds: 400), _finishLogin);
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: nkNavyGradient),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                const SizedBox(height: 32),
                // Brand lockup
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
                        'CITIZEN SIGN IN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3.1,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                // Form card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4)),
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
                      _label(Icons.person_outline, 'Full name'),
                      TextField(
                        controller: _name,
                        decoration: _dec('As per your ID'),
                      ),
                      const SizedBox(height: 16),

                      _label(
                        _idType == 'aadhaar'
                            ? Icons.badge_outlined
                            : Icons.how_to_vote_outlined,
                        'Identity',
                      ),
                      // Aadhaar / Voter ID segmented toggle
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: NkColors.slate100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            for (final (key, label, icon) in [
                              ('aadhaar', 'Aadhaar', Icons.badge_outlined),
                              ('voter', 'Voter ID', Icons.how_to_vote_outlined),
                            ])
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _idType = key);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    curve: NkMotion.settle,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 7),
                                    decoration: BoxDecoration(
                                      color: _idType == key
                                          ? Colors.white
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: _idType == key
                                          ? [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.06),
                                                blurRadius: 4,
                                                offset: const Offset(0, 1),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(icon,
                                            size: 13,
                                            color: _idType == key
                                                ? NkColors.brand
                                                : NkColors.slate500),
                                        const SizedBox(width: 6),
                                        Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: _idType == key
                                                ? NkColors.brand
                                                : NkColors.slate500,
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
                      const SizedBox(height: 8),
                      TextField(
                        controller: _id,
                        keyboardType: _idType == 'aadhaar'
                            ? TextInputType.number
                            : TextInputType.text,
                        decoration: _dec(_idType == 'aadhaar'
                            ? 'XXXX XXXX XXXX'
                            : 'ABC1234567'),
                      ),
                      const SizedBox(height: 16),

                      _label(Icons.smartphone, 'Aadhaar-linked mobile'),
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
                              onPressed:
                                  _mobileDigits.length >= 10 ? _sendOtp : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: NkColors.brand,
                                disabledBackgroundColor:
                                    NkColors.brand.withValues(alpha: 0.4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
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

                      // OTP (revealed after send) — mock: any 6 digits verify
                      AnimatedSize(
                        duration: const Duration(milliseconds: 350),
                        curve: NkMotion.settle,
                        alignment: Alignment.topCenter,
                        child: !_otpSent
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 8,
                                          ),
                                          decoration: _dec('••••••')
                                              .copyWith(counterText: ''),
                                        ),
                                        if (_verified)
                                          const Padding(
                                            padding:
                                                EdgeInsets.only(right: 12),
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
                                      'OTP sent to +91 ${_mobile.text.isEmpty ? '98xxx xxxxx' : _mobile.text} · demo code 246813',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: NkColors.slate500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),

                      _label(Icons.lock_outline, 'Password'),
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
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: NkColors.rose600,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      // Login CTA
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
                                  color:
                                      NkColors.brand.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Row(
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
                          Text(
                            'Secured by Aadhaar e-KYC · Illustrative PoC',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: NkColors.slate400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                // Demo pill — one-tap fill + sign in
                GestureDetector(
                  onTap: _demoLogin,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 44,
                          width: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: nkGoldGradient,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2),
                          ),
                          child: const Text(
                            'RK',
                            style: TextStyle(
                              fontSize: 14,
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
                              const Text(
                                'Continue as Raj Kumar',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Demo citizen · autofills every field & signs in',
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward,
                            size: 18, color: NkColors.gold200),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'New to Namm Kural? ',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      children: const [
                        TextSpan(
                          text: 'Register with Aadhaar',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: NkColors.gold200,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
