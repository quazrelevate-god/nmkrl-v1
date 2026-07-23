import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../domain/profile_data.dart';

/// Full-screen Instagram-style story viewer (port of StoryViewer.js) with
/// native gestures: auto-advancing progress bars, tap left/right to navigate,
/// press-and-hold to pause, swipe down to dismiss, inline like + reply.
class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.story});

  final Story story;

  static Future<void> open(BuildContext context, Story story) {
    HapticFeedback.lightImpact();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => StoryViewer(story: story),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer>
    with SingleTickerProviderStateMixin {
  static const _slideMs = 5000;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _slideMs),
  );

  int _idx = 0;
  final Map<int, bool> _liked = {};
  final Map<int, List<String>> _replies = {};
  final _draft = TextEditingController();
  final _focus = FocusNode();
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
    _progress.forward();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _progress.stop();
      } else if (!_progress.isAnimating && mounted) {
        _progress.forward();
      }
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<StorySlide> get _slides => widget.story.slides;

  void _next() {
    if (_idx >= _slides.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _idx++);
    _progress.forward(from: 0);
  }

  void _prev() {
    if (_idx > 0) setState(() => _idx--);
    _progress.forward(from: 0);
  }

  void _sendReply() {
    final t = _draft.text.trim();
    if (t.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _replies.putIfAbsent(_idx, () => []).add(t);
      _draft.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_idx];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        // Swipe down to dismiss — the sheet follows the finger.
        onVerticalDragUpdate: (d) =>
            setState(() => _dragY = (_dragY + d.delta.dy).clamp(0, 600)),
        onVerticalDragEnd: (d) {
          if (_dragY > 120 || (d.primaryVelocity ?? 0) > 700) {
            Navigator.of(context).maybePop();
          } else {
            setState(() => _dragY = 0);
          }
        },
        child: AnimatedContainer(
          duration: _dragY == 0
              ? const Duration(milliseconds: 260)
              : Duration.zero,
          curve: NkMotion.settle,
          transform: Matrix4.translationValues(0, _dragY, 0),
          child: Scaffold(
            backgroundColor: Colors.black,
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              child: Column(
                children: [
                  // Progress bars
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Row(
                      children: [
                        for (var i = 0; i < _slides.length; i++)
                          Expanded(
                            child: Container(
                              height: 2.5,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: i < _idx
                                  ? Container(color: Colors.white)
                                  : i == _idx
                                      ? AnimatedBuilder(
                                          animation: _progress,
                                          builder: (context, _) =>
                                              FractionallySizedBox(
                                            alignment:
                                                Alignment.centerLeft,
                                            widthFactor: _progress.value,
                                            child: Container(
                                                color: Colors.white),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: widget.story.ring,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              slide.asset,
                              height: 32,
                              width: 32,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.story.label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close,
                              size: 22, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  // Media + tap zones + caption
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onLongPressStart: (_) => _progress.stop(),
                          onLongPressEnd: (_) => _progress.forward(),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Image.asset(
                              slide.asset,
                              key: ValueKey(_idx),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: _prev,
                              ),
                            ),
                            const Spacer(),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: _next,
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.black.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  slide.caption,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              for (final r
                                  in _replies[_idx] ?? const <String>[])
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white
                                        .withValues(alpha: 0.9),
                                    borderRadius:
                                        BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    r,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: NkColors.slate800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Reply + like row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _draft,
                                    focusNode: _focus,
                                    onSubmitted: (_) => _sendReply(),
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.white),
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: 'Reply to this story…',
                                      hintStyle: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _sendReply,
                                  child: Icon(Icons.send,
                                      size: 16,
                                      color: Colors.white
                                          .withValues(alpha: 0.8)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() =>
                                _liked[_idx] = !(_liked[_idx] ?? false));
                          },
                          child: Container(
                            height: 44,
                            width: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: AnimatedScale(
                              scale: (_liked[_idx] ?? false) ? 1.15 : 1,
                              duration: const Duration(milliseconds: 220),
                              curve: NkMotion.spring,
                              child: Icon(
                                (_liked[_idx] ?? false)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 22,
                                color: (_liked[_idx] ?? false)
                                    ? NkColors.rose500
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
