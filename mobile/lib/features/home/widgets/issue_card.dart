import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/i18n.dart';
import '../../../data/media.dart';
import '../../../domain/geo_utils.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/status_meta.dart';
import '../../../domain/ticket.dart';
import '../../shared/status_chip.dart';

/// Collapsible grievance card (In My Ward + My Reports) — port of IssueCard
/// on the web home. Collapsed: thumb + title + upvote pill + distance +
/// status. Expanded: full image, ticket + ward chips, AI summary, coordinator
/// message, 6-step lifecycle tracker, optional Support button.
class IssueCard extends StatelessWidget {
  const IssueCard({
    super.key,
    required this.issue,
    required this.expanded,
    required this.onToggle,
    this.distanceKm,
    this.onUpvote,
    this.actions,
    this.badge,
  });

  final Issue issue;
  final bool expanded;
  final VoidCallback onToggle;
  final double? distanceKm;
  final ValueChanged<Issue>? onUpvote;

  /// Coordinator variant: replaces the lifecycle tracker + support button
  /// with an action-button slot (Assign/False, Transfer/Escalate/Close, …).
  final Widget? actions;

  /// Extra chip after the status chip (coordinator action-status badge).
  final Widget? badge;

  /// Placeholder shown when the issue has no photo — and, via errorBuilder,
  /// when the backend serves undecodable bytes (seed data has shipped
  /// zero-length "stub" images before; decoding must never throw in the list).
  static Widget _photoFallback(double size, double emojiSize) => Container(
        height: size,
        width: size,
        color: NkColors.slate100,
        alignment: Alignment.center,
        child: Text('🛣️', style: TextStyle(fontSize: emojiSize)),
      );

  void _showPhoto(BuildContext context, ImageProvider image) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (_) => _PhotoDialog(issue: issue, image: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = mediaImage(issue.imageUrl);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NkColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Collapsed row (always visible)
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onToggle();
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (!expanded) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: image != null
                          ? Image(
                              image: image,
                              height: 40,
                              width: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _photoFallback(40, 18),
                            )
                          : _photoFallback(40, 18),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          issue.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            color: NkColors.slate900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Upvote pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: NkColors.amber100,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: NkColors.amber200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.thumb_up,
                                      size: 10, color: NkColors.amber600),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${issue.upvotes}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: NkColors.amber700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (distanceKm != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.navigation_outlined,
                                      size: 10, color: NkColors.slate400),
                                  const SizedBox(width: 3),
                                  Text(
                                    formatDistanceKm(distanceKm!),
                                    style: const TextStyle(
                                        fontSize: 11, color: NkColors.slate400),
                                  ),
                                ],
                              ),
                            // Exactly ONE status pill: the coordinator badge
                            // (richer label) when provided, else the default
                            // status chip. Never both.
                            if (badge != null)
                              badge!
                            else
                              StatusChip(status: issue.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: NkMotion.settle,
                    child: const Icon(Icons.keyboard_arrow_down,
                        size: 16, color: NkColors.slate400),
                  ),
                ],
              ),
            ),
          ),

          // Expanded body
          AnimatedSize(
            duration: const Duration(milliseconds: 380),
            curve: NkMotion.settle,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: NkColors.slate100),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: image == null
                                  ? null
                                  : () {
                                      HapticFeedback.selectionClick();
                                      _showPhoto(context, image);
                                    },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: image != null
                                    ? Image(
                                        image: image,
                                        height: 96,
                                        width: 96,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _photoFallback(96, 30),
                                      )
                                    : _photoFallback(96, 30),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (issue.areaName != null) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.place,
                                            size: 10, color: NkColors.slate500),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                            issue.areaName!,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: NkColors.slate500),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: NkColors.slate100,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                                Icons
                                                    .confirmation_number_outlined,
                                                size: 9,
                                                color: NkColors.slate500),
                                            const SizedBox(width: 3),
                                            Text(
                                              issue.ticketNo ??
                                                  ticketNumber(issue.id),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'monospace',
                                                color: NkColors.slate500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (issue.wardNo != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: NkColors.violet50,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: NkColors.violet200),
                                          ),
                                          child: Text(
                                            'Ward no: ${issue.wardNo}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: NkColors.violet700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (issue.createdAt != null)
                                    Text(
                                      formatShortDate(issue.createdAt!),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: NkColors.slate400),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // AI summary
                        if (issue.transcript != null ||
                            issue.summaryHighlights.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: NkColors.brand50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: NkColors.brand100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.auto_awesome,
                                        size: 12, color: NkColors.brand),
                                    SizedBox(width: 6),
                                    Text(
                                      context.tr('AI SUMMARY'),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.8,
                                        color: NkColors.brand,
                                      ),
                                    ),
                                  ],
                                ),
                                if (issue.transcript != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    // Tamil transcript in Tamil mode when the
                                    // backend stored one; else the English.
                                    '"${context.lang == AppLang.ta && (issue.transcriptTa?.isNotEmpty ?? false) ? issue.transcriptTa : issue.transcript}"',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      height: 1.4,
                                      color: NkColors.slate700,
                                    ),
                                  ),
                                ],
                                if (issue.summaryHighlights.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      for (final h in issue.summaryHighlights)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                                color: NkColors.brand200),
                                          ),
                                          child: Text(
                                            h,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              color: NkColors.brand,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        // Coordinator message
                        if (issue.coordinatorMessage != null &&
                            issue.coordinatorMessage!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: issue.status == 'FALSE'
                                  ? NkColors.rose50
                                  : NkColors.amber50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: issue.status == 'FALSE'
                                    ? NkColors.rose100
                                    : NkColors.amber100,
                              ),
                            ),
                            child: Text(
                              issue.coordinatorMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                height: 1.4,
                                color: issue.status == 'FALSE'
                                    ? NkColors.rose700
                                    : NkColors.amber800,
                              ),
                            ),
                          ),
                        ],

                        // Coordinator action slot replaces the citizen
                        // lifecycle + support button entirely.
                        if (actions != null) ...[
                          const SizedBox(height: 12),
                          actions!,
                        ],

                        // Lifecycle tracker (citizen cards; hidden for FALSE)
                        if (actions == null && issue.status != 'FALSE') ...[
                          const SizedBox(height: 12),
                          _LifecycleTracker(index: progressIndex(issue.status)),
                        ],

                        // Support button — hidden on false petitions (#4).
                        if (actions == null &&
                            onUpvote != null &&
                            issue.status != 'FALSE') ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => onUpvote!(issue),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: NkColors.brand,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.thumb_up_outlined,
                                      size: 13, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text(
                                    context.tr('Support this grievance'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
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

/// Floating viewer for the expanded card's photo: dimmed barrier, tap
/// outside or the X to dismiss, and a pin button that opens the grievance
/// location in the native maps app (geo: intent, web-maps fallback).
class _PhotoDialog extends StatelessWidget {
  const _PhotoDialog({required this.issue, required this.image});

  final Issue issue;
  final ImageProvider image;

  Future<void> _openMaps() async {
    final lat = issue.latitude, lng = issue.longitude;
    final label = Uri.encodeComponent(issue.title);
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)');
    try {
      if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    final web =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height * 0.7),
              child: Image(
                image: image,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 220,
                  width: double.infinity,
                  color: NkColors.slate100,
                  alignment: Alignment.center,
                  child: const Text('🛣️', style: TextStyle(fontSize: 40)),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _PhotoDialogButton(
              icon: Icons.close,
              tooltip: 'Close',
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: _PhotoDialogButton(
              icon: Icons.place_outlined,
              tooltip: 'Open in maps',
              onTap: _openMaps,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoDialogButton extends StatelessWidget {
  const _PhotoDialogButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: 44,
          width: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: NkColors.slate900.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// The 6-step lifecycle progress rail with a glowing active dot.
class _LifecycleTracker extends StatefulWidget {
  const _LifecycleTracker({required this.index});

  final int index;

  @override
  State<_LifecycleTracker> createState() => _LifecycleTrackerState();
}

class _LifecycleTrackerState extends State<_LifecycleTracker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kLifecycle.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: i == 0
                          ? const SizedBox.shrink()
                          : Container(
                              height: 2,
                              color: i <= widget.index
                                  ? NkColors.brand
                                  : NkColors.slate200,
                            ),
                    ),
                    AnimatedBuilder(
                      animation: _glow,
                      builder: (context, _) {
                        final active = i == widget.index;
                        final done = i < widget.index;
                        final t = (0.5 - (0.5 - _glow.value).abs()) * 2;
                        return Container(
                          height: 16,
                          width: 16,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active || done
                                ? NkColors.brand
                                : NkColors.slate200,
                            shape: BoxShape.circle,
                            border: active
                                ? Border.all(color: NkColors.brand200, width: 2)
                                : null,
                            boxShadow: active
                                ? [
                                    BoxShadow(
                                      color: NkColors.brand
                                          .withValues(alpha: 0.5 * (1 - t)),
                                      spreadRadius: 6 * t,
                                    ),
                                  ]
                                : null,
                          ),
                          child: done
                              ? const Icon(Icons.check,
                                  size: 9, color: Colors.white)
                              : null,
                        );
                      },
                    ),
                    Expanded(
                      child: i == kLifecycle.length - 1
                          ? const SizedBox.shrink()
                          : Container(
                              height: 2,
                              color: i < widget.index
                                  ? NkColors.brand
                                  : NkColors.slate200,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 24,
                  child: Text(
                    kLifecycle[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 6,
                      height: 1.3,
                      fontWeight:
                          i == widget.index ? FontWeight.w700 : FontWeight.w400,
                      color: i == widget.index
                          ? NkColors.brand
                          : NkColors.slate400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
