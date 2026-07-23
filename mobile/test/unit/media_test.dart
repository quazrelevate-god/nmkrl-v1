import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/core/env.dart';
import 'package:namma_kural/data/media.dart';

void main() {
  group('mediaRef', () {
    test('absolute http(s) urls pass through', () {
      final r = mediaRef('https://example.com/a.jpg');
      expect(r, isA<NetworkMedia>());
      expect((r as NetworkMedia).url, 'https://example.com/a.jpg');
    });

    test('/community paths resolve to bundled assets', () {
      final r = mediaRef('/community/community-10.webp');
      expect(r, isA<AssetMedia>());
      expect((r as AssetMedia).asset, 'assets/community/community-10.webp');
    });

    test('bundled avif was converted to jpg — path rewrites', () {
      final r = mediaRef('/community/community-01.avif');
      expect((r as AssetMedia).asset, 'assets/community/community-01.jpg');
    });

    test('/uploads paths resolve against the backend base', () {
      final r = mediaRef('/uploads/images/x.jpg');
      expect((r as NetworkMedia).url, '${Env.apiBase}/uploads/images/x.jpg');
    });

    test('null/empty yield no media', () {
      expect(mediaRef(null), isNull);
      expect(mediaRef(''), isNull);
    });
  });
}
