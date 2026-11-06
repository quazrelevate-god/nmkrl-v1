import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/media.dart';
import '../../domain/models/story.dart';

/// How long one frame is held before it advances on its own.
const Duration _kFrameDuration = Duration(seconds: 5);

/// Full-screen story viewer — the Instagram reading model, because that is the
/// one every user already has: timed frames with a segmented progress bar, tap
/// right for the next frame and left for the previous, swipe across for the
/// next ring, swipe down (or the ✕) to close. Holding a finger down pauses.
///
/// It is read-only for citizens. A coordinator opening their OWN ring gets a
/// delete affordance on each frame ([onDelete]); nobody can delete another
/// account's story — the server enforces that too.
class StoryViewer extends StatefulWidget {
  const StoryViewer({
    super.key,
    required this.rings,
    this.initialRing = 0,
    this.onDelete,
    this.ownerUsername,
  });

  final List<StoryRing> rings;
  final int initialRing;
  final ValueChanged<Story>? onDelete;
  final String? ownerUsername;

  static Future<void> open(
    BuildContext context, {
    required List<StoryRing> rings,
    int initialRing = 0,
    ValueChanged<Story>? onDelete,
    String? ownerUsername,
  }) {
    if (rings.isEmpty) return Future.value();
    return Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: NkColors.brandDark,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => StoryViewer(
          rings: rings,
          initialRing: initialRing,
          onDelete: onDelete,
          ownerUsername: ownerUsername,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _rings =
      PageController(initialPage: widget.initialRing);
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _kFrameDuration,
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });

  int _ring = 0;
  int _frame = 0;

  /// Frames removed in this session, so a deleted story disappears at once
  /// instead of waiting for the home screen's next fetch.
  final Set<String> _removed = {};

  @override
  void initState() {
    super.initState();
    _ring = widget.initialRing;
    _progress.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    _rings.dispose();
    super.dispose();
  }

  List<Story> _framesOf(int ringIndex) => [
        for (final s in widget.rings[ringIndex].items)
          if (!_removed.contains(s.id)) s,
      ];

  void _restart() {
    _progress
      ..reset()
      ..forward();
  }

  void _next() {
    final frames = _framesOf(_ring);
    if (_frame + 1 < frames.length) {
      setState(() => _frame++);
      _restart();
      return;
    }
    if (_ring + 1 < widget.rings.length) {
      _rings.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _prev() {
    if (_frame > 0) {
      setState(() => _frame--);
      _restart();
      return;
    }
    if (_ring > 0) {
      _rings.previousPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _restart();
  }

  void _onRingChanged(int i) {
    setState(() {
      _ring = i;
      _frame = 0;
    });
    _restart();
  }

  Future<void> _confirmDelete(Story story) async {
    _progress.stop();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Delete this story?')),
        content: Text(ctx.tr('It disappears from every citizen in the ward.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('Keep')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              ctx.tr('Delete'),
              style: const TextStyle(
                  color: NkColors.rose600, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (yes == true) {
      widget.onDelete?.call(story);
      setState(() {
        _removed.add(story.id);
        if (_frame > 0) _frame--;
      });
      if (_framesOf(_ring).isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
    }
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The brand's own dark, not black: this is a civic
      // noticeboard, and navy is the ground the rest of the app uses.
      backgroundColor: _kStoryBg,
      body: PageView.builder(
        controller: _rings,
        onPageChanged: _onRingChanged,
        itemCount: widget.rings.length,
        itemBuilder: (context, i) {
          final ring = widget.rings[i];
          final frames = _framesOf(i);
          if (frames.isEmpty) return const SizedBox.shrink();
          // Only the ring on screen tracks the live frame index; the ones
          // either side of it render their first frame as a cheap preview.
          final index = i == _ring ? _frame.clamp(0, frames.length - 1) : 0;
          return _RingPage(
            ring: ring,
            frames: frames,
            index: index,
            progress: i == _ring ? _progress : null,
            canDelete: widget.onDelete != null &&
                widget.ownerUsername != null &&
                frames[index].author.toLowerCase() ==
                    widget.ownerUsername!.toLowerCase(),
            onDelete: () => _confirmDelete(frames[index]),
            onTapLeft: _prev,
            onTapRight: _next,
            onHold: (held) => held ? _progress.stop() : _progress.forward(),
            onClose: () => Navigator.of(context).maybePop(),
          );
        },
      ),
    );
  }
}

/// Deep navy ground the viewer sits on — the brand's own dark, not black.
const _kStoryBg = NkColors.brandDark;

/// The caption card's cream, warm enough to read as paper against the navy.
const _kCaptionCream = Color(0xFFFCF7EA);

class _RingPage extends StatefulWidget {
  const _RingPage({
    required this.ring,
    required this.frames,
    required this.index,
    required this.progress,
    required this.canDelete,
    required this.onDelete,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onHold,
    required this.onClose,
  });

  final StoryRing ring;
  final List<Story> frames;
  final int index;

  /// Null for the off-screen neighbours — they draw an empty bar.
  final Animation<double>? progress;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final ValueChanged<bool> onHold;
  final VoidCallback onClose;

  @override
  State<_RingPage> createState() => _RingPageState();
}

class _RingPageState extends State<_RingPage> {
  /// The current photo's width/height, once the decoder has told us.
  ///
  /// The layout needs this BEFORE it can place anything: the whole point is
  /// that the photograph is shown entire and the gold wave meets its real
  /// bottom edge, which is only knowable from the image's own proportions.
  /// Until it resolves the photo takes the full slot, and the wave sits where
  /// it would for a landscape — the common case, so the correction when the
  /// true ratio arrives is usually small or nil.
  double? _aspect;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _resolvedFor;

  Story get _story => widget.frames[widget.index];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _RingPage old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    final url = _story.imageUrl;
    // Advancing a frame rebuilds this page; only re-resolve when the photo
    // behind it actually changed.
    if (url == _resolvedFor) return;
    _resolvedFor = url;
    _detach();
    final provider = mediaImage(url);
    if (provider == null) {
      setState(() => _aspect = null);
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      final a = info.image.width / info.image.height;
      if (mounted && a > 0 && a != _aspect) setState(() => _aspect = a);
    }, onError: (_, __) {
      if (mounted) setState(() => _aspect = null);
    });
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    final image = mediaImage(story.imageUrl);
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── 1. Tap zones, underneath everything. Left third goes back, the
        // rest advances; a long press anywhere pauses, which is the gesture
        // people reach for to read a caption without racing the timer. The
        // layers above are IgnorePointer'd so taps fall through to these —
        // only the close and delete buttons take a hit of their own. ──
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTapLeft,
                onLongPressStart: (_) => widget.onHold(true),
                onLongPressEnd: (_) => widget.onHold(false),
              ),
            ),
            Expanded(
              flex: 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTapRight,
                onLongPressStart: (_) => widget.onHold(true),
                onLongPressEnd: (_) => widget.onHold(false),
              ),
            ),
          ],
        ),

        // ── 2. The story itself ──
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      for (var i = 0; i < widget.frames.length; i++) ...[
                        Expanded(
                          child: _Segment(
                            state: i < widget.index
                                ? 1
                                : i > widget.index
                                    ? 0
                                    : -1,
                            progress:
                                i == widget.index ? widget.progress : null,
                          ),
                        ),
                        if (i != widget.frames.length - 1)
                          const SizedBox(width: 4),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _Header(
                ring: widget.ring,
                story: story,
                canDelete: widget.canDelete,
                onDelete: widget.onDelete,
                onClose: widget.onClose,
              ),

              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    // Room the band needs for its two curves and the card.
                    // The photo may not eat into it, or a long caption would
                    // run off the bottom of the screen.
                    const bandReserve = 250.0;
                    final maxPhotoH = (c.maxHeight - bandReserve)
                        .clamp(c.maxHeight * 0.42, c.maxHeight * 0.82);
                    // The photo's OWN height at this width. A landscape gets
                    // all of it; a portrait taller than the slot is capped
                    // and [BoxFit.contain] keeps it whole inside the cap,
                    // with navy either side rather than a crop.
                    final a = _aspect;
                    final photoH =
                        a == null ? maxPhotoH : math.min(w / a, maxPhotoH);
                    // How far the banner rides UP onto the photograph. Just
                    // enough that the upper wave grazes the bottom edge and
                    // the two read as one piece — the shelf and the capsule
                    // stay clear of the picture. It used to be 44, which put
                    // the cream across the foot of every image and hid part
                    // of what the story was about.
                    const graze = 12.0;
                    // The band's exact height, measured rather than guessed:
                    // the centring below needs it, and an estimate was always
                    // wrong by a line for a long caption.
                    final bandH =
                        _CaptionBand.heightFor(context, w, story.caption);
                    // Centre the photograph and the banner as ONE block, so
                    // the empty navy is shared top and bottom instead of all
                    // falling below a short landscape.
                    final photoTop = math.max(
                        0.0, (c.maxHeight - (photoH + bandH - graze)) / 2);
                    return Stack(
                      children: [
                        Positioned(
                          top: photoTop,
                          left: 0,
                          right: 0,
                          height: photoH,
                          child: IgnorePointer(
                            child: image == null
                                ? const ColoredBox(color: NkColors.brand700)
                                : Image(image: image, fit: BoxFit.contain),
                          ),
                        ),
                        // Hung from the photograph's bottom edge, riding up by
                        // only [graze]. Because the band's height is known,
                        // the whole block can be centred and the banner still
                        // sits at the foot of the picture rather than across
                        // it — a longer caption grows DOWNWARD into the navy,
                        // where there is room, instead of upward over the
                        // image.
                        Positioned(
                          top: photoTop + photoH - graze,
                          left: 0,
                          right: 0,
                          height: bandH,
                          child: IgnorePointer(
                            child: _CaptionBand(caption: story.caption),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ward identity thumbnail, ring title and byline, with the close (and, for
/// your own story, delete) control on the right.
class _Header extends StatelessWidget {
  const _Header({
    required this.ring,
    required this.story,
    required this.canDelete,
    required this.onDelete,
    required this.onClose,
  });

  final StoryRing ring;
  final Story story;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final byline = [
      if (story.authorName.isNotEmpty) story.authorName,
      if (ring.ward != null) '${context.tr('Ward')} ${ring.ward}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
      child: Row(
        children: [
          IgnorePointer(
            child: Container(
              height: 44,
              width: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              // The same civic glyph the home screen's ward pill carries, so
              // a story reads as coming from the ward office rather than from
              // a person.
              child: const Icon(Icons.account_balance,
                  size: 23, color: NkColors.brand),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr(ring.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    byline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (canDelete)
            IconButton(
              onPressed: onDelete,
              tooltip: context.tr('Delete'),
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white, size: 22),
            ),
          IconButton(
            onPressed: onClose,
            tooltip: context.tr('Close'),
            icon: const Icon(Icons.close, color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }
}

/// The gold wave separator, the cream shelf, and the caption capsule — the
/// whole banner, floating over the photograph's foot as one piece.
///
/// The wave is painted as a band laid over the foot of the photograph rather
/// than as a clip applied to it. That distinction is the whole point: a curve
/// cut into the image lands in a different place on a portrait than on a
/// landscape and crops whatever happens to be there, while a band drawn on top
/// is identical whatever the photo's proportions are, and the photo underneath
/// stays a plain untouched rectangle.
///
/// Its height is MEASURED, not estimated — see [heightFor]. The caller needs
/// it before it can place anything, because the photograph and the banner are
/// centred as one block, and an estimate was always a line out for a long
/// caption.
class _CaptionBand extends StatelessWidget {
  const _CaptionBand({required this.caption});

  final String caption;

  /// Clearance between the upper wave and the capsule.
  static const double _topPad = 30;

  /// Clearance below the capsule, for the lower wave and the navy beneath.
  static const double _bottomPad = 58;

  /// What this band will measure at [width], caption and all.
  ///
  /// It lays the caption out with a [TextPainter] using the capsule's own
  /// style and the viewer's text scale, so the answer is exact for one line or
  /// four. Cheap enough to do in a layout pass, and it means the centring
  /// never has to guess.
  static double heightFor(BuildContext context, double width, String caption) {
    if (caption.isEmpty) return 0;
    final textWidth = math.max(
      40.0,
      width - _CaptionCapsule.chromeWidth,
    );
    final painter = TextPainter(
      text: TextSpan(text: caption, style: _CaptionCapsule.textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: textWidth);
    // The capsule hugs whichever is taller — its icon tile or its text.
    final capsuleH = _CaptionCapsule.verticalPadding +
        math.max(_CaptionCapsule.tileSize, painter.height);
    return _topPad + capsuleH + _bottomPad;
  }

  @override
  Widget build(BuildContext context) {
    // No caption, no band: the photograph simply runs to the bottom of the
    // screen, which is a cleaner answer than an empty shelf.
    if (caption.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: const _WaveBandPainter())),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, _topPad, 0, _bottomPad),
          child: _CaptionCapsule(text: caption),
        ),
      ],
    );
  }
}

/// Draws the cream shelf between two gold S-curves, with the navy ground
/// below the lower one. Above the upper curve nothing is painted, so the
/// photograph shows through.
class _WaveBandPainter extends CustomPainter {
  const _WaveBandPainter();

  /// The curves are placed by ABSOLUTE inset from the band's edges, not by
  /// fraction of its height — the band grows with the caption, and a
  /// fractional wave would get shallower or steeper with it.
  static const double _topLeftY = 30;
  static const double _topRightY = 6;
  static const double _bottomLeftInset = 60;
  static const double _bottomRightInset = 26;
  static const double _amp = 20;

  /// One gentle S from the left edge to the right edge. The control points
  /// pull in opposite directions, which is what makes it read as a sweep
  /// rather than as a sagging arc.
  Path _curve(double w, double y0, double y1) => Path()
    ..moveTo(0, y0)
    ..cubicTo(w * 0.34, y0 - _amp, w * 0.60, y1 + _amp, w, y1);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bl = h - _bottomLeftInset;
    final br = h - _bottomRightInset;

    final top = _curve(w, _topLeftY, _topRightY);
    final bottom = _curve(w, bl, br);

    // Cream shelf: along the top curve, down the right edge, back along the
    // bottom curve reversed, and up the left edge.
    final shelf = Path.from(top)
      ..lineTo(w, br)
      ..cubicTo(w * 0.60, br + _amp, w * 0.34, bl - _amp, 0, bl)
      ..close();
    canvas.drawPath(shelf, Paint()..color = _kCaptionCream);

    // Navy ground under the lower curve.
    final ground = Path()
      ..moveTo(0, bl)
      ..cubicTo(w * 0.34, bl - _amp, w * 0.60, br + _amp, w, br)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(ground, Paint()..color = _kStoryBg);

    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [NkColors.gold400, NkColors.gold100, NkColors.gold300],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(top, gold);
    canvas.drawPath(bottom, gold);
  }

  @override
  bool shouldRepaint(covariant _WaveBandPainter oldDelegate) => false;
}

/// The announcement, as a capsule on the cream shelf at the photograph's foot.
///
/// The metrics below are `static` because [_CaptionBand.heightFor] has to lay
/// the same text out with a [TextPainter] before anything is built. Change one
/// here and the measurement follows; hard-code it in two places and the
/// centring silently drifts.
class _CaptionCapsule extends StatelessWidget {
  const _CaptionCapsule({required this.text});

  final String text;

  /// The capsule's own text style, shared with the measuring pass.
  static const TextStyle textStyle = TextStyle(
    fontSize: 15.5,
    height: 1.28,
    fontWeight: FontWeight.w800,
    color: NkColors.brand700,
  );

  /// The icon tile, which sets the capsule's minimum height.
  static const double tileSize = 44;

  /// Padding above plus below the row.
  static const double verticalPadding = 24;

  /// Everything across the capsule that is NOT the text: the band's outer
  /// margins, the capsule's own padding, the tile, the divider and the gaps
  /// either side of it.
  static const double chromeWidth =
      18 * 2 + 12 + 18 + tileSize + 12 + 1.2 + 12;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: NkColors.gold200, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: tileSize,
              width: tileSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NkColors.amber100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.construction,
                  size: 24, color: NkColors.amber700),
            ),
            const SizedBox(width: 12),
            Container(width: 1.2, height: 40, color: NkColors.slate200),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: textStyle)),
          ],
        ),
      ),
    );
  }
}

/// One progress segment: empty, filling, or full.
class _Segment extends StatelessWidget {
  const _Segment({required this.state, required this.progress});

  /// 0 = not reached, 1 = done, -1 = the live one.
  final int state;
  final Animation<double>? progress;

  @override
  Widget build(BuildContext context) {
    final track = Colors.white.withValues(alpha: 0.26);
    Widget bar(double fraction) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: [
              Container(height: 3, color: track),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(height: 3, color: Colors.white),
              ),
            ],
          ),
        );
    if (state == 1) return bar(1);
    final p = progress;
    if (state == 0 || p == null) return bar(0);
    return AnimatedBuilder(
      animation: p,
      builder: (_, __) => bar(p.value),
    );
  }
}
