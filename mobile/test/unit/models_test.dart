import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/domain/models/boundary_data.dart';
import 'package:namma_kural/domain/models/issue.dart';
import 'package:namma_kural/domain/models/locate_result.dart';

void main() {
  group('Issue.fromJson', () {
    final sample = <String, dynamic>{
      'id': 'fae06b9f-bd12-45dc-9c07-65c21b2e3640',
      'title': 'Garbage not cleared for several days',
      'image_url': '/community/community-10.webp',
      'audio_url': null,
      'transcript': 'The garbage bins are overflowing',
      'latitude': 13.0703,
      'longitude': 80.2610,
      'status': 'FALSE',
      'upvotes': 23,
      'created_at': '2026-07-10T08:30:00+00:00',
      'area_name': 'Egmore',
      'ward_no': 108,
      'zone': '8',
      'coordinator_message': 'Verified on site — bins already cleared.',
      'summary_highlights': ['Garbage', 'Health hazard'],
    };

    test('parses the full backend shape', () {
      final i = Issue.fromJson(sample);
      expect(i.id, 'fae06b9f-bd12-45dc-9c07-65c21b2e3640');
      expect(i.title, 'Garbage not cleared for several days');
      expect(i.imageUrl, '/community/community-10.webp');
      expect(i.latitude, closeTo(13.0703, 1e-9));
      expect(i.status, 'FALSE');
      expect(i.upvotes, 23);
      expect(i.createdAt, isNotNull);
      expect(i.areaName, 'Egmore');
      expect(i.wardNo, 108);
      expect(i.summaryHighlights, ['Garbage', 'Health hazard']);
      expect(i.distanceM, isNull);
    });

    test('tolerates nulls, strings-as-numbers and missing fields', () {
      final i = Issue.fromJson(<String, dynamic>{
        'id': 'x',
        'latitude': '13.5',
        'longitude': null,
        'upvotes': '7',
        'ward_no': '104',
        'area_name': '  ',
      });
      expect(i.latitude, 13.5);
      expect(i.longitude, 0);
      expect(i.upvotes, 7);
      expect(i.wardNo, 104);
      expect(i.areaName, isNull); // blank collapses to null
      expect(i.title, 'Street Issue');
      expect(i.status, 'ACTIVE');
      expect(i.summaryHighlights, isEmpty);
    });

    test('nearby responses carry distance_m', () {
      final i = Issue.fromJson(
          <String, dynamic>{'id': 'x', 'distance_m': 442.4});
      expect(i.distanceM, closeTo(442.4, 1e-9));
    });
  });

  group('ReportOutcome', () {
    test('created issue passes through', () {
      final o = ReportOutcome.fromJson(
          <String, dynamic>{'id': 'new-1', 'status': 'SUBMITTED'});
      expect(o.isDuplicate, isFalse);
      expect(o.issue!.id, 'new-1');
    });

    test('duplicate_exists yields the existing issue', () {
      final o = ReportOutcome.fromJson(<String, dynamic>{
        'duplicate_exists': true,
        'existing_issue': {'id': 'dup-1', 'upvotes': 3, 'distance_m': 12.0},
      });
      expect(o.isDuplicate, isTrue);
      expect(o.duplicate!.id, 'dup-1');
      expect(o.duplicate!.distanceM, 12.0);
    });
  });

  group('BoundaryData', () {
    test('parses Polygon + MultiPolygon features and computes centroids', () {
      final data = BoundaryData.fromJson(<String, dynamic>{
        'zones': {
          'features': [
            {
              'properties': {'zone': '8', 'zone_name': 'ANNA NAGAR'},
              'geometry': {
                'type': 'MultiPolygon',
                'coordinates': [
                  [
                    [
                      [80.0, 13.0],
                      [80.1, 13.0],
                      [80.1, 13.1],
                      [80.0, 13.0],
                    ]
                  ]
                ],
              },
            }
          ]
        },
        'wards': {
          'features': [
            {
              'properties': {'ward': '108', 'zone': '8'},
              'geometry': {
                'type': 'Polygon',
                'coordinates': [
                  [
                    [80.0, 13.0],
                    [80.2, 13.0],
                    [80.2, 13.2],
                    [80.0, 13.2],
                  ]
                ],
              },
            }
          ]
        },
      });

      expect(data.zones, hasLength(1));
      expect(data.zones.first.zoneName, 'ANNA NAGAR');
      expect(data.wards, hasLength(1));
      final ward = data.wards.first;
      expect(ward.ward, '108');
      // GeoJSON is [lng, lat] — LatLng must swap.
      expect(ward.parts.first.first.first.latitude, 13.0);
      expect(ward.parts.first.first.first.longitude, 80.0);
      final c = ward.centroid();
      expect(c.latitude, closeTo(13.1, 1e-9));
      expect(c.longitude, closeTo(80.1, 1e-9));
    });

    test('empty collections parse safely', () {
      final data = BoundaryData.fromJson(<String, dynamic>{});
      expect(data.zones, isEmpty);
      expect(data.wards, isEmpty);
    });
  });

  group('LocateResult', () {
    test('parses an inside-GCC response', () {
      final r = LocateResult.fromJson(<String, dynamic>{
        'zone': '8',
        'zone_name': 'ANNA NAGAR',
        'ward': '103',
        'detected_constituencies': ['20 - Anna Nagar', '14 - Villivakkam'],
        'inside': true,
      });
      expect(r.inside, isTrue);
      expect(r.wardNumber, 103);
      expect(r.constituencies.first, '20 - Anna Nagar');
    });

    test('outside GCC → inside false, null ward', () {
      final r = LocateResult.fromJson(<String, dynamic>{
        'zone': null,
        'ward': null,
        'inside': false,
      });
      expect(r.inside, isFalse);
      expect(r.wardNumber, isNull);
    });
  });
}
