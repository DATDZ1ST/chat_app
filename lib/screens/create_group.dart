import 'package:chat_app/screens/group_conversation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _groupNameController = TextEditingController();
  final _selectedUserIds = <String>{};
  bool _isCreating = false;

  @override
  void dispose() {
    _groupNameController.dispose();
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

  String? _extractOtherUserId(List<String> participants, String currentUserId) {
    for (final userId in participants) {
      if (userId != currentUserId) {
        return userId;
      }
    }

    return null;
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createGroup(
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> userById,
  ) async {
    if (_isCreating) {
      return;
    }

    if (_selectedUserIds.isEmpty) {
      _showSnackBar('Chọn ít nhất một bạn bè để tạo nhóm.');
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser!;
    final participants = {..._selectedUserIds, currentUser.uid}.toList()
      ..sort();
    final typedName = _groupNameController.text.trim();
    final fallbackName = _selectedUserIds
        .map((userId) {
          return _readString(userById[userId]?.data(), const ['username']) ??
              'User';
        })
        .take(3)
        .join(', ');
    final groupName = typedName.isEmpty
        ? (fallbackName.isEmpty ? 'Nhóm mới' : fallbackName)
        : typedName;

    setState(() {
      _isCreating = true;
    });

    try {
      final groupDoc = FirebaseFirestore.instance
          .collection('private_chats')
          .doc();
      await groupDoc.set({
        'type': 'group',
        'isGroup': true,
        'name': groupName,
        'participants': participants,
        'createdBy': currentUser.uid,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'lastMessage': 'Nhóm đã được tạo',
        'lastMessageSenderId': currentUser.uid,
        'archivedFor': <String>[],
        'hiddenFor': <String>[],
      });

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GroupConversationScreen(chatId: groupDoc.id),
        ),
      );
    } catch (error) {
      _showSnackBar('Không tạo được nhóm: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('friend_requests')
          .where('participants', arrayContains: currentUser.uid)
          .snapshots(),
      builder: (context, requestSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .orderBy('username')
              .snapshots(),
          builder: (context, userSnapshot) {
            if ((!requestSnapshot.hasData &&
                    requestSnapshot.connectionState ==
                        ConnectionState.waiting) ||
                (!userSnapshot.hasData &&
                    userSnapshot.connectionState == ConnectionState.waiting)) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (requestSnapshot.hasError || userSnapshot.hasError) {
              return const Scaffold(
                body: Center(child: Text('Không thể tải danh sách bạn bè.')),
              );
            }

            final userById =
                <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
                  for (final userDoc in userSnapshot.data?.docs ?? [])
                    userDoc.id: userDoc,
                };
            final friendIds = <String>{};

            for (final requestDoc in requestSnapshot.data?.docs ?? []) {
              final data = requestDoc.data();
              if (data['status'] != 'accepted') {
                continue;
              }

              final otherUserId = _extractOtherUserId(
                List<String>.from(data['participants'] ?? const []),
                currentUser.uid,
              );
              if (otherUserId != null) {
                friendIds.add(otherUserId);
              }
            }

            final friends =
                friendIds
                    .map((userId) => userById[userId])
                    .whereType<QueryDocumentSnapshot<Map<String, dynamic>>>()
                    .toList()
                  ..sort((a, b) {
                    final firstName =
                        _readString(a.data(), const [
                          'username',
                        ])?.toLowerCase() ??
                        '';
                    final secondName =
                        _readString(b.data(), const [
                          'username',
                        ])?.toLowerCase() ??
                        '';
                    return firstName.compareTo(secondName);
                  });

            return Scaffold(
              appBar: AppBar(
                title: const Text('Tạo nhóm'),
                actions: [
                  TextButton(
                    onPressed: _isCreating
                        ? null
                        : () => _createGroup(userById),
                    child: _isCreating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Tạo'),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  TextField(
                    controller: _groupNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Tên nhóm',
                      hintText: 'Có thể để trống',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Thành viên',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Bạn cần có bạn bè để tạo nhóm.'),
                    )
                  else
                    ...friends.map((userDoc) {
                      final userData = userDoc.data();
                      final username =
                          _readString(userData, const ['username']) ?? 'User';
                      final userImage = _readString(userData, const [
                        'image_url',
                        'imageUrl',
                        'userImage',
                      ]);
                      final isSelected = _selectedUserIds.contains(userDoc.id);

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedUserIds.add(userDoc.id);
                            } else {
                              _selectedUserIds.remove(userDoc.id);
                            }
                          });
                        },
                        secondary: CircleAvatar(
                          foregroundImage: userImage != null
                              ? NetworkImage(userImage)
                              : null,
                          child: userImage == null
                              ? Text(username[0].toUpperCase())
                              : null,
                        ),
                        title: Text(username),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
