import 'package:chat_app/widgets/message_bubble.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatMessages extends StatelessWidget {
  const ChatMessages({
    super.key,
    required this.chatId,
    required this.otherUserId,
  });

  final String chatId;
  final String otherUserId;

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

  String? _resolveUsername(
    Map<String, dynamic>? profileData,
    Map<String, dynamic> messageData,
  ) {
    final profileUsername = _readString(profileData, const ['username']);
    if (profileUsername != null) {
      return profileUsername;
    }

    final messageUsername = _readString(messageData, const ['username']);
    if (messageUsername == null) {
      return null;
    }

    if (!messageUsername.contains('@')) {
      return messageUsername;
    }

    final emailLocalPart = messageUsername.split('@').first.trim();
    return emailLocalPart.isEmpty ? null : emailLocalPart;
  }

  String? _resolveUserImage(
    Map<String, dynamic>? profileData,
    Map<String, dynamic> messageData,
  ) {
    return _readString(profileData, const [
          'image_url',
          'imageUrl',
          'userImage',
        ]) ??
        _readString(messageData, const ['userImage', 'image_url']);
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedUser = FirebaseAuth.instance.currentUser!;

    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (ctx, userSnapshots) {
        if (userSnapshots.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (userSnapshots.hasError) {
          return Center(child: Text('Something went wrong...'));
        }

        final userProfiles = {
          for (final userDoc in userSnapshots.data?.docs ?? [])
            userDoc.id: userDoc.data(),
        };

        return StreamBuilder(
          stream: FirebaseFirestore.instance
              .collection('private_chats')
              .doc(chatId)
              .collection('messages')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (ctx, chatSnapshots) {
            if (chatSnapshots.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (!chatSnapshots.hasData || chatSnapshots.data!.docs.isEmpty) {
              return Center(child: Text('No messages found.'));
            }
            if (chatSnapshots.hasError) {
              return Center(child: Text('Something went wrong...'));
            }

            final loadedMessages = chatSnapshots.data!.docs;
            String? latestReadMessageId;
            for (final messageDoc in loadedMessages) {
              final messageData = messageDoc.data();
              final senderId = _readString(messageData, const ['userId']);
              final readBy = List<String>.from(
                messageData['readBy'] ?? const [],
              );
              final isLatestReadOutgoingMessage =
                  senderId == authenticatedUser.uid &&
                  readBy.contains(otherUserId);
              if (isLatestReadOutgoingMessage) {
                latestReadMessageId = messageDoc.id;
                break;
              }
            }

            final otherUserProfile = userProfiles[otherUserId];
            final readReceiptUserImage = _resolveUserImage(
              otherUserProfile,
              const {},
            );
            final readReceiptUsername =
                _resolveUsername(otherUserProfile, const {}) ?? 'User';

            return ListView.builder(
              padding: EdgeInsets.only(bottom: 40, left: 40, right: 40),
              reverse: true,
              itemCount: loadedMessages.length,
              itemBuilder: (ctx, index) {
                final chatMessage = loadedMessages[index].data();
                final nextChatMessage = index + 1 < loadedMessages.length
                    ? loadedMessages[index + 1].data()
                    : null;
                final currentMessageUserId = chatMessage['userId'];
                final nextMessageUserId = nextChatMessage != null
                    ? nextChatMessage['userId']
                    : null;
                final nextUserIsSame =
                    nextMessageUserId == currentMessageUserId;
                final profileData = userProfiles[currentMessageUserId];
                final username =
                    _resolveUsername(profileData, chatMessage) ?? 'User';
                final userImage = _resolveUserImage(profileData, chatMessage);
                final showReadReceipt =
                    authenticatedUser.uid == currentMessageUserId &&
                    loadedMessages[index].id == latestReadMessageId;

                if (nextUserIsSame) {
                  return MessageBubble.next(
                    message: chatMessage['text'],
                    isMe: authenticatedUser.uid == currentMessageUserId,
                    showReadReceipt: showReadReceipt,
                    readReceiptUserImage: readReceiptUserImage,
                    readReceiptUsername: readReceiptUsername,
                  );
                } else {
                  return MessageBubble.first(
                    userImage: userImage,
                    username: username,
                    message: chatMessage['text'],
                    isMe: authenticatedUser.uid == currentMessageUserId,
                    showReadReceipt: showReadReceipt,
                    readReceiptUserImage: readReceiptUserImage,
                    readReceiptUsername: readReceiptUsername,
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}
