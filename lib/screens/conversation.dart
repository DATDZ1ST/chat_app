import 'dart:async';

import 'package:chat_app/widgets/chat_messages.dart';
import 'package:chat_app/widgets/new_message.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ConversationScreenArguments {
  const ConversationScreenArguments({
    required this.chatId,
    required this.otherUserId,
    this.initialMessageId,
  });

  final String chatId;
  final String otherUserId;
  final String? initialMessageId;
}

class ConversationScreen extends StatefulWidget {
  static const routeName = '/conversation';

  const ConversationScreen({super.key, required this.arguments});

  final ConversationScreenArguments arguments;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final GlobalKey<ChatMessagesState> _chatMessagesKey =
      GlobalKey<ChatMessagesState>();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _messagesSubscription;
  bool _isMarkingMessagesAsRead = false;

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

  List<Map<String, dynamic>> _readPinnedMessages(
    Map<String, dynamic>? chatData,
  ) {
    if (chatData == null) {
      return const [];
    }

    final normalized = <Map<String, dynamic>>[];
    final rawPinnedMessages = chatData['pinnedMessages'];

    if (rawPinnedMessages is Iterable) {
      for (final item in rawPinnedMessages) {
        if (item is! Map) {
          continue;
        }

        final rawMap = Map<String, dynamic>.from(item);
        final messageId = _readString(rawMap, const ['messageId']);
        if (messageId == null) {
          continue;
        }

        normalized.add({
          'messageId': messageId,
          'text': _readString(rawMap, const ['text', 'pinnedText']) ?? '',
          'pinnedAt': rawMap['pinnedAt'],
        });
      }
    }

    final legacyPinnedMessageId = _readString(chatData, const [
      'pinnedMessageId',
    ]);
    if (legacyPinnedMessageId != null &&
        !normalized.any((item) => item['messageId'] == legacyPinnedMessageId)) {
      normalized.add({
        'messageId': legacyPinnedMessageId,
        'text': _readString(chatData, const ['pinnedMessageText']) ?? '',
        'pinnedAt': chatData['pinnedAt'],
      });
    }

    normalized.sort((a, b) {
      final aPinnedAt = a['pinnedAt'];
      final bPinnedAt = b['pinnedAt'];
      final aMillis = aPinnedAt is Timestamp
          ? aPinnedAt.millisecondsSinceEpoch
          : 0;
      final bMillis = bPinnedAt is Timestamp
          ? bPinnedAt.millisecondsSinceEpoch
          : 0;
      return bMillis.compareTo(aMillis);
    });

    return normalized;
  }

  bool _isDeletedForMe(Map<String, dynamic>? data, String userId) {
    final deletedFor = List<String>.from(data?['deletedFor'] ?? const []);
    return deletedFor.contains(userId);
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

  String _messagePreview(Map<String, dynamic>? messageData) {
    if (messageData == null) {
      return '';
    }

    if (messageData['deletedForEveryone'] == true) {
      return 'Tin nhắn đã bị thu hồi';
    }

    return _readString(messageData, const ['text']) ?? '';
  }

  String _formatPinnedDate(dynamic pinnedAt) {
    if (pinnedAt is! Timestamp) {
      return '';
    }

    final date = pinnedAt.toDate();
    return '${date.day} thg ${date.month}';
  }

  Future<void> _showPinnedMessagesSheet(
    BuildContext context, {
    required List<Map<String, dynamic>> pinnedMessages,
    required String currentUserId,
    required Timestamp? clearedAt,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF252529),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.52,
            minChildSize: 0.34,
            maxChildSize: 0.82,
            builder: (context, scrollController) {
              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Tin nhắn đã ghim',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: pinnedMessages.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, index) {
                        final pinnedMessage = pinnedMessages[index];
                        final pinnedMessageId =
                            pinnedMessage['messageId'] as String;
                        final storedText =
                            _readString(pinnedMessage, const [
                              'text',
                              'pinnedText',
                            ]) ??
                            '';
                        final dateLabel = _formatPinnedDate(
                          pinnedMessage['pinnedAt'],
                        );

                        return StreamBuilder<
                          DocumentSnapshot<Map<String, dynamic>>
                        >(
                          stream: FirebaseFirestore.instance
                              .collection('private_chats')
                              .doc(widget.arguments.chatId)
                              .collection('messages')
                              .doc(pinnedMessageId)
                              .snapshots(),
                          builder: (context, snapshot) {
                            final messageData = snapshot.data?.data();
                            if (messageData != null &&
                                (_isDeletedForMe(messageData, currentUserId) ||
                                    _wasMessageClearedForCurrentUser(
                                      messageData,
                                      clearedAt,
                                    ))) {
                              return const SizedBox.shrink();
                            }

                            final preview = messageData == null
                                ? storedText
                                : _messagePreview(messageData);
                            if (preview.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return InkWell(
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                _chatMessagesKey.currentState?.scrollToMessage(
                                  pinnedMessageId,
                                );
                              },
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.push_pin,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (dateLabel.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              child: Text(
                                                dateLabel,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white10,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            child: Text(
                                              preview,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Colors.white54,
                                      size: 28,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPinnedMessagesBanner(
    BuildContext context, {
    required List<Map<String, dynamic>> pinnedMessages,
    required String currentUserId,
    required Timestamp? clearedAt,
  }) {
    final latestPinnedMessage = pinnedMessages.first;
    final pinnedMessageId = latestPinnedMessage['messageId'] as String;
    final storedText =
        _readString(latestPinnedMessage, const ['text', 'pinnedText']) ?? '';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('private_chats')
          .doc(widget.arguments.chatId)
          .collection('messages')
          .doc(pinnedMessageId)
          .snapshots(),
      builder: (context, snapshot) {
        final messageData = snapshot.data?.data();
        if (messageData != null &&
            (_isDeletedForMe(messageData, currentUserId) ||
                _wasMessageClearedForCurrentUser(messageData, clearedAt))) {
          return const SizedBox.shrink();
        }

        final preview = messageData == null
            ? storedText
            : _messagePreview(messageData);
        if (preview.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          decoration: BoxDecoration(
            color: const Color(0xFF4B4A5D),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _showPinnedMessagesSheet(
                context,
                pinnedMessages: pinnedMessages,
                currentUserId: currentUserId,
                clearedAt: clearedAt,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(
                        Icons.push_pin,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (pinnedMessages.length > 1) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${pinnedMessages.length}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white70,
                      size: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _startMessagesReadTracking();
  }

  @override
  void didUpdateWidget(covariant ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.arguments.chatId != widget.arguments.chatId) {
      _messagesSubscription?.cancel();
      _startMessagesReadTracking();
    }
  }

  void _startMessagesReadTracking() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    _messagesSubscription = FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.arguments.chatId)
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

    final chatSnapshot = await FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.arguments.chatId)
        .get();
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
  void dispose() {
    _messagesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.arguments.otherUserId)
          .snapshots(),
      builder: (context, snapshot) {
        final otherUserData = snapshot.data?.data();
        final username =
            _readString(otherUserData, const ['username']) ?? 'User';
        final userImage = _readString(otherUserData, const [
          'image_url',
          'imageUrl',
          'userImage',
        ]);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                CircleAvatar(
                  foregroundImage: userImage != null
                      ? NetworkImage(userImage)
                      : null,
                  child: userImage == null
                      ? Text(username[0].toUpperCase())
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(username, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('private_chats')
                  .doc(widget.arguments.chatId)
                  .snapshots(),
              builder: (context, chatSnapshot) {
                final chatData = chatSnapshot.data?.data();
                final pinnedMessages = _readPinnedMessages(chatData);
                final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                final clearedAt = currentUserId == null
                    ? null
                    : _readConversationClearedAt(chatData, currentUserId);

                return Column(
                  children: [
                    if (pinnedMessages.isNotEmpty && currentUserId != null)
                      _buildPinnedMessagesBanner(
                        context,
                        pinnedMessages: pinnedMessages,
                        currentUserId: currentUserId,
                        clearedAt: clearedAt,
                      ),
                    Expanded(
                      child: ChatMessages(
                        key: _chatMessagesKey,
                        chatId: widget.arguments.chatId,
                        otherUserId: widget.arguments.otherUserId,
                        initialMessageId: widget.arguments.initialMessageId,
                      ),
                    ),
                    NewMessage(
                      chatId: widget.arguments.chatId,
                      otherUserId: widget.arguments.otherUserId,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
