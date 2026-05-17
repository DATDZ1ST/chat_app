import 'dart:async';

import 'package:chat_app/screens/group_settings.dart';
import 'package:chat_app/widgets/chat_messages.dart';
import 'package:chat_app/widgets/new_message.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GroupConversationScreen extends StatefulWidget {
  const GroupConversationScreen({
    super.key,
    required this.chatId,
    this.initialMessageId,
  });

  final String chatId;
  final String? initialMessageId;

  @override
  State<GroupConversationScreen> createState() =>
      _GroupConversationScreenState();
}

class _GroupConversationScreenState extends State<GroupConversationScreen> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _messagesSubscription;
  bool _isMarkingMessagesAsRead = false;

  DocumentReference<Map<String, dynamic>> get _chatDocument =>
      FirebaseFirestore.instance.collection('private_chats').doc(widget.chatId);

  @override
  void initState() {
    super.initState();
    _startMessagesReadTracking();
  }

  @override
  void didUpdateWidget(covariant GroupConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _messagesSubscription?.cancel();
      _startMessagesReadTracking();
    }
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    super.dispose();
  }

  String? _readString(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) {
      return null;
    }

    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  List<String> _readStringList(Map<String, dynamic>? data, String key) {
    final value = data?[key];
    if (value is! Iterable) {
      return const [];
    }

    return value.whereType<String>().toList();
  }

  String _quickReactionFor(Map<String, dynamic>? chatData) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return '👍';
    }

    final rawMap = chatData?['quickReactions'];
    if (rawMap is! Map) {
      return '👍';
    }

    final reaction = rawMap[currentUserId];
    if (reaction is String && reaction.trim().isNotEmpty) {
      return reaction.trim();
    }

    return '👍';
  }

  String? _groupImageUrl(Map<String, dynamic>? chatData) {
    return _readString(chatData, const [
      'imageUrl',
      'image_url',
      'groupImage',
      'groupImageUrl',
    ]);
  }

  bool _isGroupDissolved(Map<String, dynamic>? chatData) {
    return chatData?['isDissolved'] == true ||
        chatData?['status'] == 'dissolved';
  }

  Map<String, dynamic>? _readConversationTheme(Map<String, dynamic>? chatData) {
    final rawTheme = chatData?['theme'];
    if (rawTheme is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(rawTheme);
  }

  Color? _readThemeColor(Map<String, dynamic>? chatData) {
    final theme = _readConversationTheme(chatData);
    if (theme?['type'] != 'color') {
      return null;
    }

    final colorValue = theme?['backgroundColor'];
    if (colorValue is int) {
      return Color(colorValue);
    }
    if (colorValue is num) {
      return Color(colorValue.toInt());
    }

    return null;
  }

  String? _readThemeImageUrl(Map<String, dynamic>? chatData) {
    final theme = _readConversationTheme(chatData);
    if (theme?['type'] != 'image') {
      return null;
    }

    return _readString(theme, const ['imageUrl']);
  }

  BoxDecoration _conversationThemeDecoration(
    BuildContext context,
    Map<String, dynamic>? chatData,
  ) {
    final imageUrl = _readThemeImageUrl(chatData);
    final color = _readThemeColor(chatData);

    return BoxDecoration(
      color: imageUrl == null
          ? color ?? Theme.of(context).colorScheme.surface
          : Colors.black,
      image: imageUrl == null
          ? null
          : DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
    );
  }

  Future<void> _openGroupSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GroupSettingsScreen(chatId: widget.chatId),
      ),
    );
  }

  Timestamp? _readConversationClearedAt(
    Map<String, dynamic>? chatData,
    String userId,
  ) {
    final clearedAtByUser = chatData?['clearedAtByUser'];
    if (clearedAtByUser is! Map) {
      return null;
    }

    final clearedAt = clearedAtByUser[userId];
    return clearedAt is Timestamp ? clearedAt : null;
  }

  bool _wasMessageClearedForCurrentUser(
    Map<String, dynamic>? messageData,
    Timestamp? clearedAt,
  ) {
    if (messageData == null || clearedAt == null) {
      return false;
    }

    final createdAt = messageData['createdAt'];
    if (createdAt is! Timestamp) {
      return false;
    }

    return createdAt.millisecondsSinceEpoch <= clearedAt.millisecondsSinceEpoch;
  }

  void _startMessagesReadTracking() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    _messagesSubscription = _chatDocument
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _markMessagesAsRead(snapshot.docs, currentUser.uid);
        });
  }

  Future<void> _markMessagesAsRead(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> messageDocs,
    String currentUserId,
  ) async {
    if (_isMarkingMessagesAsRead) {
      return;
    }

    final chatSnapshot = await _chatDocument.get();
    final clearedAt = _readConversationClearedAt(
      chatSnapshot.data(),
      currentUserId,
    );

    final unreadIncomingMessages = messageDocs.where((messageDoc) {
      final messageData = messageDoc.data();
      final senderId = messageData['userId'] as String?;
      final readBy = List<String>.from(messageData['readBy'] ?? const []);
      return senderId != currentUserId &&
          !readBy.contains(currentUserId) &&
          !_wasMessageClearedForCurrentUser(messageData, clearedAt);
    }).toList();

    if (unreadIncomingMessages.isEmpty) {
      return;
    }

    _isMarkingMessagesAsRead = true;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final messageDoc in unreadIncomingMessages) {
        final readBy = List<String>.from(
          messageDoc.data()['readBy'] ?? const [],
        );
        batch.update(messageDoc.reference, {
          'readBy': {...readBy, currentUserId}.toList(),
        });
      }
      await batch.commit();
    } finally {
      _isMarkingMessagesAsRead = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatDocument.snapshots(),
      builder: (context, snapshot) {
        final chatData = snapshot.data?.data();
        final groupName =
            _readString(chatData, const ['name', 'groupName']) ?? 'Nhóm chat';
        final groupImageUrl = _groupImageUrl(chatData);
        final participants = _readStringList(chatData, 'participants');
        final quickReaction = _quickReactionFor(chatData);
        final isDissolved = _isGroupDissolved(chatData);
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final isCurrentMember =
            currentUserId != null && participants.contains(currentUserId);
        final isChatUnavailable =
            chatData != null && (isDissolved || !isCurrentMember);
        final unavailableMessage = isDissolved
            ? 'Nhóm đã được giải tán. Bạn không thể gửi tin nhắn mới.'
            : 'Bạn đã rời nhóm. Bạn không thể gửi tin nhắn mới.';

        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _openGroupSettings,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      foregroundImage: groupImageUrl != null
                          ? NetworkImage(groupImageUrl)
                          : null,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      child: groupImageUrl == null
                          ? const Icon(Icons.groups_rounded)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(groupName, overflow: TextOverflow.ellipsis),
                          if (participants.isNotEmpty)
                            Text(
                              '${participants.length} thành viên',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Thông tin nhóm',
                onPressed: _openGroupSettings,
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            child: Column(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: _conversationThemeDecoration(context, chatData),
                    child: ChatMessages(
                      chatId: widget.chatId,
                      isGroup: true,
                      initialMessageId: widget.initialMessageId,
                    ),
                  ),
                ),
                if (isChatUnavailable)
                  SafeArea(
                    top: false,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      color: Theme.of(context).colorScheme.surface,
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(unavailableMessage)),
                        ],
                      ),
                    ),
                  )
                else
                  NewMessage(
                    chatId: widget.chatId,
                    isGroup: true,
                    participantIds: participants,
                    quickReaction: quickReaction,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
