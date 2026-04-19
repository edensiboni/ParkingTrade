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
}
