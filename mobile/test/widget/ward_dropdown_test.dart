import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/domain/constituencies.dart';
import 'package:namma_kural/features/home/widgets/ward_dropdown.dart';

void main() {
  final all = [for (var w = 1; w <= 200; w++) '$w'];

  // The dropdown groups by the LIVE corporation's table; these are Chennai's.
  setUp(() => setActiveAcMap(kChennaiAcMap));

  Widget harness(String? ward, ValueChanged<String> onChanged) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 96,
              child: ConstituencyWardDropdown(
                wards: all,
                ward: ward,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      );

  testWidgets('closed button shows only the chosen ward', (tester) async {
    await tester.pumpWidget(harness('108', (_) {}));
    expect(find.text('Ward 108'), findsOneWidget);
    expect(find.text('16 · Egmore'), findsNothing);
  });

  testWidgets('a boundary ward, listed twice, can be the selection',
      (tester) async {
    // 168 sits under Saidapet and Velachery — two items for one ward. A
    // dropdown with duplicate values throws while building.
    await tester.pumpWidget(harness('168', (_) {}));
    expect(tester.takeException(), isNull);
    expect(find.text('Ward 168'), findsOneWidget);
  });

  testWidgets('opens grouped, and picking reports the bare ward',
      (tester) async {
    String? picked;
    await tester.pumpWidget(harness(null, (w) => picked = w));
    await tester.tap(find.text('Ward'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Constituency headings are in the open menu.
    expect(find.text('11 · Dr. Radhakrishnan Nagar'), findsWidgets);

    // Ward 38 is the first ward of the first constituency, so it is on screen
    // without scrolling; the menu builds its rows lazily.
    await tester.tap(find.text('Ward 38').last);
    await tester.pumpAndSettle();
    expect(picked, '38');
  });

  testWidgets('an unmapped ward is selectable and shows plainly',
      (tester) async {
    String? picked;
    await tester.pumpWidget(harness('86', (w) => picked = w));
    expect(tester.takeException(), isNull);
    expect(find.text('Ward 86'), findsOneWidget);
    expect(picked, isNull);
  });
}
