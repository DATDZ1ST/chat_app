import 'package:chat_app/screens/conversation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  static const routeName = '/chat';

  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser!;
  int _selectedTabIndex = 0;

  String _buildDirectChatId(String firstUserId, String secondUserId) {
    final ids = [firstUserId, secondUserId]..sort();
    return ids.join('_');
  }

  List<String> _buildParticipants(String firstUserId, String secondUserId) {
    final ids = [firstUserId, secondUserId]..sort();
    return ids;
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

  QueryDocumentSnapshot<Map<String, dynamic>>? _findRequestDoc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> requestDocs,
    String chatId,
  ) {
    for (final requestDoc in requestDocs) {
      if (requestDoc.id == chatId) {
        return requestDoc;
      }
    }

    return null;
  }

  Future<void> _sendFriendRequest(String otherUserId) async {
    final requestId = _buildDirectChatId(_currentUser.uid, otherUserId);

    await FirebaseFirestore.instance
        .collection('friend_requests')
        .doc(requestId)
        .set({
          'participants': _buildParticipants(_currentUser.uid, otherUserId),
          'senderId': _currentUser.uid,
          'receiverId': otherUserId,
          'status': 'pending',
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        }, SetOptions(merge: true));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Friend request sent.')));
  }

  Future<void> _acceptFriendRequest(
    String requestId,
    Map<String, dynamic> requestData,
  ) async {
    final participants = List<String>.from(
      requestData['participants'] ?? [_currentUser.uid],
    );

    await FirebaseFirestore.instance
        .collection('friend_requests')
        .doc(requestId)
        .update({'status': 'accepted', 'updatedAt': Timestamp.now()});

    await FirebaseFirestore.instance
        .collection('private_chats')
        .doc(requestId)
        .set({
          'participants': participants,
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        }, SetOptions(merge: true));
  }

  Future<void> _rejectFriendRequest(String requestId) async {
    await FirebaseFirestore.instance
        .collection('friend_requests')
        .doc(requestId)
        .delete();
  }

  void _openConversation({
    required String chatId,
    required String otherUserId,
  }) {
    Navigator.of(context).pushNamed(
      ConversationScreen.routeName,
      arguments: ConversationScreenArguments(
        chatId: chatId,
        otherUserId: otherUserId,
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildFriendTile({
    required String chatId,
    required String otherUserId,
    required String username,
    required String? userImage,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('private_chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        final latestMessageData = snapshot.data?.docs.isNotEmpty == true
            ? snapshot.data!.docs.first.data()
            : null;
        final latestMessageText = _readString(latestMessageData, const [
          'text',
        ]);
        final latestMessageSenderId = _readString(latestMessageData, const [
          'userId',
        ]);
        final latestMessageReadBy = List<String>.from(
          latestMessageData?['readBy'] ?? const [],
        );
        final isUnread =
            latestMessageText != null &&
            latestMessageSenderId != null &&
            latestMessageSenderId != _currentUser.uid &&
            !latestMessageReadBy.contains(_currentUser.uid);
        final previewText = latestMessageText == null
            ? 'Tap avatar or name to chat'
            : latestMessageSenderId == _currentUser.uid
            ? 'B\u1ea1n: $latestMessageText'
            : latestMessageText;
        final titleStyle = isUnread
            ? Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
            : null;
        final subtitleStyle = isUnread
            ? Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
            : null;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            onTap: () =>
                _openConversation(chatId: chatId, otherUserId: otherUserId),
            leading: CircleAvatar(
              foregroundImage: userImage != null
                  ? NetworkImage(userImage)
                  : null,
              child: userImage == null ? Text(username[0].toUpperCase()) : null,
            ),
            title: Text(username, style: titleStyle),
            subtitle: Text(
              previewText,
              style: subtitleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chat_bubble_outline),
          ),
        );
      },
    );
  }

  Widget _buildIncomingRequestsSection(
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> userById,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> requestDocs,
  ) {
    final incomingRequests = requestDocs.where((requestDoc) {
      final data = requestDoc.data();
      return data['status'] == 'pending' &&
          data['receiverId'] == _currentUser.uid;
    }).toList();

    if (incomingRequests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Friend Requests'),
        ...incomingRequests.map((requestDoc) {
          final data = requestDoc.data();
          final senderId = data['senderId'] as String?;
          final senderUser = senderId != null
              ? userById[senderId]?.data()
              : null;
          final username =
              _readString(senderUser, const ['username']) ?? 'User';
          final userImage = _readString(senderUser, const [
            'image_url',
            'imageUrl',
            'userImage',
          ]);

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                foregroundImage: userImage != null
                    ? NetworkImage(userImage)
                    : null,
                child: userImage == null
                    ? Text(username[0].toUpperCase())
                    : null,
              ),
              title: Text(username),
              subtitle: const Text('sent you a friend request'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _rejectFriendRequest(requestDoc.id),
                    child: const Text('Decline'),
                  ),
                  ElevatedButton(
                    onPressed: () => _acceptFriendRequest(requestDoc.id, data),
                    child: const Text('Accept'),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFriendsSection(
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> userById,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> requestDocs,
  ) {
    final acceptedRequests = requestDocs.where((requestDoc) {
      final data = requestDoc.data();
      return data['status'] == 'accepted';
    }).toList();

    if (acceptedRequests.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(context, 'Friends'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No friends yet. Add some friends to start chatting.'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Friends'),
        ...acceptedRequests.map((requestDoc) {
          final data = requestDoc.data();
          final participants = List<String>.from(data['participants'] ?? []);
          String otherUserId = '';

          for (final userId in participants) {
            if (userId != _currentUser.uid) {
              otherUserId = userId;
              break;
            }
          }

          if (otherUserId.isEmpty) {
            return const SizedBox.shrink();
          }

          final otherUser = userById[otherUserId]?.data();
          final username = _readString(otherUser, const ['username']) ?? 'User';
          final userImage = _readString(otherUser, const [
            'image_url',
            'imageUrl',
            'userImage',
          ]);

          return _buildFriendTile(
            chatId: requestDoc.id,
            otherUserId: otherUserId,
            username: username,
            userImage: userImage,
          );
        }),
      ],
    );
  }

  Widget _buildAddFriendsSection(
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> userById,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> requestDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  ) {
    final acceptedFriendIds = <String>{};
    for (final requestDoc in requestDocs) {
      final data = requestDoc.data();
      if (data['status'] != 'accepted') {
        continue;
      }

      final participants = List<String>.from(data['participants'] ?? []);
      for (final userId in participants) {
        if (userId != _currentUser.uid) {
          acceptedFriendIds.add(userId);
        }
      }
    }

    final addableUsers = users.where((userDoc) {
      return userDoc.id != _currentUser.uid &&
          !acceptedFriendIds.contains(userDoc.id);
    }).toList();

    if (addableUsers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIncomingRequestsSection(userById, requestDocs),
          _buildSectionTitle(context, 'Add Friends'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'All available users are already in your friends list.',
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIncomingRequestsSection(userById, requestDocs),
        _buildSectionTitle(context, 'Add Friends'),
        ...addableUsers.map((userDoc) {
          final userData = userDoc.data();
          final username = _readString(userData, const ['username']) ?? 'User';
          final userImage = _readString(userData, const [
            'image_url',
            'imageUrl',
            'userImage',
          ]);
          final chatId = _buildDirectChatId(_currentUser.uid, userDoc.id);
          final existingRequest = _findRequestDoc(requestDocs, chatId);
          final requestData = existingRequest?.data();
          final status = requestData?['status'] as String?;
          final receiverId = requestData?['receiverId'] as String?;
          final isIncomingPending =
              status == 'pending' && receiverId == _currentUser.uid;
          final isOutgoingPending =
              status == 'pending' && receiverId != _currentUser.uid;

          Widget trailing;
          if (isIncomingPending && existingRequest != null) {
            trailing = Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _rejectFriendRequest(existingRequest.id),
                  child: const Text('Decline'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      _acceptFriendRequest(existingRequest.id, requestData!),
                  child: const Text('Accept'),
                ),
              ],
            );
          } else if (isOutgoingPending) {
            trailing = const Text('Pending');
          } else {
            trailing = ElevatedButton(
              onPressed: () => _sendFriendRequest(userDoc.id),
              child: const Text('Add'),
            );
          }

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                foregroundImage: userImage != null
                    ? NetworkImage(userImage)
                    : null,
                child: userImage == null
                    ? Text(username[0].toUpperCase())
                    : null,
              ),
              title: Text(username),
              subtitle: Text(
                isOutgoingPending
                    ? 'Request sent'
                    : isIncomingPending
                    ? 'Waiting for your response'
                    : 'Send friend request first',
              ),
              trailing: trailing,
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('friend_requests')
          .where('participants', arrayContains: _currentUser.uid)
          .snapshots(),
      builder: (context, requestSnapshot) {
        if (requestSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (requestSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Unable to load requests.')),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .orderBy('username')
              .snapshots(),
          builder: (context, usersSnapshot) {
            if (usersSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (usersSnapshot.hasError) {
              return const Scaffold(
                body: Center(child: Text('Unable to load users.')),
              );
            }

            final requestDocs = requestSnapshot.data?.docs ?? [];
            final users = usersSnapshot.data?.docs ?? [];
            final userById = {for (final userDoc in users) userDoc.id: userDoc};

            return Scaffold(
              appBar: AppBar(
                title: const Text('FlutterChat'),
                actions: [
                  IconButton(
                    onPressed: () {
                      FirebaseAuth.instance.signOut();
                    },
                    icon: Icon(
                      Icons.exit_to_app,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _selectedTabIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    _selectedTabIndex = index;
                  });
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: 'Friends',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_add_alt_1_outlined),
                    selectedIcon: Icon(Icons.person_add_alt_1),
                    label: 'Add Friends',
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: _selectedTabIndex == 0
                    ? [_buildFriendsSection(userById, requestDocs)]
                    : [_buildAddFriendsSection(userById, requestDocs, users)],
              ),
            );
          },
        );
      },
    );
  }
}
