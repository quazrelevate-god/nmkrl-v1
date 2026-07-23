import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/domain/models/issue.dart';
import 'package:namma_kural/features/home/widgets/issue_card.dart';

void main() {
  final issue = Issue.fromJson(<String, dynamic>{
    'id': 'fae06b9f-bd12-45dc-9c07-65c21b2e3640',
    'title': 'Sewage overflow on the street',
    'latitude': 13.07,
    'longitude': 80.26,
    'status': 'IN_PROGRESS',
    'upvotes': 4,
    'created_at': '2026-07-01T10:00:00+00:00',
    'area_name': 'Egmore',
    'ward_no': 108,
    'transcript': 'Sewage water is flooding the road',
    'summary_highlights': ['Sewage', 'Health hazard'],
  });

  Widget harness({
    required bool expanded,
    VoidCallback? onToggle,
    ValueChanged<Issue>? onUpvote,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IssueCard(
              issue: issue,
              expanded: expanded,
              onToggle: onToggle ?? () {},
              distanceKm: 0.333,
              onUpvote: onUpvote,
            ),
          ),
        ),
      );

  testWidgets('collapsed row shows title, upvotes, distance and status',
      (tester) async {
    await tester.pumpWidget(harness(expanded: false));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sewage overflow on the street'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('333 m'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    // Expanded-only content is hidden
    expect(find.textContaining('AI SUMMARY'), findsNothing);
  });

  testWidgets('tap toggles; expanded shows ticket, AI summary and lifecycle',
      (tester) async {
    var toggles = 0;
    await tester.pumpWidget(
        harness(expanded: false, onToggle: () => toggles++));
    await tester.tap(find.text('Sewage overflow on the street'));
    expect(toggles, 1);

    await tester.pumpWidget(harness(expanded: true, onUpvote: (_) {}));
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('FMS-FAE06B9F'), findsOneWidget);
    expect(find.text('Ward no: 108'), findsOneWidget);
    expect(find.text('AI SUMMARY'), findsOneWidget);
    expect(
        find.text('"Sewage water is flooding the road"'), findsOneWidget);
    expect(find.text('Support this grievance'), findsOneWidget);
    // Lifecycle tracker labels
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });
}
