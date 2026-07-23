/// Environment configuration.
///
/// The API base is injected at build time:
///   flutter run --dart-define=API_BASE=https://nmkrl-v1-production-587d.up.railway.app
///
/// Defaults to the Android-emulator loopback (10.0.2.2 → host machine's
/// localhost:8000 dev backend), mirroring the web app's local-dev default.
class Env {
  Env._();

  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
