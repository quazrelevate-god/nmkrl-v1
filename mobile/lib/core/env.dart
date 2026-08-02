import 'package:flutter/foundation.dart' show kReleaseMode;

/// Environment configuration.
///
/// The API base can be overridden at build time:
///   flutter run --dart-define=API_BASE=https://nmkrl-v1-production-587d.up.railway.app
///
/// When no override is given the default is build-mode aware:
///   * release  → the production Railway backend, so a plain
///                `flutter build apk --release` (e.g. an APK to hand to a
///                tester) is always reachable off-device.
///   * debug    → the Android-emulator loopback (10.0.2.2 → host machine's
///                localhost:8000 dev backend), for local development.
/// This prevents a release build from silently shipping the dev loopback,
/// which is unreachable on a real phone.
class Env {
  Env._();

  /// Production FastAPI backend (Railway). Serves `/api/*` directly.
  static const String _prodBackend =
      'https://nmkrl-v1-production-587d.up.railway.app';

  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: kReleaseMode ? _prodBackend : 'http://10.0.2.2:8000',
  );
}
