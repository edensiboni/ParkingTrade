// Web-only: FCM for browser push. Stores token in Supabase and listens for messages.
// No local notifications plugin; browser shows notifications when app is in background.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WebNotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  String? _currentToken;

  Future<void> initialize() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        _currentToken = await _firebaseMessaging.getToken();
        await _storeFcmTokenIfUser();
        _firebaseMessaging.onTokenRefresh.listen((token) {
          _currentToken = token;
          _storeFcmTokenIfUser();
        });
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        _supabase.auth.onAuthStateChange.listen((_) => _storeFcmTokenIfUser());
      }
    } catch (e) {
      debugPrint('WebNotificationService init failed: $e');
    }
  }

  Future<void> _storeFcmTokenIfUser() async {
    final token = _currentToken;
    if (token == null) return;
    await _storeFcmToken(token);
  }

  Future<void> _storeFcmToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('user_fcm_tokens').upsert(
        {
          'user_id': user.id,
          'token': token,
          'platform': 'web',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      );
    } catch (e) {
      debugPrint('Failed to store web FCM token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // User is in app; optional: show in-app banner/snackbar via a global key
    debugPrint('Web push (foreground): ${message.notification?.title}');
  }
}
