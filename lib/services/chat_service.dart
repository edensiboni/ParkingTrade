import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message.dart';

class ChatService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Send a message
  Future<Message> sendMessage({
    required String bookingId,
    required String content,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final response = await _supabase
        .from('messages')
        .insert({
          'booking_id': bookingId,
          'sender_id': user.id,
          'content': content,
        })
        .select()
        .single();

    return Message.fromJson(response);
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
