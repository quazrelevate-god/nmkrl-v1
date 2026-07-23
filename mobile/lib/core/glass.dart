import 'dart:ui';

import 'package:flutter/material.dart';

/// iOS-style glassmorphism, ported from the web's globals.css glass classes.
///
///   .glass         → [Glass.regular]  (white .62, blur 20, border white .55)
///   .glass-strong  → [Glass.strong]   (white .82, blur 24, border white .60)
///   .glass-clear   → [Glass.clear]    (white .10, blur 24, border white .35)
///   .glass-dark    → [Glass.dark]     (slate .55, blur 18, border white .12)
///
/// The CSS also applies saturate(180%); we reproduce it by composing a
/// saturation color-matrix with the blur, so content behind the glass pops
/// the same way it does on iOS.
enum Glass { regular, strong, clear, dark }

/// 5x4 color matrix boosting saturation (s = 1.8, luma-weighted).
List<double> _saturationMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  return <double>[
    sr + s, sg, sb, 0, 0,
    sr, sg + s, sb, 0, 0,
    sr, sg, sb + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.variant = Glass.regular,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.boxShadow,
    this.padding,
    this.margin,
  });

  final Widget child;
  final Glass variant;
  final BorderRadius borderRadius;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  ({Color fill, Color border, double blur}) get _spec => switch (variant) {
        Glass.regular => (
            fill: Colors.white.withValues(alpha: 0.62),
            border: Colors.white.withValues(alpha: 0.55),
            blur: 20,
          ),
        Glass.strong => (
            fill: Colors.white.withValues(alpha: 0.82),
            border: Colors.white.withValues(alpha: 0.60),
            blur: 24,
          ),
        Glass.clear => (
            fill: Colors.white.withValues(alpha: 0.10),
            border: Colors.white.withValues(alpha: 0.35),
            blur: 24,
          ),
        Glass.dark => (
            fill: const Color(0xFF0F172A).withValues(alpha: 0.55),
            border: Colors.white.withValues(alpha: 0.12),
            blur: 18,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final filter = ImageFilter.compose(
      outer: ColorFilter.matrix(_saturationMatrix(1.8)),
      inner: ImageFilter.blur(sigmaX: spec.blur, sigmaY: spec.blur),
    );
    final glass = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: filter,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: spec.fill,
            borderRadius: borderRadius,
            border: Border.all(color: spec.border),
          ),
          child: child,
        ),
      ),
    );
    if (boxShadow == null && margin == null) return glass;
    return Container(
      margin: margin,
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: boxShadow),
      child: glass,
    );
  }
}

/// Frosted scrim used behind floating modals (.bg-slate-900/45 + blur-md).
class GlassScrim extends StatelessWidget {
  const GlassScrim({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(color: const Color(0xFF0F172A).withValues(alpha: 0.45)),
      ),
    );
  }
}
