import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import 'notification_banner.dart' show NotificationBanner;

/// Bell icon (header, top-right) with an unread badge. Tapping opens a
/// floating overlay panel listing recent notifications — no separate page —
/// with a "Clear all" action. Notifications are the same records the
/// [NotificationPoller] pops as banners; the bell is their persistent home.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({
    super.key,
    required this.recipientType, // 'citizen' | 'coordinator'
    required this.recipientId,
    this.dark = false, // dark = light glyph on a navy header
  });

  final String recipientType;
  final String recipientId;
  final bool dark;

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  Timer? _timer;
  List<Map<String, dynamic>> _items = [];

  String get _seenKey => 'nk_bell_seen_${widget.recipientType}_${widget.recipientId}';
  String get _clearedKey =>
      'nk_bell_cleared_${widget.recipientType}_${widget.recipientId}';

  String get _cleared =>
      ref.read(sharedPreferencesProvider).getString(_clearedKey) ?? '';
  String get _seen =>
      ref.read(sharedPreferencesProvider).getString(_seenKey) ?? '';

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (widget.recipientId.isEmpty) return;
    try {
      final res = await ref.read(apiClientProvider).fetchNotifications(
            recipientType: widget.recipientType,
            recipientId: widget.recipientId,
          );
      if (!mounted) return;
      final cleared = _cleared;
      // Hide everything up to the "cleared" marker.
      final visible = res.items
          .where((n) => cleared.isEmpty || '${n['created_at']}'.compareTo(cleared) > 0)
          .toList();
      setState(() => _items = visible);
    } catch (_) {/* silent */}
  }

  int get _unread {
    final seen = _seen;
    if (seen.isEmpty) return _items.length;
    return _items
        .where((n) => '${n['created_at']}'.compareTo(seen) > 0)
        .length;
  }

  Future<void> _markSeen() async {
    if (_items.isEmpty) return;
    final newest = '${_items.first['created_at']}';
    await ref.read(sharedPreferencesProvider).setString(_seenKey, newest);
    if (mounted) setState(() {});
  }

  Future<void> _clearAll() async {
    final newest = _items.isNotEmpty ? '${_items.first['created_at']}' : '';
    if (newest.isNotEmpty) {
      await ref.read(sharedPreferencesProvider).setString(_clearedKey, newest);
      await ref.read(sharedPreferencesProvider).setString(_seenKey, newest);
    }
    if (mounted) setState(() => _items = []);
  }

  void _open() {
    HapticFeedback.selectionClick();
    _markSeen();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notifications',
      barrierColor: Colors.black.withValues(alpha: 0.25),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(parent: anim, curve: NkMotion.settle);
        // Material ancestor so Text uses proper styling (no yellow underlines).
        return Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.0).animate(curved),
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding:
                        const EdgeInsets.only(top: 56, right: 12, left: 12),
                    child: _NotificationPanel(
                      items: _items,
                      onClear: () {
                        Navigator.of(ctx).pop();
                        _clearAll();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final glyph = widget.dark ? Colors.white : NkColors.slate700;
    return GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.notifications_none_rounded, size: 22, color: glyph),
            if (_unread > 0)
              Positioned(
                top: 6,
                right: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 15),
                  decoration: BoxDecoration(
                    color: NkColors.rose600,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.4),
                  ),
                  child: Text(
                    _unread > 9 ? '9+' : '$_unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 8.5,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({required this.items, required this.onClear});

  final List<Map<String, dynamic>> items;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: w > 460 ? 380 : w - 24, maxHeight: 460),
      child: GlassContainer(
        variant: Glass.strong,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: NkColors.slate900.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 16),
            spreadRadius: -8,
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_outlined,
                      size: 16, color: NkColors.brand),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Notifications',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: NkColors.slate900,
                        )),
                  ),
                  if (items.isNotEmpty)
                    GestureDetector(
                      onTap: onClear,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: NkColors.rose50,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('Clear all',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: NkColors.rose600,
                            )),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: NkColors.slate200),
            Flexible(
              child: items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.notifications_off_outlined,
                              size: 30, color: NkColors.slate300),
                          SizedBox(height: 8),
                          Text('No notifications',
                              style: TextStyle(
                                  fontSize: 13, color: NkColors.slate400)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(10),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => NotificationBanner(notif: items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
