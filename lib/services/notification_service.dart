import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SupabaseClient _supabase = Supabase.instance.client;

  // Initialize notifications (no-op on web; FCM/local notifications are mobile-only)
  Future<void> initialize() async {
    if (kIsWeb) return;
    // Request permissions
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // Initialize local notifications
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings();
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Get FCM token and store it
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _storeFcmToken(token);
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen(_storeFcmToken);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background messages (configured in main.dart)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);
    }
  }

  // Store FCM token in Supabase for server-side push (mobile only; platform is ios or android)
  Future<void> _storeFcmToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final platform = Platform.isIOS ? 'ios' : 'android';
    try {
      await _supabase.from('user_fcm_tokens').upsert(
        {
          'user_id': user.id,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      );
    } catch (e) {
      debugPrint('Failed to store FCM token: $e');
    }
  }

  // Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    _showLocalNotification(message);
  }

  // Handle background message tap
  void _handleBackgroundMessageTap(RemoteMessage message) {
    // Navigate to relevant screen based on message data
    // This would typically use a navigation service
  }

  // Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'parking_trade_channel',
      'Parking Trade Notifications',
      channelDescription: 'Notifications for parking booking updates',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: message.hashCode,
      title: message.notification?.title ?? 'Parking Trade',
      body: message.notification?.body ?? '',
      notificationDetails: notificationDetails,
      payload: message.data.toString(),
    );
  }

  // Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // Navigate to relevant screen based on payload
    // This would typically use a navigation service
  }

}

