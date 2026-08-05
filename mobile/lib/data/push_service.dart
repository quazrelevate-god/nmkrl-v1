import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

/// Android channel id. MUST match `_CHANNEL_ID` in backend/push.py — a mismatch
/// means Android silently drops the heads-up banner and sound.
const String _kChannelId = 'nk_alerts';
const String _kChannelName = 'Grievance updates';

/// Background/terminated handler. Must be a top-level function annotated with
/// @pragma('vm:entry-point') — Flutter spins up a fresh isolate to run it, and
/// tree-shaking would otherwise strip it from release builds.
///
/// It deliberately does nothing: our messages carry a `notification` block, so
/// Android renders them from the system tray without our code running. This
/// exists only so the plugin has a registered handler.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

/// Owns FCM setup, the device token, and foreground presentation.
///
/// Push is strictly additive: everything here is wrapped so that a missing
/// google-services.json, a denied permission, or an offline device degrades to
/// the existing 15s polling rather than breaking sign-in or startup.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();

  bool _ready = false;
  String? _token;

  /// The current FCM registration token, or null when push is unavailable.
  String? get token => _token;

  /// Called once from main() before runApp.
  Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      // Android 13+ gates notifications behind a runtime permission; without
      // it nothing is ever displayed.
      await FirebaseMessaging.instance.requestPermission();

      // Android 8+ requires an explicit high-importance channel for heads-up
      // banners. Created here so it exists before the first message lands.
      const android = AndroidNotificationChannel(
        _kChannelId,
        _kChannelName,
        description: 'Updates on grievances you reported or manage',
        importance: Importance.high,
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(android);

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      _token = await FirebaseMessaging.instance.getToken();

      // A token can rotate at any time (app restore, cache clear). Re-bind it
      // to whoever is signed in, or the device silently stops receiving push.
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        _token = t;
        final rebind = _rebind;
        if (rebind != null) await rebind(t);
      });

      _ready = true;
    } catch (e) {
      // No google-services.json, no Play Services, emulator without Google
      // APIs — all land here. Polling still covers the foreground case.
      debugPrint('[push] disabled: $e');
    }
  }

  /// Set by the auth layer so a refreshed token can be re-registered against
  /// the account that is currently signed in.
  Future<void> Function(String token)? _rebind;

  /// Bind this device to [recipientId]. Call after every successful sign-in.
  Future<void> bind({
    required ApiClient api,
    required String recipientType,
    required String recipientId,
  }) async {
    if (!_ready || recipientId.isEmpty) return;
    _rebind = (t) => api.registerDeviceToken(
          token: t,
          recipientType: recipientType,
          recipientId: recipientId,
          platform: Platform.isIOS ? 'ios' : 'android',
        );
    final t = _token;
    if (t != null) await _rebind!(t);
  }

  /// Release this device on sign-out, so the next account signing in here does
  /// not inherit the previous one's alerts.
  Future<void> unbind(ApiClient api) async {
    _rebind = null;
    final t = _token;
    if (t == null) return;
    await api.unregisterDeviceToken(t);
  }

  /// FCM does not raise a tray notification while the app is foregrounded.
  /// The in-app banner (NotificationPoller) covers that case, so nothing extra
  /// is shown here — this hook exists for callers that want to react.
  Stream<RemoteMessage> get onForegroundMessage => FirebaseMessaging.onMessage;

  /// Message that launched the app from a terminated state, if any.
  Future<RemoteMessage?> initialMessage() =>
      FirebaseMessaging.instance.getInitialMessage();

  /// Taps on a tray notification while the app was backgrounded.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;
}
