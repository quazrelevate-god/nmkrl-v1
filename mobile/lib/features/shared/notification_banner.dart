import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../state/providers.dart';

/// Foreground-poll pump for the notifications API. Drops in at the top of a
/// screen and pops a floating banner for every new entry the backend returns.
///
///   type = 'citizen'      → pops on status changes to the user's own reports
///   type = 'coordinator'  → pops on new-grievance-in-my-ward events
///
/// Cursor (last-seen ISO ts) is persisted per user so the banner never
/// re-pops the same notification across restarts.
class NotificationPoller extends ConsumerStatefulWidget {
  const NotificationPoller({
    super.key,
    required this.recipientType,
    required this.recipientId,
    this.pollInterval = const Duration(seconds: 15),
    this.onNewGrievanceInMyWard,
    this.onStatusChange,
  });

  final String recipientType; // 'citizen' | 'coordinator'
  final String recipientId;
  final Duration pollInterval;

  /// Coordinator-side callback: a new grievance landed in my ward — parent
  /// typically wants to refresh its list too.
  final void Function(Map<String, dynamic> notif)? onNewGrievanceInMyWard;

  /// Citizen-side callback: a status change on one of my reports.
  final void Function(Map<String, dynamic> notif)? onStatusChange;

  @override
  ConsumerState<NotificationPoller> createState() => _NotificationPollerState();
}

class _NotificationPollerState extends ConsumerState<NotificationPoller> {
  Timer? _timer;
  final _queue = <Map<String, dynamic>>[];
  Map<String, dynamic>? _current;
  String _cursor = '';

  @override
  void initState() {
    super.initState();
    _hydrateCursor();
    // First poll fires quickly; subsequent ones follow [pollInterval].
    Future.microtask(_pollOnce);
    _timer = Timer.periodic(widget.pollInterval, (_) => _pollOnce());
  }

  void _hydrateCursor() {
    if (widget.recipientId.isEmpty) return;
    if (widget.recipientType == 'coordinator') {
      final store = ref.read(coordinatorStoreProvider);
      _cursor = store.notifCursor(widget.recipientId) ?? '';
    } else {
      final prefs = ref.read(prefsProvider);
      _cursor = prefs.citizenNotifCursor;
    }
  }

  Future<void> _persistCursor(String isoTs) async {
    _cursor = isoTs;
    if (widget.recipientType == 'coordinator') {
      await ref
          .read(coordinatorStoreProvider)
          .setNotifCursor(widget.recipientId, isoTs);
    } else {
      await ref.read(prefsProvider).setCitizenNotifCursor(isoTs);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _pollOnce() async {
    if (widget.recipientId.isEmpty) return;
    try {
      final res = await ref.read(apiClientProvider).fetchNotifications(
            recipientType: widget.recipientType,
            recipientId: widget.recipientId,
            since: _cursor,
          );
      if (!mounted) return;
      final newest = res.items.isNotEmpty ? '${res.items.first['created_at']}' : '';
      // Newest-first from server; advance cursor immediately so we don't
      // re-pop on the next poll.
      if (newest.isNotEmpty) {
        await _persistCursor(newest);
      } else if (res.serverTime.isNotEmpty && _cursor.isEmpty) {
        // First-ever poll with nothing pending — anchor at server time.
        await _persistCursor(res.serverTime);
      }
      if (res.items.isEmpty) return;
      // Fire callbacks (oldest first so refresh happens once).
      for (final n in res.items.reversed) {
        if (widget.recipientType == 'coordinator' &&
            n['kind'] == 'new_grievance') {
          widget.onNewGrievanceInMyWard?.call(n);
        } else if (widget.recipientType == 'citizen') {
          widget.onStatusChange?.call(n);
        }
      }
      setState(() => _queue.addAll(res.items.reversed));
      _showNext();
    } catch (_) {
      /* silent — poll again in [interval] */
    }
  }

  void _showNext() {
    if (_current != null) return;
    if (_queue.isEmpty) return;
    setState(() => _current = _queue.removeAt(0));
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _current = null);
      Future.delayed(const Duration(milliseconds: 200), _showNext);
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = _current;
    return SafeArea(
      bottom: false,
      child: AnimatedSlide(
        offset: n == null ? const Offset(0, -1.4) : Offset.zero,
        duration: const Duration(milliseconds: 320),
        curve: NkMotion.settle,
        child: AnimatedOpacity(
          opacity: n == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          child: n == null
              ? const SizedBox.shrink()
              : GestureDetector(
                  onTap: () => setState(() => _current = null),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: NotificationBanner(notif: n),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Pure UI — a glass banner rendering one notification.
class NotificationBanner extends StatelessWidget {
  const NotificationBanner({super.key, required this.notif});

  final Map<String, dynamic> notif;

  @override
  Widget build(BuildContext context) {
    final kind = '${notif['kind'] ?? ''}';
    final (icon, tint, kicker) = _visuals(kind);
    return GlassContainer(
      variant: Glass.strong,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: NkColors.slate900.withValues(alpha: 0.35),
          blurRadius: 30,
          offset: const Offset(0, 12),
          spreadRadius: -8,
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 34, width: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tint.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, size: 16, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr(kicker),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: tint,
                      )),
                  Text('${notif['title'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: NkColors.slate900,
                      )),
                  Text('${notif['message'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: NkColors.slate600,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _visuals(String kind) {
    switch (kind) {
      case 'assigned':
        return (Icons.verified_user_outlined, NkColors.brand, 'ASSIGNED');
      case 'transfer':
        return (Icons.send_outlined, NkColors.sky700, 'TRANSFERRED');
      case 'escalated':
        return (Icons.keyboard_double_arrow_up, NkColors.amber700, 'ESCALATED');
      case 'closed':
        return (Icons.check_circle_outline, NkColors.emerald600, 'RESOLVED');
      case 'false':
        return (Icons.block, NkColors.rose600, 'FLAGGED');
      case 'new_grievance':
        return (Icons.report_problem_outlined, NkColors.brand, 'NEW GRIEVANCE');
      default:
        return (Icons.notifications_none, NkColors.slate600, 'UPDATE');
    }
  }
}
