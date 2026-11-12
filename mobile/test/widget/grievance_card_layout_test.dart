import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/domain/models/issue.dart';
import 'package:namma_kural/features/home/widgets/grievance_card.dart';
import 'package:namma_kural/features/shared/status_chip.dart';

/// The card's trailing chips used to overflow on a long status and to float
/// short of the card's right edge. Both are pure layout, so both are checkable
/// here — unlike text metrics, which the test font makes meaningless.
Issue _issue(String status) => Issue(
      id: 'i1',
      title: 'Citizen Reports Unspecified Civic Problem On The Main Road',
      latitude: 13.08,
      longitude: 80.27,
      status: status,
      upvotes: 0,
      ticketNo: 'FMS-4B2554CE',
      createdAt: DateTime(2026, 10, 30),
    );

Future<void> _pump(WidgetTester tester, String status, double width) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Padding(
        // The list's own horizontal padding, so the card width is realistic.
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GrievanceCard(issue: _issue(status)),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  // The widest real status, and the one that was running off the card.
  const statuses = [
    'FALSE_PETITION',
    'PENDING_VERIFICATION',
    'IN_PROGRESS',
    'RESOLVED',
    'ASSIGNED',
  ];

  for (final width in [320.0, 360.0, 393.0, 411.0]) {
    for (final status in statuses) {
      testWidgets('$status lays out without overflow at ${width}dp',
          (tester) async {
        await _pump(tester, status, width);
        // A RenderFlex overflow reports through the error reporter, which
        // the harness turns into a test failure — so reaching here is the
        // assertion. Make it explicit anyway.
        expect(tester.takeException(), isNull);
      });

      testWidgets('$status chips sit flush right at ${width}dp',
          (tester) async {
        await _pump(tester, status, width);

        final card = tester.getRect(find.byType(GrievanceCard));
        final chip = tester.getRect(find.byType(StatusChip));
        // The PILL, not the label inside it — the label sits 8dp in from the
        // pill's edge, which is what an earlier version of this test was
        // measuring and wrongly calling a misalignment.
        final support = tester.getRect(find
            .ancestor(
              of: find.textContaining('Support'),
              matching: find.byType(Container),
            )
            .first);

        // Card padding is 10. The chip's right edge should land there, not
        // short of it — the old Flexible left the slack AFTER the chips.
        expect(card.right - chip.right, closeTo(10, 1.5),
            reason: 'status chip is not against the card padding');
        expect(card.right - support.right, closeTo(10, 1.5),
            reason: 'support pill is not against the card padding');
        // The two pills share a right edge.
        expect(support.right, closeTo(chip.right, 1.5));
        // And inside it.
        expect(chip.right, lessThanOrEqualTo(card.right));
      });
    }
  }
}
