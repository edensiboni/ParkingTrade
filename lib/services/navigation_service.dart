import 'package:flutter/material.dart';

import '../screens/bookings/booking_detail_screen.dart';
import '../screens/chat/chat_screen.dart';

/// Global navigator key.
///
/// Used to navigate from contexts that don't have a [BuildContext] — for
/// example, notification tap handlers that fire outside the widget tree.
/// [MaterialApp.navigatorKey] is set to this in [main.dart].
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Handle a notification tap by inspecting the FCM [data] payload and
/// deep-linking to the appropriate screen.
///
/// Payload contract (set by the edge functions in `supabase/functions`):
/// - `type` — one of `booking_request`, `booking_approved`, `booking_rejected`,
///   `chat_message`
/// - `booking_id` — the booking the notification refers to
void handleNotificationTap(Map<String, dynamic> data) {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;

  final type = data['type']?.toString();
  final bookingId = data['booking_id']?.toString();
  if (bookingId == null || bookingId.isEmpty) return;

  switch (type) {
    case 'chat_message':
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(bookingId: bookingId),
        ),
      );
      return;
    case 'booking_request':
    case 'booking_approved':
    case 'booking_rejected':
      navigator.push(
        MaterialPageRoute(
          builder: (_) => BookingDetailScreen(bookingId: bookingId),
        ),
      );
      return;
    default:
      // Unknown type — fall back to booking detail if we have an id.
      navigator.push(
        MaterialPageRoute(
          builder: (_) => BookingDetailScreen(bookingId: bookingId),
        ),
      );
  }
}
