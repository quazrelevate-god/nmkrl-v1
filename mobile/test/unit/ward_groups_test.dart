import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/domain/constituencies.dart';

void main() {
  // Every GCC ward, 1–200, as the map loads them.
  final all = [for (var w = 1; w <= 200; w++) '$w'];

  // The grouping reads the LIVE corporation's table; these cases are Chennai's.
  setUp(() => setActiveAcMap(kChennaiAcMap));

  test('Tambaram: one unnumbered group, labelled by its name', () {
    final groups = groupWardsByConstituency(
      [for (var w = 1; w <= 70; w++) '$w'],
      table: {'Tambaram Corporation': [for (var w = 1; w <= 70; w++) '$w']},
    );
    expect(groups, hasLength(1));
    expect(groups.single.label, 'Tambaram Corporation');
    expect(groups.single.isUnmapped, isFalse);
    expect(groups.single.wards.first, '1');
    expect(groups.single.wards.last, '70');
  });

  test('groups follow constituency-number order, wards ascending', () {
    final groups = groupWardsByConstituency(all);
    final mapped = groups.where((g) => !g.isUnmapped).toList();
    final numbers = mapped.map((g) => int.parse(g.key)).toList();
    expect(numbers, [...numbers]..sort());
    for (final g in mapped) {
      final ws = g.wards.map(int.parse).toList();
      expect(ws, [...ws]..sort(), reason: g.label);
    }
  });

  test('Egmore holds exactly its six wards', () {
    final egmore = groupWardsByConstituency(all).firstWhere((g) => g.key == '16');
    expect(egmore.label, '16 · Egmore');
    expect(egmore.wards, ['58', '61', '77', '78', '104', '108']);
  });

  test('a boundary ward is listed under every constituency it belongs to', () {
    final holding168 = groupWardsByConstituency(all)
        .where((g) => g.wards.contains('168'))
        .map((g) => g.key)
        .toList();
    expect(holding168, containsAll(['22', '25'])); // Saidapet, Velachery
  });

  test('wards no constituency covers come last, none dropped', () {
    final groups = groupWardsByConstituency(all);
    expect(groups.last.isUnmapped, isTrue);
    expect(groups.last.wards, contains('86'));
    final listed = {for (final g in groups) ...g.wards};
    expect(listed, all.toSet());
  });

  test('group keys are unique, so dropdown values cannot collide', () {
    final keys = groupWardsByConstituency(all).map((g) => g.key).toList();
    expect(keys.toSet().length, keys.length);
  });
}
