import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'theme.dart';

/// App language. `en` is the source language — every UI string is written in
/// English and looked up in [_ta] when the app is in Tamil mode.
enum AppLang { en, ta }

/// Persisted language selection. Toggle from [LangToggle]; read anywhere via
/// `context.lang` and translate with `context.tr('English string')`.
class LangNotifier extends Notifier<AppLang> {
  static const _key = 'nk_app_lang';

  @override
  AppLang build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    return raw == 'ta' ? AppLang.ta : AppLang.en;
  }

  void set(AppLang lang) {
    state = lang;
    ref.read(sharedPreferencesProvider).setString(_key, lang.name);
  }

  void toggle() => set(state == AppLang.en ? AppLang.ta : AppLang.en);
}

final langProvider =
    NotifierProvider<LangNotifier, AppLang>(LangNotifier.new);

/// Inherited carrier so any widget can translate via [BuildContext] without a
/// WidgetRef. [app.dart] rebuilds this above every route when the language
/// changes, so all descendants re-translate.
class AppL10n extends InheritedWidget {
  const AppL10n({super.key, required this.lang, required super.child});

  final AppLang lang;

  static AppLang of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<AppL10n>();
    return w?.lang ?? AppLang.en;
  }

  @override
  bool updateShouldNotify(AppL10n old) => old.lang != lang;
}

extension L10nX on BuildContext {
  AppLang get lang => AppL10n.of(this);

  /// Translate [en] to the current language. Unknown strings pass through as
  /// English, so partial coverage degrades gracefully.
  String tr(String en) {
    if (AppL10n.of(this) == AppLang.en) return en;
    return _ta[en] ?? en;
  }
}

/// Compact EN | த pill toggle. [onDark] styles it for a navy header.
class LangToggle extends ConsumerWidget {
  const LangToggle({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final trackBg = onDark
        ? Colors.white.withValues(alpha: 0.12)
        : NkColors.slate100;
    final trackBorder = onDark
        ? Colors.white.withValues(alpha: 0.2)
        : NkColors.slate200;
    final inactive = onDark
        ? Colors.white.withValues(alpha: 0.6)
        : NkColors.slate500;

    Widget seg(String label, AppLang value) {
      final active = lang == value;
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(langProvider.notifier).set(value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? NkColors.gold300 : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active ? NkColors.brandDark : inactive,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: trackBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('EN', AppLang.en), seg('த', AppLang.ta)],
      ),
    );
  }
}

/// English → Tamil dictionary. Keyed by the exact English source string.
const Map<String, String> _ta = {
  // ── Roles / toggle ──
  'Citizen': 'குடிமகன்',
  'Coordinator': 'ஒருங்கிணைப்பாளர்',

  // ── Splash / brand ──
  'CITIZEN SIGN IN': 'குடிமகன் உள்நுழைவு',
  'One account per mobile number': 'ஒரு மொபைல் எண்ணுக்கு ஒரு கணக்கு',
  'COORDINATOR CONSOLE': 'ஒருங்கிணைப்பாளர் பலகை',
  'Constituency staff portal': 'தொகுதி பணியாளர் நுழைவாயில்',

  // ── Citizen login ──
  'FULL NAME': 'முழு பெயர்',
  'As per your records': 'உங்கள் பதிவுகளின்படி',
  'MOBILE NUMBER': 'மொபைல் எண்',
  'Send OTP': 'OTP அனுப்பு',
  'Resend': 'மீண்டும் அனுப்பு',
  'ENTER OTP': 'OTP உள்ளிடவும்',
  'Login': 'உள்நுழை',
  'New numbers are registered automatically on first login':
      'புதிய எண்கள் முதல் உள்நுழைவில் தானாகவே பதிவு செய்யப்படும்',
  'Enter a valid 10-digit mobile number first.':
      'முதலில் சரியான 10 இலக்க மொபைல் எண்ணை உள்ளிடவும்.',
  'Enter your name and mobile number, then tap Send OTP.':
      'உங்கள் பெயர் மற்றும் மொபைல் எண்ணை உள்ளிட்டு OTP அனுப்பு என்பதைத் தட்டவும்.',
  'Enter the 6-digit OTP sent to your mobile.':
      'உங்கள் மொபைலுக்கு அனுப்பப்பட்ட 6 இலக்க OTP-ஐ உள்ளிடவும்.',

  // ── Coordinator login ──
  'Welcome back 👋': 'மீண்டும் வரவேற்கிறோம் 👋',
  'Sign in to manage grievances and community posts.':
      'குறைகள் மற்றும் சமூக இடுகைகளை நிர்வகிக்க உள்நுழையவும்.',
  'USERNAME': 'பயனர்பெயர்',
  'PASSWORD': 'கடவுச்சொல்',
  'Sign In': 'உள்நுழை',
  'Accounts are created in the /admin coordinators panel — no demo profiles are shipped in the app.':
      'கணக்குகள் /admin ஒருங்கிணைப்பாளர் பலகையில் உருவாக்கப்படுகின்றன — செயலியில் மாதிரி கணக்குகள் இல்லை.',
  'Invalid username or password.': 'தவறான பயனர்பெயர் அல்லது கடவுச்சொல்.',

  // ── Greetings ──
  'Good morning': 'காலை வணக்கம்',
  'Good afternoon': 'மதிய வணக்கம்',
  'Good evening': 'மாலை வணக்கம்',

  // ── Profile tiles ──
  'Reports': 'புகார்கள்',
  'Upvotes': 'ஆதரவுகள்',
  'Resolved': 'தீர்க்கப்பட்டது',
  'Open': 'நிலுவையில்',
  'Sign out': 'வெளியேறு',

  // ── Home v4 (reference UI) ──
  'Submit Your Grievance': 'உங்கள் குறையைச் சமர்ப்பிக்கவும்',
  'In my Ward': 'என் வார்டில்',
  'My Supports': 'என் ஆதரவுகள்',
  'In-progress': 'செயலில்',
  'Language': 'மொழி',
  'Cancel': 'ரத்து',
  'Search by ticket number, title or area.':
      'டிக்கெட் எண், தலைப்பு அல்லது பகுதி மூலம் தேடுங்கள்.',
  'No grievances match that search.':
      'அந்தத் தேடலுக்குப் பொருந்தும் குறைகள் இல்லை.',

  // ── Home / map ──
  'Grievance map': 'குறை வரைபடம்',
  'Ward grievance map': 'வார்டு குறை வரைபடம்',
  'Tap a pin for details': 'விவரங்களுக்கு ஒரு குறியைத் தட்டவும்',
  'Search ticket no. or grievance nearby':
      'டிக்கெட் எண் அல்லது அருகிலுள்ள குறையைத் தேடுங்கள்',
  'Search grievances in this ward': 'இந்த வார்டில் குறைகளைத் தேடுங்கள்',
  'In My Ward': 'என் வார்டில்',
  'My Reports': 'என் புகார்கள்',
  'Public grievances in your ward': 'உங்கள் வார்டில் பொது குறைகள்',
  'Refresh': 'புதுப்பி',
  'Refresh location': 'இருப்பிடத்தைப் புதுப்பி',
  'Locating your ward…': 'உங்கள் வார்டைக் கண்டறிகிறது…',
  'Detecting zone…': 'மண்டலம் கண்டறியப்படுகிறது…',
  'Outside GCC limits': 'GCC எல்லைக்கு வெளியே',
  'No ward boundary here': 'இங்கு வார்டு எல்லை இல்லை',
  'Ward': 'வார்டு',
  'CONSTITUENCY': 'தொகுதி',
  'WARD': 'வார்டு',

  // ── Legend / statuses ──
  'Assigned': 'ஒதுக்கப்பட்டது',
  'In Progress': 'செயலில் உள்ளது',
  'Verification Pending': 'சரிபார்ப்பு நிலுவையில்',
  'Marked as false petition': 'தவறான மனுவாகக் குறிக்கப்பட்டது',
  'Pending Verification': 'சரிபார்ப்பு நிலுவையில்',
  'Completed': 'முடிந்தது',
  'Submitted': 'சமர்ப்பிக்கப்பட்டது',
  'Verification': 'சரிபார்ப்பு',

  // ── Issue card ──
  'AI SUMMARY': 'AI சுருக்கம்',
  'Support this grievance': 'இந்த குறையை ஆதரிக்கவும்',
  'High Priority': 'அதிக முன்னுரிமை',
  'Medium': 'நடுத்தரம்',
  'Low': 'குறைவு',

  // ── Report sheet ──
  'Report Street Issue': 'தெரு பிரச்சினையைப் புகாரளி',
  'Help us build better and safer streets':
      'சிறந்த, பாதுகாப்பான தெருக்களை உருவாக்க உதவுங்கள்',
  'Fair use policy': 'நியாயமான பயன்பாட்டுக் கொள்கை',
  'You can report 1 grievance per day.':
      'ஒரு நாளைக்கு 1 குறையை மட்டுமே பதிவு செய்யலாம்.',
  'remaining today': 'இன்று மீதம்',
  'Current Location': 'தற்போதைய இருப்பிடம்',
  'Upload Photo': 'புகைப்படம் பதிவேற்று',
  'Add clear photos of the issue': 'பிரச்சினையின் தெளிவான புகைப்படங்களைச் சேர்க்கவும்',
  'Record Voice': 'குரல் பதிவு',
  'Describe the issue in your voice': 'பிரச்சினையை உங்கள் குரலில் விவரிக்கவும்',
  'Your report helps us build better communities':
      'உங்கள் புகார் சிறந்த சமூகங்களை உருவாக்க உதவுகிறது',
  'Capture photo': 'புகைப்படம் எடு',
  'Record voice': 'குரல் பதிவு',
  'Voice note': 'குரல் குறிப்பு',
  'Live photo': 'நேரடி புகைப்படம்',
  'Swipe to submit grievance': 'குறையைச் சமர்ப்பிக்க இழுக்கவும்',
  'Add a photo or a voice note to describe the issue.':
      'பிரச்சினையை விவரிக்க புகைப்படம் அல்லது குரல் குறிப்பைச் சேர்க்கவும்.',
  'Grievance Submitted': 'குறை சமர்ப்பிக்கப்பட்டது',

  // ── Upvote / support sheet ──
  'Support Grievance': 'குறையை ஆதரி',
  'Swipe to support': 'ஆதரிக்க இழுக்கவும்',

  // ── Coordinator home ──
  'STAFF': 'பணியாளர்',
  'Home ward': 'சொந்த வார்டு',
  'Open grievances in Ward': 'வார்டில் திறந்த குறைகள்',
  'Assigned to me': 'எனக்கு ஒதுக்கப்பட்டவை',
  'Escalated grievances': 'மேல்முறையீட்டு குறைகள்',
  'Resolved & closed': 'தீர்க்கப்பட்டு மூடப்பட்டவை',
  'Escalated': 'மேல்முறையீடு',
  'Assign Grievance': 'குறையை ஒதுக்கு',
  'False Petition': 'தவறான மனு',
  'Dept. Transfer': 'துறை மாற்றம்',
  'Transferred': 'மாற்றப்பட்டது',
  'Escalate': 'மேல்முறையீடு',
  'Close': 'மூடு',
  'Assigning…': 'ஒதுக்குகிறது…',
  'Recent': 'சமீபத்தியது',
  'Priority': 'முன்னுரிமை',
  'Rejected — review ASAP': 'நிராகரிக்கப்பட்டது — உடனே பரிசீலி',

  // ── Notifications ──
  'Notifications': 'அறிவிப்புகள்',
  'No notifications': 'அறிவிப்புகள் இல்லை',
  'Clear all': 'அனைத்தையும் அழி',
  'UPDATE': 'புதுப்பிப்பு',
  'NEW GRIEVANCE': 'புதிய குறை',
  'ASSIGNED': 'ஒதுக்கப்பட்டது',
  'TRANSFERRED': 'மாற்றப்பட்டது',
  'ESCALATED': 'மேல்முறையீடு',
  'RESOLVED': 'தீர்க்கப்பட்டது',
  'FLAGGED': 'குறிக்கப்பட்டது',
};
