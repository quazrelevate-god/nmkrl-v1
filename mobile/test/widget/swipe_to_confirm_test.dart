import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/features/report/widgets/swipe_to_confirm.dart';

void main() {
  Widget harness(Widget child) => MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );

  testWidgets('full drag past the threshold fires onConfirm once',
      (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(harness(
      SwipeToConfirm(
        label: 'Swipe to submit grievance',
        onConfirm: () => confirmed++,
      ),
    ));

    expect(find.text('Swipe to submit grievance'), findsOneWidget);

    final knob = find.byIcon(Icons.keyboard_double_arrow_right);
    expect(knob, findsOneWidget);

    await tester.drag(knob, const Offset(900, 0));
    await tester.pump(const Duration(milliseconds: 400));

    expect(confirmed, 1);
    expect(find.text('Confirmed'), findsOneWidget);
  });

  testWidgets('short drag springs back without confirming', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(harness(
      SwipeToConfirm(label: 'Swipe to support', onConfirm: () => confirmed++),
    ));

    await tester.drag(
        find.byIcon(Icons.keyboard_double_arrow_right), const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 400));

    expect(confirmed, 0);
    expect(find.text('Swipe to support'), findsOneWidget);
  });

  testWidgets('resetToken snaps a confirmed control back', (tester) async {
    var token = 0;
    late StateSetter setOuterState;
    await tester.pumpWidget(harness(
      StatefulBuilder(
        builder: (context, setState) {
          setOuterState = setState;
          return SwipeToConfirm(
            label: 'Swipe',
            onConfirm: () {},
            resetToken: token,
          );
        },
      ),
    ));

    await tester.drag(
        find.byIcon(Icons.keyboard_double_arrow_right), const Offset(900, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Confirmed'), findsOneWidget);

    setOuterState(() => token++);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Swipe'), findsOneWidget);
  });
}
