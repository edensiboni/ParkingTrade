import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SupabaseClient _supabase = Supabase.instance.client;

  // Initialize notifications
  Future<void> initialize() async {
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
        initSettings,
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

  // Store FCM token in Supabase (you may want to create a user_tokens table)
  Future<void> _storeFcmToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // TODO: Store token in database table (e.g., user_fcm_tokens)
    // This would typically be done via an Edge Function or directly in a table
    // For now, we'll just log it
    print('FCM Token: $token');
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
      message.hashCode,
      message.notification?.title ?? 'Parking Trade',
      message.notification?.body ?? '',
      notificationDetails,
      payload: message.data.toString(),
    );
  }

  // Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // Navigate to relevant screen based on payload
    // This would typically use a navigation service
  }

}

