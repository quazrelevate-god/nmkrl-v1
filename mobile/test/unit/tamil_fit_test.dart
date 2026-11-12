import 'package:flutter/widgets.dart'; // re-exports package:characters
import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/core/i18n.dart';

/// Tamil sets wider than English, and two chips overflowed because of it.
///
/// This CANNOT check pixel fit: `flutter test` substitutes a test font where
/// every glyph is a fixed-width box, so a TextPainter here measures code
/// units, not Tamil shaping. What it can do is guard the thing that actually
/// regressed — a translation written long enough to blow out a chip that is
/// only ever one line. The budgets below are in grapheme clusters, roughly
/// what a reader counts, and are set just above today's strings.
int _clusters(String s) => s.characters.length;

String _ta(String en) {
  final t = taTable[en];
  expect(t, isNotNull, reason: '"$en" has no Tamil entry');
  return t!;
}

void main() {
  group('grievance card status chip', () {
    // One line, on a card that also has to show a title, a ticket and a date.
    // The long forms that overflowed were 19 and 22 clusters.
    const budget = 14;

    for (final en in [
      'In Progress',
      'Pending Verification',
      'Verification Pending',
      'Marked as false petition',
      'False Petition',
      'Resolved',
      'Assigned',
      'Combined',
    ]) {
      test('"$en" is short enough for the chip', () {
        final ta = _ta(en);
        expect(_clusters(ta), lessThanOrEqualTo(budget),
            reason: '"$ta" (${_clusters(ta)} clusters) will overflow the chip');
      });
    }
  });

  test('the shortened statuses really are shorter than what overflowed', () {
    // Guards against someone restoring the long forms.
    expect(_ta('In Progress'), isNot(contains('உள்ளது')));
    expect(_ta('Pending Verification'), isNot(contains('நிலுவையில்')));
    expect(_ta('Verification Pending'), isNot(contains('நிலுவையில்')));
  });

  test('Ward keeps its full word', () {
    // Deliberately NOT abbreviated: the picker box was widened instead.
    expect(_ta('Ward'), 'வார்டு');
  });
}
