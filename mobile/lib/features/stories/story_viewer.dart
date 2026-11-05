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
        barrierColor: Colors.black,
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
      backgroundColor: Colors.black,
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

class _RingPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final story = frames[index];
    final top = MediaQuery.paddingOf(context).top;
    final image = mediaImage(story.imageUrl);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null)
          Image(image: image, fit: BoxFit.contain, alignment: Alignment.center),
        // Scrims: the chrome at both ends needs its own contrast whatever the
        // photo does behind it.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black54, Colors.transparent, Colors.black54],
              stops: [0, 0.3, 1],
            ),
          ),
        ),

        // Tap zones. Left third goes back, the rest advances; a long press
        // anywhere pauses, which is the gesture people reach for to read a
        // caption without racing the timer.
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTapLeft,
                onLongPressStart: (_) => onHold(true),
                onLongPressEnd: (_) => onHold(false),
              ),
            ),
            Expanded(
              flex: 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTapRight,
                onLongPressStart: (_) => onHold(true),
                onLongPressEnd: (_) => onHold(false),
              ),
            ),
          ],
        ),

        // ── Header: progress segments, title, author, age, controls ──
        Positioned(
          top: top + 8,
          left: 10,
          right: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < frames.length; i++) ...[
                    Expanded(
                      child: _Segment(
                        state: i < index
                            ? 1
                            : i > index
                                ? 0
                                : -1,
                        progress: i == index ? progress : null,
                      ),
                    ),
                    if (i != frames.length - 1) const SizedBox(width: 3),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.tr(ring.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (story.authorName.isNotEmpty) story.authorName,
                            if (ring.ward != null)
                              '${context.tr('Ward')} ${ring.ward}',
                            if (story.age.isNotEmpty) context.tr(story.age),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      onPressed: onDelete,
                      tooltip: context.tr('Delete'),
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white, size: 21),
                    ),
                  IconButton(
                    onPressed: onClose,
                    tooltip: context.tr('Close'),
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Caption ──
        if (story.caption.isNotEmpty)
          Positioned(
            left: 18,
            right: 18,
            bottom: MediaQuery.paddingOf(context).bottom + 28,
            child: IgnorePointer(
              child: Text(
                story.caption,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  shadows: [
                    Shadow(blurRadius: 8, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
      ],
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
    final track = Colors.white.withValues(alpha: 0.32);
    Widget bar(double fraction) => ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(
            children: [
              Container(height: 2.5, color: track),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(height: 2.5, color: Colors.white),
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
