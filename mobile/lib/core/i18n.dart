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
            // Warm-white on the dark login header; gold on light surfaces.
            gradient: active && onDark ? nkWarmWhiteGradient : null,
            color: active && !onDark ? NkColors.gold300 : null,
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
  'Pending': 'நிலுவை',
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
  'Search location, issue or ward': 'இடம், குறை அல்லது வார்டைத் தேடுங்கள்',
  'Attach petition document (optional)':
      'மனு ஆவணத்தை இணைக்கவும் (விருப்பத்தேர்வு)',
  // App-open PIN
  'Create a PIN': 'கடவு எண்ணை உருவாக்கவும்',
  'Confirm your PIN': 'கடவு எண்ணை உறுதிப்படுத்தவும்',
  'Enter your PIN': 'உங்கள் கடவு எண்ணை உள்ளிடவும்',
  'Four digits to open the app. You will be asked for this each time.':
      'செயலியைத் திறக்க நான்கு இலக்கங்கள். ஒவ்வொரு முறையும் இது கேட்கப்படும்.',
  'Enter the same four digits once more.':
      'அதே நான்கு இலக்கங்களை மீண்டும் உள்ளிடவும்.',
  'Four digits to unlock the app.': 'செயலியைத் திறக்க நான்கு இலக்கங்கள்.',
  'Those did not match. Start again.':
      'அவை பொருந்தவில்லை. மீண்டும் தொடங்கவும்.',
  'Wrong PIN. Try again.': 'தவறான கடவு எண். மீண்டும் முயற்சிக்கவும்.',
  'Forgot PIN? Sign in again':
      'கடவு எண் மறந்துவிட்டதா? மீண்டும் உள்நுழையவும்',
  'Tap to enter': 'உள்ளிட தட்டவும்',
  'Sign in again': 'மீண்டும் உள்நுழையவும்',
  'Proof of work': 'பணிக்கான ஆதாரம்',
  'Playing…': 'இயங்குகிறது…',
  'This account is no longer available. Sign in again.':
      'இந்தக் கணக்கு இனி கிடைக்கவில்லை. மீண்டும் உள்நுழையவும்.',
  'Welcome back': 'மீண்டும் வருக',
  'In My Ward': 'என் வார்டில்',
  'My Reports': 'என் புகார்கள்',
  'Public grievances in your ward': 'உங்கள் வார்டில் பொது குறைகள்',
  'Refresh': 'புதுப்பி',
  'Refresh location': 'இருப்பிடத்தைப் புதுப்பி',
  'Locating your ward…': 'உங்கள் வார்டைக் கண்டறிகிறது…',
  'Detecting zone…': 'மண்டலம் கண்டறியப்படுகிறது…',
  'Outside corporation limits': 'மாநகராட்சி எல்லைக்கு வெளியே',
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
  'Fair use policy: you can report 1 grievance per day':
      'நியாயமான பயன்பாட்டுக் கொள்கை: ஒரு நாளைக்கு 1 குறை மட்டுமே',
  'Tap to add another': 'மற்றொன்றைச் சேர்க்க தட்டவும்',
  'Tap to stop': 'நிறுத்த தட்டவும்',
  'Photo added': 'புகைப்படம் சேர்க்கப்பட்டது',
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
  // Duplicate review — the coordinator decides whether two reports describe
  // the same problem, and merges them into one ticket if they do.
  'Possible duplicate': 'நகல் இருக்கலாம்',
  // Test-location picker: wards not yet mapped to any constituency.
  'No constituency yet': 'இன்னும் தொகுதி இல்லை',
  'Review': 'பரிசீலி',
  'Already reviewed': 'ஏற்கனவே பரிசீலிக்கப்பட்டது',
  'This grievance was merged into another.':
      'இந்தக் குறை மற்றொன்றுடன் இணைக்கப்பட்டது.',
  'This was confirmed as a separate grievance.':
      'இது தனிக் குறை என உறுதிசெய்யப்பட்டது.',
  'The matching grievance is no longer available.':
      'பொருந்திய குறை இப்போது கிடைக்கவில்லை.',
  'A similar grievance was already reported nearby. Compare them, then merge into one ticket or keep this as its own.':
      'இதே போன்ற குறை அருகில் ஏற்கனவே பதிவாகியுள்ளது. இரண்டையும் ஒப்பிட்டு, ஒரே டிக்கெட்டாக இணைக்கவும் அல்லது இதைத் தனியாக வைக்கவும்.',
  'THIS REPORT': 'இந்தப் புகார்',
  'ALREADY REPORTED': 'ஏற்கனவே பதிவானது',
  'supporting': 'ஆதரவு',
  'Merge into one grievance': 'ஒரே குறையாக இணை',
  'Keep as a separate grievance': 'தனிக் குறையாக வைத்திரு',
  'In Ward': 'வார்டு',
  'merging moves this report to that ward’s ticket.':
      'இணைத்தால் இந்தப் புகார் அந்த வார்டின் டிக்கெட்டுக்கு மாறும்.',
  'Merging keeps this citizen’s photo and voice note as evidence on the original, adds their support to it, and tells them it is being prioritised.':
      'இணைக்கும்போது இந்தக் குடிமகனின் புகைப்படமும் குரல் குறிப்பும் மூலக் குறையில் ஆதாரமாகச் சேர்க்கப்படும், அவரது ஆதரவும் சேரும், முன்னுரிமை அளிக்கப்படுவதாக அவருக்குத் தெரிவிக்கப்படும்.',
  'Dept. Transfer': 'துறை மாற்றம்',
  'Transferred': 'மாற்றப்பட்டது',
  'Escalate': 'மேல்முறையீடு',
  'Close': 'மூடு',
  'Assigning…': 'ஒதுக்குகிறது…',
  'Recent': 'சமீபத்தியது',
  'Grievances outside the corporation limits are not accepted right now':
      'மாநகராட்சி எல்லைக்கு வெளியே உள்ள புகார்கள் தற்போது ஏற்கப்படவில்லை',
  // {corp} is replaced with the live corporation's name after translation.
  'You are outside the {corp} area. New grievances can only be filed inside '
          'it — you can still view your reports and your ward.':
      'நீங்கள் {corp} பகுதிக்கு வெளியே இருக்கிறீர்கள். புதிய புகார்களை அதன் '
          'உள்ளே மட்டுமே பதிவு செய்ய முடியும் — உங்கள் புகார்களையும் உங்கள் '
          'வார்டையும் பார்க்கலாம்.',
  'Already supported this grievance': 'இந்த புகாருக்கு ஏற்கனவே ஆதரவு அளித்துள்ளீர்கள்',
  'Add both a photo and a voice note to submit.':
      'சமர்ப்பிக்க புகைப்படம் மற்றும் குரல் பதிவு இரண்டையும் சேர்க்கவும்.',
  'Add a photo — a voice note alone is not enough.':
      'புகைப்படம் சேர்க்கவும் — குரல் பதிவு மட்டும் போதாது.',
  'Record a voice note — a photo alone is not enough.':
      'குரல் பதிவு செய்யவும் — புகைப்படம் மட்டும் போதாது.',
  'Add a photo and a voice note': 'புகைப்படம் மற்றும் குரல் பதிவு சேர்க்கவும்',
  'Show': 'காட்டு',
  'Sort by': 'வரிசைப்படுத்து',
  'All': 'அனைத்தும்',
  'You have not supported any grievance yet.':
      'நீங்கள் இதுவரை எந்த புகாருக்கும் ஆதரவு அளிக்கவில்லை.',
  'No matching grievances among your supports.':
      'உங்கள் ஆதரவுகளில் பொருந்தும் புகார்கள் இல்லை.',
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
