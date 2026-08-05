import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../data/media.dart';
import '../../../domain/geo_utils.dart';
import '../../../domain/models/issue.dart';
import '../../../domain/status_meta.dart';
import '../../../domain/ticket.dart';
import '../../shared/status_chip.dart';

const Color _kInk = Color(0xFF1A2A3A);
const Color _kMuted = Color(0xFF7A8799);
const Color _kPillBg = Color(0xFFF0F3FA);
const Color _kSummaryBg = Color(0xFFF4F5F7);
const Color _kSummaryInk = Color(0xFF2C3E50);
const Color _kIdleBg = Color(0xFFF0F3F4);
const Color _kIdleInk = Color(0xFFB0B8C4);

/// Placeholder for grievances with no photo — also the errorBuilder target,
/// since seed data has shipped zero-length images that must never throw.
Widget _thumbFallback(double size, double emoji) => Container(
      height: size,
      width: size,
      color: NkColors.slate100,
      alignment: Alignment.center,
      child: Text('🛣️', style: TextStyle(fontSize: emoji)),
    );

String _ticketOf(Issue i) => i.ticketNo ?? ticketNumber(i.id);

/// Upvote count + "Support" label, shared by the list row and the dialog.
class _SupportPill extends StatelessWidget {
  const _SupportPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kPillBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_upward, size: 11, color: _kInk),
          const SizedBox(width: 3),
          Text(
            '$count ${context.tr('Support')}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _kInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsed grievance row for the citizen home list (My Ward / My Reports /
/// My Supports). Tapping opens [GrievanceDialog] — there is no inline
/// expansion and no chevron.
class GrievanceCard extends StatelessWidget {
  const GrievanceCard({super.key, required this.issue, this.onUpvote});

  final Issue issue;

  /// When null the dialog hides its support button (My Reports).
  final ValueChanged<Issue>? onUpvote;

  @override
  Widget build(BuildContext context) {
    final image = mediaImage(issue.imageUrl);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            GrievanceDialog.open(context, issue: issue, onUpvote: onUpvote);
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: image != null
                      ? Image(
                          image: image,
                          height: 64,
                          width: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _thumbFallback(64, 24),
                        )
                      : _thumbFallback(64, 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        issue.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: _kInk,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _ticketOf(issue),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _kMuted,
                        ),
                      ),
                      if (issue.createdAt != null)
                        Text(
                          formatShortDate(issue.createdAt!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _kMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _SupportPill(count: issue.upvotes),
                    const SizedBox(height: 6),
                    StatusChip(status: issue.status, fontSize: 10),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full grievance detail, shown as a modal dialog over the home screen.
class GrievanceDialog extends StatelessWidget {
  const GrievanceDialog({super.key, required this.issue, this.onUpvote});

  final Issue issue;
  final ValueChanged<Issue>? onUpvote;

  static Future<void> open(
    BuildContext context, {
    required Issue issue,
    ValueChanged<Issue>? onUpvote,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Grievance',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) =>
          GrievanceDialog(issue: issue, onUpvote: onUpvote),
      transitionBuilder: (context, anim, _, child) {
        final scale = Tween<double>(begin: 0.92, end: 1).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        );
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale.value, child: child),
        );
      },
    );
  }

  bool get _hasGeo => issue.latitude != 0 || issue.longitude != 0;

  Future<void> _openMaps(BuildContext context) async {
    if (!_hasGeo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location unavailable')),
      );
      return;
    }
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

  /// Which of the three lifecycle pills is lit for this status.
  int get _activeStep => switch (issue.status) {
        'SUBMITTED' || 'PENDING_VERIFICATION' || 'ACTIVE' => 0,
        'FORWARDED' || 'IN_PROGRESS' => 1,
        'CLOSED' => 2,
        _ => -1, // FALSE — nothing lit
      };

  @override
  Widget build(BuildContext context) {
    final image = mediaImage(issue.imageUrl);
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    final summary = context.lang == AppLang.ta &&
            (issue.transcriptTa?.isNotEmpty ?? false)
        ? issue.transcriptTa!
        : (issue.transcript ?? '');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 1. Photo + maps overlay ──
                  SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image != null)
                          Image(
                            image: image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: const Color(0xFFE5E8EE)),
                          )
                        else
                          Container(color: const Color(0xFFE5E8EE)),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: GestureDetector(
                            onTap: () => _openMaps(context),
                            child: Container(
                              height: 28,
                              width: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.place,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── 2. Title ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: Text(
                      issue.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kInk,
                      ),
                    ),
                  ),

                  // ── 3. Summary ──
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kSummaryBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      summary.isNotEmpty
                          ? summary
                          : context.tr('Summary not available'),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: summary.isNotEmpty
                            ? _kSummaryInk
                            : const Color(0xFF9AA5B4),
                      ),
                    ),
                  ),

                  // ── 4. Date + ticket ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          issue.createdAt != null
                              ? formatShortDate(issue.createdAt!)
                              : '—',
                          style: const TextStyle(
                              fontSize: 11, color: _kMuted),
                        ),
                        Flexible(
                          child: Text(
                            '${context.tr('Ticket')}: ${_ticketOf(issue)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: _kMuted),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── 5. Support count ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SupportPill(count: issue.upvotes),
                    ),
                  ),

                  // ── 6. Lifecycle pills (display only) ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Row(
                      children: [
                        for (final (i, status, label) in [
                          (0, 'PENDING_VERIFICATION', 'Verification'),
                          (1, 'IN_PROGRESS', 'In Progress'),
                          (2, 'CLOSED', 'Resolved'),
                        ]) ...[
                          Expanded(
                            child: _StepPill(
                              label: context.tr(label),
                              active: _activeStep == i,
                              status: status,
                            ),
                          ),
                          if (i < 2) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  if (issue.status == 'FALSE')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: _StepPill(
                        label: context.tr('False Petition'),
                        active: true,
                        status: 'FALSE',
                      ),
                    ),

                  // ── 7. Support button ──
                  if (onUpvote != null && issue.status != 'FALSE')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          onUpvote!(issue);
                        },
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // Brand navy, not the card's text ink.
                            color: NkColors.navyPrimary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            context.tr('Support this Grievance'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the three lifecycle pills. Active uses the status' existing badge
/// colors; inactive is a dimmed grey and never tappable.
class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.label,
    required this.active,
    required this.status,
  });

  final String label;
  final bool active;
  final String status;

  @override
  Widget build(BuildContext context) {
    final m = statusMeta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? m.badgeBg : _kIdleBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          color: active ? m.badgeFg : _kIdleInk,
        ),
      ),
    );
  }
}
