import 'package:flutter/widgets.dart'; // re-exports package:characters
import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/core/i18n.dart';
import 'package:namma_kural/domain/constituencies.dart';

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

  group('constituency names', () {
    // Shown in the ward pill (a FittedBox that scales the whole pill down),
    // the ward dropdown's group headings and the coordinator's scope line.
    // The longest English name is Chepauk-Thiruvallikeni.
    // Derived from the real table, NOT hand-listed: a hand-written list is
    // how three constituencies (Dr. Radhakrishnan Nagar, Perambur, Kolathur)
    // shipped untranslated. Adding an AC to the table now fails this until it
    // has a Tamil name.
    final names = [
      for (final key in kChennaiAcMap.keys) shortAC(key),
      'Tambaram Corporation',
      'Tambaram',
    ];

    for (final en in names) {
      test('"$en" has a Tamil name', () => expect(taTable[en], isNotNull));
    }

    test('none is wildly longer than its English name', () {
      for (final en in names) {
        final ta = _ta(en);
        // Tamil clusters set wider than Latin characters, so a name that is
        // also longer in clusters would scale the ward pill down twice over.
        expect(_clusters(ta), lessThanOrEqualTo(en.length),
            reason: '"$ta" (${_clusters(ta)}) vs "$en" (${en.length})');
      }
    });
  });

  test('the constituency table keys are NEVER translated', () {
    // The lookup keys in domain/constituencies.dart carry the number, and
    // trAC only ever translates the part after the separator. A table entry
    // for a full key would mean a translated string could reach a lookup.
    for (final key in ['16 - Egmore', '17 - Harbour', '20 - Anna Nagar']) {
      expect(taTable[key], isNull, reason: '$key must stay a key, not a label');
    }
  });

  test('account is one word everywhere', () {
    // The user chose the transliteration; mixing the two spellings
    // would show both words on different screens.
    for (final en in [
      'Delete account',
      'Delete your account?',
      'One account per mobile number',
      'This account is no longer available. Sign in again.',
    ]) {
      final ta = _ta(en);
      expect(ta, contains('அக்கவுண்ட'), reason: '"$en" -> "$ta"');
      expect(ta, isNot(contains('கணக்க')), reason: '"$en" -> "$ta"');
    }
  });

  test('Ward keeps its full word', () {
    // Deliberately NOT abbreviated: the picker box was widened instead.
    expect(_ta('Ward'), 'வார்டு');
  });
}
