import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/data/coordinator_store.dart';
import 'package:namma_kural/domain/coordinator_data.dart';
import 'package:namma_kural/domain/departments.dart';
import 'package:namma_kural/domain/models/issue.dart';
import 'package:shared_preferences/shared_preferences.dart';

Issue _issue(String id, String status) => Issue.fromJson(<String, dynamic>{
      'id': id,
      'title': 'Issue $id',
      'latitude': 13.07,
      'longitude': 80.26,
      'status': status,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('authenticateCoordinator', () {
    test('valid seeded credentials sign in', () {
      final c = authenticateCoordinator('raja', 'raja123');
      expect(c, isNotNull);
      expect(c!.name, 'V. Ramkumar Raja');
      expect(c.homeWard, '58');
      expect(c.constituency, '16 - Egmore');
    });

    test('username is case/space tolerant, password is not', () {
      expect(authenticateCoordinator(' Raja ', 'raja123'), isNotNull);
      expect(authenticateCoordinator('raja', 'RAJA123'), isNull);
      expect(authenticateCoordinator('nobody', 'x'), isNull);
    });

    test('all four seeded coordinators authenticate', () {
      for (final c in kCoordinators) {
        expect(authenticateCoordinator(c.username, c.password), isNotNull);
      }
    });
  });

  group('partitionWardIssues', () {
    test('splits ward / mine / previous exactly like the web useMemos', () {
      final issues = [
        _issue('a', 'SUBMITTED'), // not mine → ward
        _issue('b', 'ACTIVE'), // mine + active → mine
        _issue('c', 'CLOSED'), // mine + terminal → previous
        _issue('d', 'FALSE'), // mine + terminal → previous
        _issue('e', 'PENDING_VERIFICATION'), // mine + open → mine
        _issue('f', 'ACTIVE'), // not mine → ward
      ];
      final parts =
          partitionWardIssues(issues, {'b', 'c', 'd', 'e'});
      expect(parts.ward.map((i) => i.id), ['a', 'f']);
      expect(parts.mine.map((i) => i.id), ['b', 'e']);
      expect(parts.previous.map((i) => i.id), ['c', 'd']);
    });

    test('unverified CLOSED/FALSE stay in the ward tab', () {
      final parts = partitionWardIssues([_issue('x', 'FALSE')], {});
      expect(parts.ward, hasLength(1));
      expect(parts.previous, isEmpty);
    });
  });

  group('departments', () {
    test('7 canonical departments with meta', () {
      expect(kDepartments.length, 7);
      final m = departmentMeta('Storm Water Drain Department');
      expect(m.short, 'Storm Water');
      expect(m.slaDays, 7);
    });

    test('unknown department falls back safely', () {
      expect(departmentMeta('Nope').short, 'Unassigned');
      expect(departmentMeta(null).slaDays, 7);
    });

    test('slaDeadline adds the department window to created_at', () {
      final created = DateTime(2026, 7, 1);
      final d = slaDeadline(created, 'Solid Waste Management Department');
      expect(d, DateTime(2026, 7, 3));
    });
  });

  group('CoordinatorStore', () {
    Future<CoordinatorStore> store({DateTime Function()? now}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      return CoordinatorStore(prefs, now: now ?? () => DateTime(2026, 7, 23));
    }

    test('session round-trips', () async {
      final s = await store();
      expect(s.sessionUsername, isNull);
      await s.saveSession('raja');
      expect(s.sessionUsername, 'raja');
      await s.clearSession();
      expect(s.sessionUsername, isNull);
    });

    test('verify adds ownership per user; flagFalse removes it', () async {
      final s = await store();
      await s.verify('raja', 'issue-1');
      await s.verify('raja', 'issue-1'); // idempotent
      expect(s.verifiedIds('raja'), {'issue-1'});
      expect(s.verifiedIds('meena'), isEmpty);

      await s.flagFalse('raja', 'issue-1');
      expect(s.verifiedIds('raja'), isEmpty);
    });

    test('action log records newest-first and exposes latest kind', () async {
      final s = await store();
      await s.addAction(
          coordinator: 'raja', issueId: 'i1', kind: 'transfer');
      await s.addAction(coordinator: 'raja', issueId: 'i1', kind: 'close');
      await s.addAction(coordinator: 'raja', issueId: 'i2', kind: 'escalate');
      final latest = s.latestActionKindByIssue();
      expect(latest['i1'], 'close');
      expect(latest['i2'], 'escalate');
    });

    test('post/poll limits: 1 per kind per day per coordinator', () async {
      var day = DateTime(2026, 7, 23);
      final s = await store(now: () => day);

      expect(s.canPost('raja'), isTrue);
      expect(await s.addPost('raja', {'title': 'Update'}), isTrue);
      expect(s.canPost('raja'), isFalse);
      expect(await s.addPost('raja', {'title': 'Second'}), isFalse);

      // Poll limit is independent, and other users unaffected.
      expect(s.canPoll('raja'), isTrue);
      expect(await s.addPoll('raja', {'question': 'Q?'}), isTrue);
      expect(s.canPoll('raja'), isFalse);
      expect(s.canPost('meena'), isTrue);

      // Next day resets.
      day = DateTime(2026, 7, 24);
      expect(s.canPost('raja'), isTrue);
      expect(s.canPoll('raja'), isTrue);
    });

    test('published entries land as pending with author + date', () async {
      final s = await store();
      await s.addPost('suresh', {'title': 'Road update', 'body': 'x'});
      final posts = s.feed()['posts'] as List<dynamic>;
      expect(posts, hasLength(1));
      final p = posts.first as Map;
      expect(p['author'], 'suresh');
      expect(p['status'], 'pending');
      expect(p['title'], 'Road update');
    });
  });
}
