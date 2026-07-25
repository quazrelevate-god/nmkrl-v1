import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/data/coordinator_store.dart';
import 'package:namma_kural/domain/coordinator_data.dart';
import 'package:namma_kural/domain/models/issue.dart';
import 'package:shared_preferences/shared_preferences.dart';

Issue _issue({
  required String id,
  required String status,
  String? assigned,
  DateTime? escalatedAt,
}) =>
    Issue.fromJson(<String, dynamic>{
      'id': id,
      'title': 'Issue $id',
      'latitude': 13.07,
      'longitude': 80.26,
      'status': status,
      if (assigned != null) 'assigned_coordinator': assigned,
      if (escalatedAt != null) 'escalated_at': escalatedAt.toIso8601String(),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('partitionForCoordinator', () {
    test('unassigned open → ward; mine → mine; escalated → escalated; terminal → previous', () {
      final t = DateTime(2026, 7, 25, 10);
      final issues = [
        _issue(id: 'u1', status: 'SUBMITTED'), // unassigned → ward
        _issue(id: 'u2', status: 'ACTIVE'), // unassigned → ward
        _issue(id: 'm1', status: 'ACTIVE', assigned: 'raja'), // mine → mine
        _issue(id: 'm2', status: 'FORWARDED', assigned: 'raja'), // mine → mine
        _issue(id: 'e1', status: 'IN_PROGRESS', assigned: 'raja', escalatedAt: t), // escalated
        _issue(id: 'p1', status: 'CLOSED', assigned: 'raja'), // previous
        _issue(id: 'p2', status: 'FALSE', assigned: 'raja'), // previous
        _issue(id: 'o1', status: 'ACTIVE', assigned: 'meena'), // OTHER coord → hidden
      ];
      final p = partitionForCoordinator(issues, 'raja');
      expect(p.ward.map((i) => i.id), ['u1', 'u2']);
      expect(p.mine.map((i) => i.id), ['m1', 'm2']);
      expect(p.escalated.map((i) => i.id), ['e1']);
      expect(p.previous.map((i) => i.id), ['p1', 'p2']);
    });

    test('username match is case-insensitive', () {
      final issues = [_issue(id: 'x', status: 'ACTIVE', assigned: 'Raja')];
      final p = partitionForCoordinator(issues, 'raja');
      expect(p.mine, hasLength(1));
    });
  });

  group('Coordinator model', () {
    test('fromJson tolerates snake_case + camelCase field names', () {
      final a = Coordinator.fromJson({
        'id': 'a1',
        'username': 'raja',
        'name': 'V. Ramkumar Raja',
        'role': 'Constituency Lead',
        'constituency': '16 - Egmore',
        'home_ward': '58',
        'must_change_password': true,
      });
      expect(a.homeWard, '58');
      expect(a.mustChangePassword, isTrue);
      expect(a.initials, 'VR');

      final b = Coordinator.fromJson({
        'id': 'b1',
        'username': 'meena',
        'name': 'Meena Lakshmi',
        'role': 'Ward Coordinator',
        'constituency': '16 - Egmore',
        'homeWard': '104',
      });
      expect(b.homeWard, '104');
      expect(b.mustChangePassword, isFalse);
    });
  });

  group('CoordinatorStore', () {
    test('session round-trips with Coordinator profile + notif cursor is per-user',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = CoordinatorStore(await SharedPreferences.getInstance());
      expect(store.session, isNull);

      final c = Coordinator(
        id: 'x', username: 'raja', name: 'Raja', role: 'Lead',
        constituency: '16 - Egmore', homeWard: '58',
      );
      await store.saveSession(c);
      expect(store.session?.username, 'raja');
      expect(store.session?.homeWard, '58');

      await store.setNotifCursor('raja', '2026-07-25T10:00:00Z');
      expect(store.notifCursor('raja'), '2026-07-25T10:00:00Z');
      expect(store.notifCursor('meena'), isNull);

      await store.clearSession();
      expect(store.session, isNull);
    });
  });
}
