import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../../models/message.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/empty_state.dart';

class ChatScreen extends StatefulWidget {
  final String bookingId;

  const ChatScreen({
    super.key,
    required this.bookingId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = ChatService();
  final _authService = AuthService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<List<Message>>? _streamSub;

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _hasText = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      final has = _messageController.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _loadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _chatService.getMessages(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, 'Could not load messages: $e');
    }
  }

  void _subscribeToMessages() {
    _streamSub = _chatService.streamMessages(widget.bookingId).listen((msgs) {
      if (!mounted) return;
      setState(() => _messages = msgs);
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    _messageController.clear();
    try {
      await _chatService.sendMessage(
        bookingId: widget.bookingId,
        content: content,
      );
    } catch (e) {
      if (mounted) AppSnack.error(context, 'Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _isCurrentUser(String senderId) {
    return _authService.currentUser?.id == senderId;
  }

  /// Returns a list of items: either a Message or a String (day label).
  List<Object> _buildItems() {
    if (_messages.isEmpty) return const [];
    final out = <Object>[];
    DateTime? lastDay;
    for (final m in _messages) {
      final local = m.createdAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (lastDay == null || day != lastDay) {
        out.add(_dayLabel(day));
        lastDay = day;
      }
      out.add(m);
    }
    return out;
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(day);
    return DateFormat('MMM d, y').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const EmptyState(
                        icon: Icons.forum_outlined,
                        title: 'Say hi',
                        message:
                            'Coordinate arrival and hand-off with the other resident.',
                      )
                    : _buildMessageList(scheme, theme),
          ),
          _Composer(
            controller: _messageController,
            hasText: _hasText,
            sending: _sending,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(ColorScheme scheme, ThemeData theme) {
    final items = _buildItems();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is String) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          );
        }

        final message = item as Message;
        final isMe = _isCurrentUser(message.senderId);
        final prev = index > 0 ? items[index - 1] : null;
        final next = index < items.length - 1 ? items[index + 1] : null;
        final isFirstInGroup = prev is! Message ||
            _isCurrentUser(prev.senderId) != isMe;
        final isLastInGroup = next is! Message ||
            _isCurrentUser((next).senderId) != isMe;

        return _Bubble(
          message: message,
          isMe: isMe,
          isFirstInGroup: isFirstInGroup,
          isLastInGroup: isLastInGroup,
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const _Bubble({
    required this.message,
    required this.isMe,
    required this.isFirstInGroup,
    required this.isLastInGroup,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final bg = isMe ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = isMe ? scheme.onPrimary : scheme.onSurface;
    final timeColor = isMe
        ? scheme.onPrimary.withValues(alpha: 0.75)
        : scheme.onSurfaceVariant;

    const r = Radius.circular(18);
    final radius = BorderRadius.only(
      topLeft: isMe ? r : (isFirstInGroup ? r : const Radius.circular(6)),
      topRight: isMe ? (isFirstInGroup ? r : const Radius.circular(6)) : r,
      bottomLeft: isMe ? r : (isLastInGroup ? const Radius.circular(4) : r),
      bottomRight: isMe ? (isLastInGroup ? const Radius.circular(4) : r) : r,
    );

    final timeText = DateFormat('h:mm a').format(message.createdAt.toLocal());

    return Padding(
      padding: EdgeInsets.only(
        top: isFirstInGroup ? 6 : 2,
        bottom: isLastInGroup ? 6 : 2,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: radius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    message.content,
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: timeColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final bool sending;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.hasText,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSend = hasText && !sending;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Message…',
                    filled: true,
                    fillColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          BorderSide(color: scheme.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: canSend ? scheme.primary : scheme.surfaceContainerHighest,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: canSend ? onSend : null,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.send_rounded,
                    size: 20,
                    color: canSend ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
