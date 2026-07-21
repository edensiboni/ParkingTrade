import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message.dart';

class ChatService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Send a message via the send-chat-message edge function.
  //
  // The edge function enforces that the sender is a participant in the
  // booking and triggers a push notification to the other party. Realtime
  // subscriptions still deliver the inserted row to any open chat view.
  Future<Message> sendMessage({
    required String bookingId,
    required String content,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase.functions.invoke(
      'send-chat-message',
      body: {
        'booking_id': bookingId,
        'content': content,
      },
    );

    if (response.status != 200) {
      final data = response.data;
      final error = (data is Map && data['error'] != null)
          ? data['error'].toString()
          : 'Failed to send message';
      throw Exception(error);
    }

    return Message.fromJson(response.data['message']);
  }

  // Get messages for a booking
  Future<List<Message>> getMessages(String bookingId) async {
    final response = await _supabase
        .from('messages')
        .select()
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true);

    return (response as List).map((json) => Message.fromJson(json)).toList();
  }

  // Stream messages for real-time updates
  Stream<List<Message>> streamMessages(String bookingId) {
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true)
        .map((data) => data.map((json) => Message.fromJson(json)).toList());
  }

  // Mark every message in [bookingId] as read for the current user.
  //
  // Upserts the caller's read receipt to now() via the mark_booking_read
  // RPC (migration 032). Best-effort: a failed read-marker must never
  // block the chat UI, so errors are swallowed.
  Future<void> markBookingRead(String bookingId) async {
    try {
      await _supabase.rpc(
        'mark_booking_read',
        params: {'p_booking_id': bookingId},
      );
    } catch (_) {
      // Non-fatal — the badge simply clears on the next successful call.
    }
  }

  // Unread message counts for the current user, keyed by booking id.
  //
  // Backed by the get_unread_message_counts RPC (migration 032). Only
  // bookings with at least one unread message from the other party are
  // present in the map.
  Future<Map<String, int>> getUnreadCounts() async {
    final rows = await _supabase.rpc('get_unread_message_counts');
    final counts = <String, int>{};
    for (final row in (rows as List)) {
      final id = row['booking_id'] as String?;
      final count = (row['unread_count'] as num?)?.toInt() ?? 0;
      if (id != null && count > 0) counts[id] = count;
    }
    return counts;
  }
}
