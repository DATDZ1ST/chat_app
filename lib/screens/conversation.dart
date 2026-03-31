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
  });

  final String chatId;
  final String otherUserId;
}

class ConversationScreen extends StatefulWidget {
  static const routeName = '/conversation';

  const ConversationScreen({super.key, required this.arguments});

  final ConversationScreenArguments arguments;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
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

    final unreadIncomingMessages = messageDocs.where((messageDoc) {
      final messageData = messageDoc.data();
      final senderId = messageData['userId'] as String?;
      final readBy = List<String>.from(messageData['readBy'] ?? const []);
      return senderId != currentUserId && !readBy.contains(currentUserId);
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
          body: Column(
            children: [
              Expanded(
                child: ChatMessages(
                  chatId: widget.arguments.chatId,
                  otherUserId: widget.arguments.otherUserId,
                ),
              ),
              NewMessage(
                chatId: widget.arguments.chatId,
                otherUserId: widget.arguments.otherUserId,
              ),
            ],
          ),
        );
      },
    );
  }
}
