import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/domain/models/corporation.dart';

void main() {
  test('parses GET /api/corporation', () {
    final c = Corporation.fromJson({
      'id': 'tambaram',
      'name': 'Tambaram City Municipal Corporation',
      'short_name': 'Tambaram',
      'center': [12.9376, 80.1355],
      'zoom': 12.5,
      'constituencies': {
        'Tambaram Corporation': ['1', '2', 70],
      },
      'available': <dynamic>[],
    });
    expect(c.id, 'tambaram');
    expect(c.shortName, 'Tambaram');
    expect(c.center.latitude, closeTo(12.9376, 1e-9));
    expect(c.constituencies['Tambaram Corporation'], ['1', '2', '70']);
  });

  test('round-trips through the on-device cache', () {
    final c = Corporation.fromJson({
      'id': 'chennai',
      'name': 'Greater Chennai Corporation',
      'short_name': 'Chennai',
      'center': [13.0827, 80.2081],
      'constituencies': {
        '16 - Egmore': ['58', '61'],
      },
    });
    final back = Corporation.fromJson(c.toJson());
    expect(back.id, 'chennai');
    expect(back.center.longitude, closeTo(80.2081, 1e-9));
    expect(back.constituencies, c.constituencies);
  });

  test('a response without a centre falls back to Tambaram', () {
    final c = Corporation.fromJson({'id': 'x', 'name': 'X'});
    expect(c.center, kDefaultCorporationCenter);
    expect(c.shortName, 'X');
  });
}
