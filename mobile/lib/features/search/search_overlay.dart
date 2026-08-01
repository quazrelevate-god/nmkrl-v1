import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../domain/models/issue.dart';
import '../home/widgets/grievance_card.dart';

/// Full-screen grievance search, opened from the magnifier in the home app bar.
///
/// Matches on ticket number, title, area name and ward across whatever the
/// caller supplies (ward feed + the citizen's own reports, de-duplicated), so
/// "Search ticket no. or grievance nearby" works from one field.
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({
    super.key,
    required this.issues,
    this.onUpvote,
  });

  final List<Issue> issues;
  final ValueChanged<Issue>? onUpvote;

  static Future<void> open(
    BuildContext context, {
    required List<Issue> issues,
    ValueChanged<Issue>? onUpvote,
  }) {
    HapticFeedback.selectionClick();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.18),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) =>
            SearchOverlay(issues: issues, onUpvote: onUpvote),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: NkMotion.settle);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, -0.03), end: Offset.zero)
                  .animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Open straight into typing — the user tapped a search icon.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<Issue> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    // De-duplicate: the same grievance can appear in both the ward feed and
    // the citizen's own history.
    final seen = <String>{};
    final out = <Issue>[];
    for (final i in widget.issues) {
      if (!seen.add(i.id)) continue;
      final haystack = [
        i.ticketNo ?? '',
        i.title,
        i.areaName ?? '',
        i.wardNo == null ? '' : 'ward ${i.wardNo}',
      ].join(' ').toLowerCase();
      if (haystack.contains(q)) out.add(i);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final hasQuery = _query.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Search field row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: NkColors.slate200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search,
                              size: 19, color: NkColors.slate400),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              onChanged: (v) => setState(() => _query = v),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: context.tr(
                                    'Search ticket no. or grievance nearby'),
                                hintStyle: const TextStyle(
                                    fontSize: 14, color: NkColors.slate400),
                              ),
                              style: const TextStyle(
                                  fontSize: 14, color: NkColors.slate900),
                            ),
                          ),
                          if (hasQuery)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                              child: const Icon(Icons.close,
                                  size: 17, color: NkColors.slate400),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        context.tr('Cancel'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: NkColors.brand,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: !hasQuery
                  ? _hint(context, Icons.search,
                      'Search by ticket number, title or area.')
                  : results.isEmpty
                      ? _hint(context, Icons.search_off,
                          'No grievances match that search.')
                      : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                          itemCount: results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => GrievanceCard(
                            issue: results[i],
                            onUpvote: widget.onUpvote,
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, IconData icon, String message) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
        child: Column(
          children: [
            Icon(icon, size: 34, color: NkColors.slate300),
            const SizedBox(height: 10),
            Text(
              context.tr(message),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: NkColors.slate400),
            ),
          ],
        ),
      );
}
