// Stub for web: push notifications are not supported; this avoids pulling in
// firebase_messaging and flutter_local_notifications on web builds.

class NotificationService {
  Future<void> initialize() async {}
}
