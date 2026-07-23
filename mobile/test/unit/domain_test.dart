import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/domain/constituencies.dart';
import 'package:namma_kural/domain/geo_utils.dart';
import 'package:namma_kural/domain/status_meta.dart';
import 'package:namma_kural/domain/ticket.dart';

void main() {
  group('ticketNumber', () {
    test('derives FMS-XXXXXXXX from a uuid, stable per id', () {
      const id = 'fae06b9f-bd12-45dc-9c07-65c21b2e3640';
      expect(ticketNumber(id), 'FMS-FAE06B9F');
      expect(ticketNumber(id), ticketNumber(id));
    });

    test('handles null/empty/short ids', () {
      expect(ticketNumber(null), 'FMS-UNKNOWN');
      expect(ticketNumber(''), 'FMS-UNKNOWN');
      expect(ticketNumber('ab-c'), 'FMS-ABC');
    });
  });

  group('statusMeta', () {
    test('maps every backend status to the web labels', () {
      expect(statusMeta('SUBMITTED').label, 'Pending Verification');
      expect(statusMeta('ACTIVE').label, 'Assigned');
      expect(statusMeta('FORWARDED').label, 'In Progress');
      expect(statusMeta('IN_PROGRESS').label, 'In Progress');
      expect(statusMeta('PENDING_VERIFICATION').label, 'Verification Pending');
      expect(statusMeta('CLOSED').label, 'Resolved');
      expect(statusMeta('FALSE').label, 'Marked as false petition');
    });

    test('unknown status falls back to ACTIVE meta', () {
      expect(statusMeta('???').label, 'Assigned');
      expect(statusMeta(null).label, 'Assigned');
    });

    test('open flags match the web source of truth', () {
      expect(statusMeta('CLOSED').open, isFalse);
      expect(statusMeta('FALSE').open, isFalse);
      expect(statusMeta('ACTIVE').open, isTrue);
    });
  });

  group('progressIndex', () {
    test('mirrors the merged lifecycle mapping', () {
      expect(progressIndex('SUBMITTED'), 1);
      expect(progressIndex('ACTIVE'), 2);
      expect(progressIndex('FORWARDED'), 3);
      expect(progressIndex('IN_PROGRESS'), 3);
      expect(progressIndex('PENDING_VERIFICATION'), 4);
      expect(progressIndex('CLOSED'), 5);
      expect(progressIndex('FALSE'), -1);
      expect(progressIndex('other'), 0);
    });
  });

  group('haversineKm', () {
    test('zero distance for identical points', () {
      expect(haversineKm(13.0827, 80.2081, 13.0827, 80.2081), 0);
    });

    test('Chennai Central → Marina (~4.6 km) within tolerance', () {
      final d = haversineKm(13.0827, 80.2707, 13.0500, 80.2824);
      expect(d, greaterThan(3.0));
      expect(d, lessThan(5.0));
    });

    test('formats distances like the web cards', () {
      expect(formatDistanceKm(0.442), '442 m');
      expect(formatDistanceKm(1.44), '1.4 km');
    });
  });

  group('constituencies', () {
    test('ward 104 belongs to both Villivakkam and Egmore', () {
      final acs = constituenciesForWard(104);
      expect(acs, contains('14 - Villivakkam'));
      expect(acs, contains('16 - Egmore'));
    });

    test('unknown / null wards map to no ACs', () {
      expect(constituenciesForWard(999), isEmpty);
      expect(constituenciesForWard(null), isEmpty);
    });

    test('shortAC drops the numeric code', () {
      expect(shortAC('20 - Anna Nagar'), 'Anna Nagar');
      expect(shortAC(null), '');
    });

    test('titleCase renders zone names for display', () {
      expect(titleCase('ANNA NAGAR'), 'Anna Nagar');
    });

    test('16 constituencies in the dropdown, Egmore present', () {
      expect(kConstituencies.length, 16);
      expect(kConstituencies, contains('16 - Egmore'));
    });
  });
}
