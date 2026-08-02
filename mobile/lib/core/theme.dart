import 'package:flutter/material.dart';

/// Design tokens ported 1:1 from the web app's tailwind.config.js +
/// globals.css. Deep royal navy is the brand, warm gold the accent — white
/// stays the dominant surface (WCAG-AA on white).
class NkColors {
  NkColors._();

  // Brand (royal navy)
  static const brand50 = Color(0xFFEEF2F7);
  static const brand100 = Color(0xFFD0DBE6);
  static const brand200 = Color(0xFF8FA5BE);
  static const brand = Color(0xFF1A3556);
  static const brand700 = Color(0xFF132844);
  static const brandDark = Color(0xFF0D1D34);

  /// The brand blue, sampled straight from the supplied logo SVG (the signal
  /// arcs are filled `#004AAD`). This is the single source of truth for every
  /// blue accent — chips, avatar ring, buttons and labels — so nothing
  /// approximates it any more.
  static const refBlue = Color(0xFF004AAD);

  /// Darkened brand blue for the bottom CTA plate, and the lighter tone its
  /// centre glow blooms to. Both sit on the same hue line as [refBlue].
  static const refBlueDeep = Color(0xFF0A1F45);
  static const refBlueGlow = Color(0xFF12356E);

  // Gold accent (cover emblem tone)
  static const gold100 = Color(0xFFF2E4BC);
  static const gold200 = Color(0xFFDDC689);
  static const gold300 = Color(0xFFC8A04A);
  static const gold400 = Color(0xFFA88535);

  // Tailwind neutrals used across the citizen surface
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);

  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber300 = Color(0xFFFCD34D);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amber800 = Color(0xFF92400E);
  static const yellow400 = Color(0xFFFACC15);

  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald900 = Color(0xFF064E3B);

  static const teal50 = Color(0xFFF0FDFA);
  static const teal700 = Color(0xFF0F766E);

  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose200 = Color(0xFFFECDD3);
  static const rose500 = Color(0xFFF43F5E);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);

  static const sky50 = Color(0xFFF0F9FF);
  static const sky100 = Color(0xFFE0F2FE);
  static const sky700 = Color(0xFF0369A1);

  static const violet50 = Color(0xFFF5F3FF);
  static const violet200 = Color(0xFFDDD6FE);
  static const violet700 = Color(0xFF6D28D9);
}

/// Motion tokens — the web's easing curves.
class NkMotion {
  NkMotion._();

  /// cubic-bezier(0.22, 1, 0.36, 1) — the app-wide "settle" ease.
  static const settle = Cubic(0.22, 1, 0.36, 1);

  /// cubic-bezier(0.34, 1.56, 0.64, 1) — springy overshoot (pop-in).
  static const spring = Cubic(0.34, 1.56, 0.64, 1);
}

/// Login/splash navy wash — linear-gradient(165deg, #1e3a5f, #12233f, #0b1626).
const nkNavyGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1E3A5F), Color(0xFF12233F), Color(0xFF0B1626)],
  stops: [0.0, 0.55, 1.0],
);

/// Brand CTA gradient (from-brand to-brand-dark).
const nkBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [NkColors.brand, NkColors.brandDark],
);

/// Golden ticket / avatar-ring gradient (amber-300 → yellow-400 → amber-500).
const nkGoldGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [NkColors.amber300, NkColors.yellow400, NkColors.amber500],
);

ThemeData buildNkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: NkColors.brand,
      primary: NkColors.brand,
      surface: const Color(0xFFFBFCFD),
    ),
    scaffoldBackgroundColor: const Color(0xFFFBFCFD),
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: NkColors.slate800,
      displayColor: NkColors.slate900,
    ),
    dividerColor: NkColors.slate200,
  );
}
