import 'dart:io';

import 'package:chat_app/screens/change_password.dart';
import 'package:chat_app/screens/conversation.dart';
import 'package:chat_app/services/cloudinary_service.dart';
import 'package:chat_app/services/push_notification_service.dart';
import 'package:chat_app/services/remembered_accounts_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

enum _ChatMenuAction { changePassword, switchAccount, logout }

enum _ConversationListAction { archive, unarchive, clear }

class _MatchedMessageResult {
  const _MatchedMessageResult({
    required this.messageId,
    required this.text,
    required this.createdAt,
  });

  final String messageId;
  final String text;
  final Timestamp? createdAt;
}

class _ChatMessageSearchResult {
  const _ChatMessageSearchResult({
    required this.chatId,
    required this.otherUserId,
    required this.username,
    required this.userImage,
    required this.matches,
    required this.isArchived,
    required this.isHidden,
  });

  final String chatId;
  final String otherUserId;
  final String username;
  final String? userImage;
  final List<_MatchedMessageResult> matches;
  final bool isArchived;
  final bool isHidden;
}

class ChatScreen extends StatefulWidget {
  static const routeName = '/chat';

  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser!;
  final _chatSearchController = TextEditingController();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _friendRequestsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _privateChatsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _allMessagesStream;
  int _selectedTabIndex = 0;
  String _chatSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _friendRequestsStream = FirebaseFirestore.instance
        .collection('friend_requests')
        .where('participants', arrayContains: _currentUser.uid)
        .snapshots();
    _usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('username')
        .snapshots();
    _privateChatsStream = FirebaseFirestore.instance
        .collection('private_chats')
        .where('participants', arrayContains: _currentUser.uid)
        .snapshots();
    _allMessagesStream = FirebaseFirestore.instance
        .collectionGroup('messages')
        .snapshots();
  }

  @override
  void dispose() {
    _chatSearchController.dispose();
    super.dispose();
  }

  Future<void> _handleMenuAction(_ChatMenuAction action) async {
    switch (action) {
      case _ChatMenuAction.changePassword:
        if (!mounted) {
          return;
        }
        await Navigator.of(context).pushNamed(ChangePasswordScreen.routeName);
        break;
      case _ChatMenuAction.switchAccount:
        RememberedAccountsService.instance
            .showRememberedAccountsOnNextAuthScreen();
        await _showSwitchAccountSheet();
        break;
      case _ChatMenuAction.logout:
        RememberedAccountsService.instance.clearPendingSelection();
        RememberedAccountsService.instance
            .hideRememberedAccountsOnNextAuthScreen();
        await PushNotificationService.instance.signOutCurrentUser();
        break;
    }
  }

  Future<void> _showSwitchAccountSheet() async {
    final accounts = await RememberedAccountsService.instance.getAccounts();
    if (!mounted) {
      return;
    }

    final currentEmail = (_currentUser.email ?? '').trim().toLowerCase();
    final availableAccounts = accounts.where((account) {
      return account.email.trim().toLowerCase() != currentEmail;
    }).toList();

    if (availableAccounts.isEmpty) {
      RememberedAccountsService.instance.clearPendingSelection();
      await PushNotificationService.instance.signOutCurrentUser();
      return;
    }

    final selectedAccount = await showModalBottomSheet<RememberedAccount>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đổi tài khoản',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...availableAccounts.map((account) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      foregroundImage:
                          account.imageUrl != null &&
                              account.imageUrl!.isNotEmpty
                          ? NetworkImage(account.imageUrl!)
                          : null,
                      child:
                          account.imageUrl == null || account.imageUrl!.isEmpty
                          ? Text(account.username[0].toUpperCase())
                          : null,
                    ),
                    title: Text(account.username),
                    subtitle: Text(
                      account.hasSavedPassword
                          ? 'Sẽ đăng nhập ngay'
                          : 'Chỉ cần nhập lại mật khẩu',
                    ),
                    trailing: Icon(
                      account.hasSavedPassword
                          ? Icons.lock_open_rounded
                          : Icons.keyboard_alt_outlined,
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(account),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedAccount == null) {
      return;
    }

    await _switchToRememberedAccount(selectedAccount);
  }

  Future<void> _switchToRememberedAccount(RememberedAccount account) async {
    RememberedAccountsService.instance.setPendingSelection(account);

    final savedPassword = account.hasSavedPassword
        ? await RememberedAccountsService.instance.getSavedPassword(
            account.email,
          )
        : null;

    await PushNotificationService.instance.signOutCurrentUser();

    if (savedPassword == null || savedPassword.isEmpty) {
      return;
    }

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: account.email,
        password: savedPassword,
      );
      RememberedAccountsService.instance.clearPendingSelection();
    } on FirebaseAuthException {
      // Keep pending selection so the auth screen can prefill it.
    }
  }

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

  List<String> _readStringList(Map<String, dynamic>? data, String key) {
    final value = data?[key];
    if (value is! Iterable) {
      return const [];
    }

    return value.whereType<String>().toList();
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

  bool _isConversationArchivedForCurrentUser(Map<String, dynamic>? chatData) {
    return _readStringList(chatData, 'archivedFor').contains(_currentUser.uid);
  }

  bool _isConversationHiddenForCurrentUser(Map<String, dynamic>? chatData) {
    return _readStringList(chatData, 'hiddenFor').contains(_currentUser.uid);
  }

  bool _wasMessageClearedForCurrentUser(
    Map<String, dynamic> messageData,
    Timestamp? clearedAt,
  ) {
    if (clearedAt == null) {
      return false;
    }

    final createdAt = messageData['createdAt'];
    if (createdAt is! Timestamp) {
      return false;
    }

    return createdAt.millisecondsSinceEpoch <= clearedAt.millisecondsSinceEpoch;
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

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setConversationArchived({
    required String chatId,
    required bool archived,
  }) async {
    await FirebaseFirestore.instance
        .collection('private_chats')
        .doc(chatId)
        .set({
          'archivedFor': archived
              ? FieldValue.arrayUnion([_currentUser.uid])
              : FieldValue.arrayRemove([_currentUser.uid]),
        }, SetOptions(merge: true));

    _showSnackBar(
      archived ? 'Đã lưu trữ đoạn chat.' : 'Đã bỏ lưu trữ đoạn chat.',
    );
  }

  Future<void> _clearConversation(String chatId) async {
    await FirebaseFirestore.instance
        .collection('private_chats')
        .doc(chatId)
        .set({
          'clearedAtByUser': {_currentUser.uid: Timestamp.now()},
          'hiddenFor': FieldValue.arrayUnion([_currentUser.uid]),
        }, SetOptions(merge: true));

    _showSnackBar('Đã xóa trò chuyện ở phía bạn.');
  }

  Future<void> _showConversationActions({
    required String chatId,
    required String username,
    required bool isArchived,
  }) async {
    final action = await showModalBottomSheet<_ConversationListAction>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(
                  isArchived ? 'Bỏ lưu trữ đoạn chat' : 'Lưu trữ đoạn chat',
                ),
                onTap: () => Navigator.of(sheetContext).pop(
                  isArchived
                      ? _ConversationListAction.unarchive
                      : _ConversationListAction.archive,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Xóa trò chuyện'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_ConversationListAction.clear),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _ConversationListAction.archive:
        await _setConversationArchived(chatId: chatId, archived: true);
        break;
      case _ConversationListAction.unarchive:
        await _setConversationArchived(chatId: chatId, archived: false);
        break;
      case _ConversationListAction.clear:
        final shouldClear = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Xóa trò chuyện'),
              content: Text('Xóa toàn bộ tin nhắn với  ở phía bạn?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Xóa'),
                ),
              ],
            );
          },
        );

        if (shouldClear == true) {
          await _clearConversation(chatId);
        }
        break;
    }
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

    _showSnackBar('Yêu cầu kết bạn đã được gửi.');
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

  bool _matchesSearch(String? source, String query) {
    if (source == null) {
      return false;
    }

    return source.trim().toLowerCase().contains(query);
  }

  String? _extractOtherUserId(List<String> participants) {
    for (final userId in participants) {
      if (userId != _currentUser.uid) {
        return userId;
      }
    }

    return null;
  }

  List<_MatchedMessageResult> _matchedMessagesForChat({
    required String chatId,
    required Map<String, dynamic>? chatData,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allMessageDocs,
  }) {
    if (_chatSearchQuery.isEmpty) {
      return const [];
    }

    final clearedAt = _readConversationClearedAt(chatData, _currentUser.uid);
    final matches = <_MatchedMessageResult>[];

    for (final messageDoc in allMessageDocs) {
      final messageChatId = messageDoc.reference.parent.parent?.id;
      if (messageChatId != chatId) {
        continue;
      }

      final messageData = messageDoc.data();
      final deletedFor = List<String>.from(
        messageData['deletedFor'] ?? const [],
      );
      if (deletedFor.contains(_currentUser.uid) ||
          messageData['deletedForEveryone'] == true ||
          _wasMessageClearedForCurrentUser(messageData, clearedAt)) {
        continue;
      }

      final text = _readString(messageData, const ['text']);
      if (!_matchesSearch(text, _chatSearchQuery)) {
        continue;
      }

      matches.add(
        _MatchedMessageResult(
          messageId: messageDoc.id,
          text: text!,
          createdAt: messageData['createdAt'] as Timestamp?,
        ),
      );
    }

    matches.sort((a, b) {
      final aMillis = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bMillis = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bMillis.compareTo(aMillis);
    });

    return matches;
  }

  List<_ChatMessageSearchResult> _buildMessageSearchResults({
    required Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> userById,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> requestDocs,
    required Map<String, Map<String, dynamic>> privateChatById,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allMessageDocs,
  }) {
    if (_chatSearchQuery.isEmpty) {
      return const [];
    }

    final results = <_ChatMessageSearchResult>[];

    for (final requestDoc in requestDocs) {
      final requestData = requestDoc.data();
      if (requestData['status'] != 'accepted') {
        continue;
      }

      final participants = List<String>.from(requestData['participants'] ?? []);
      final otherUserId = _extractOtherUserId(participants);
      if (otherUserId == null) {
        continue;
      }

      final chatData = privateChatById[requestDoc.id];
      final matches = _matchedMessagesForChat(
        chatId: requestDoc.id,
        chatData: chatData,
        allMessageDocs: allMessageDocs,
      );
      if (matches.isEmpty) {
        continue;
      }

      final otherUserData = userById[otherUserId]?.data();
      final username = _readString(otherUserData, const ['username']) ?? 'User';
      final userImage = _readString(otherUserData, const [
        'image_url',
        'imageUrl',
        'userImage',
      ]);

      results.add(
        _ChatMessageSearchResult(
          chatId: requestDoc.id,
          otherUserId: otherUserId,
          username: username,
          userImage: userImage,
          matches: matches,
          isArchived: _isConversationArchivedForCurrentUser(chatData),
          isHidden: _isConversationHiddenForCurrentUser(chatData),
        ),
      );
    }

    results.sort(
      (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
    );
    return results;
  }

  String _formatMatchedMessageCount(int count) {
    return count == 1 ? '1 tin nhắn khớp' : '$count tin nhắn khớp';
  }

  String _formatMessageDate(Timestamp? timestamp) {
    if (timestamp == null) {
      return '';
    }

    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<File?> _pickProfileImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Chụp ảnh'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Chọn từ thư viện'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return null;
    }

    final pickedImage = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 800,
    );
    if (pickedImage == null) {
      return null;
    }

    return File(pickedImage.path);
  }

  Future<void> _showEditProfileSheet(Map<String, dynamic>? userData) async {
    final currentEmail = _currentUser.email ?? '';
    final currentUsername =
        _readString(userData, const ['username']) ??
        _currentUser.displayName?.trim() ??
        'User';
    final currentImageUrl =
        _readString(userData, const ['image_url', 'imageUrl', 'userImage']) ??
        _currentUser.photoURL;
    final nameController = TextEditingController(text: currentUsername);
    File? selectedImageFile;
    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> saveProfile() async {
              final trimmedName = nameController.text.trim();
              if (trimmedName.isEmpty || isSaving) {
                return;
              }

              setSheetState(() {
                isSaving = true;
              });

              try {
                String? imageUrl = currentImageUrl;
                if (selectedImageFile != null) {
                  imageUrl = await CloudinaryService.uploadImage(
                    selectedImageFile!,
                    publicId:
                        'profile_${_currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}',
                  );
                }

                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_currentUser.uid)
                    .set({
                      'username': trimmedName,
                      if (imageUrl != null) 'image_url': imageUrl,
                    }, SetOptions(merge: true));

                if (_currentUser.displayName != trimmedName) {
                  await _currentUser.updateDisplayName(trimmedName);
                }
                if (imageUrl != null && _currentUser.photoURL != imageUrl) {
                  await _currentUser.updatePhotoURL(imageUrl);
                }

                final rememberedAccount = currentEmail.isEmpty
                    ? null
                    : await RememberedAccountsService.instance.getAccount(
                        currentEmail,
                      );
                if (currentEmail.isNotEmpty && rememberedAccount != null) {
                  final savedPassword = rememberedAccount.hasSavedPassword
                      ? await RememberedAccountsService.instance
                            .getSavedPassword(currentEmail)
                      : null;
                  await RememberedAccountsService.instance.saveAccount(
                    email: currentEmail,
                    username: trimmedName,
                    imageUrl: imageUrl,
                    savePassword: rememberedAccount.hasSavedPassword,
                    password: savedPassword,
                  );
                }

                if (!mounted || !sheetContext.mounted) {
                  return;
                }

                Navigator.of(sheetContext).pop();
                _showSnackBar('Đã cập nhật thông tin cá nhân.');
              } catch (_) {
                if (!mounted || !sheetContext.mounted) {
                  return;
                }
                _showSnackBar('Không cập nhật được thông tin cá nhân.');
                setSheetState(() {
                  isSaving = false;
                });
              }
            }

            final avatar = selectedImageFile != null
                ? FileImage(selectedImageFile!)
                : (currentImageUrl != null
                          ? NetworkImage(currentImageUrl)
                          : null)
                      as ImageProvider<Object>?;

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thông tin cá nhân',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          foregroundImage: avatar,
                          child: avatar == null
                              ? Text(_trimmedFirstLetter(nameController.text))
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 16,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final file = await _pickProfileImage(
                                        sheetContext,
                                      );
                                      if (file == null) {
                                        return;
                                      }
                                      setSheetState(() {
                                        selectedImageFile = file;
                                      });
                                    },
                              icon: const Icon(Icons.edit, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(
                      labelText: 'Tên hiển thị',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSaving ? null : saveProfile,
                      child: Text(isSaving ? 'Đang lưu...' : 'Lưu thay đổi'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
  }

  String _trimmedFirstLetter(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed.substring(0, 1).toUpperCase();
  }

  Widget _buildProfileSection(Map<String, dynamic>? currentUserData) {
    final username =
        _readString(currentUserData, const ['username']) ??
        _currentUser.displayName?.trim() ??
        'User';
    final userImage =
        _readString(currentUserData, const [
          'image_url',
          'imageUrl',
          'userImage',
        ]) ??
        _currentUser.photoURL;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Thông tin cá nhân'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            onTap: () => _showEditProfileSheet(currentUserData),
            leading: CircleAvatar(
              radius: 26,
              foregroundImage: userImage != null
                  ? NetworkImage(userImage)
                  : null,
              child: userImage == null
                  ? Text(_trimmedFirstLetter(username))
                  : null,
            ),
            title: Text(
              username,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Nhấn để đổi avatar hoặc tên'),
            trailing: const Icon(Icons.edit_outlined),
          ),
        ),
      ],
    );
  }

  Future<void> _showMatchedMessagesSheet(
    _ChatMessageSearchResult result,
  ) async {
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.username,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatMatchedMessageCount(result.matches.length),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: result.matches.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final match = result.matches[index];
                      final dateLabel = _formatMessageDate(match.createdAt);

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          match.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: dateLabel.isEmpty ? null : Text(dateLabel),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _openConversation(
                            chatId: result.chatId,
                            otherUserId: result.otherUserId,
                            initialMessageId: match.messageId,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openConversation({
    required String chatId,
    required String otherUserId,
    String? initialMessageId,
  }) async {
    await FirebaseFirestore.instance
        .collection('private_chats')
        .doc(chatId)
        .set({
          'hiddenFor': FieldValue.arrayRemove([_currentUser.uid]),
        }, SetOptions(merge: true));

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushNamed(
      ConversationScreen.routeName,
      arguments: ConversationScreenArguments(
        chatId: chatId,
        otherUserId: otherUserId,
        initialMessageId: initialMessageId,
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
    Map<String, dynamic>? chatData,
    bool isArchived = false,
  }) {
    final clearedAt = _readConversationClearedAt(chatData, _currentUser.uid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('private_chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, dynamic>? latestMessageData;

        for (final doc in snapshot.data?.docs ?? const []) {
          final messageData = doc.data();
          final deletedFor = List<String>.from(
            messageData['deletedFor'] ?? const [],
          );
          if (!deletedFor.contains(_currentUser.uid) &&
              !_wasMessageClearedForCurrentUser(messageData, clearedAt)) {
            latestMessageData = messageData;
            break;
          }
        }

        final latestMessageText = _readString(latestMessageData, const [
          'text',
        ]);
        final latestMessageSenderId = _readString(latestMessageData, const [
          'userId',
        ]);
        final latestMessageReadBy = List<String>.from(
          latestMessageData?['readBy'] ?? const [],
        );
        final previewContent = latestMessageData?['deletedForEveryone'] == true
            ? 'Tin nhắn đã bị thu hồi'
            : latestMessageText;
        final isUnread =
            previewContent != null &&
            latestMessageSenderId != null &&
            latestMessageSenderId != _currentUser.uid &&
            !latestMessageReadBy.contains(_currentUser.uid);
        final previewText = previewContent == null
            ? 'Nhấn để trò chuyện'
            : latestMessageSenderId == _currentUser.uid
            ? 'Bạn: $previewContent'
            : previewContent;
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
            onLongPress: () => _showConversationActions(
              chatId: chatId,
              username: username,
              isArchived: isArchived,
            ),
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
        _buildSectionTitle(context, 'Lời mời kết bạn'),
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
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _rejectFriendRequest(requestDoc.id),
                    child: const Text('Xóa'),
                  ),
                  ElevatedButton(
                    onPressed: () => _acceptFriendRequest(requestDoc.id, data),
                    child: const Text('Xác nhận'),
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
    Map<String, Map<String, dynamic>> privateChatById,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allMessageDocs,
  ) {
    if (_chatSearchQuery.isNotEmpty) {
      final acceptedRequests = requestDocs.where((requestDoc) {
        return requestDoc.data()['status'] == 'accepted';
      }).toList();

      final matchedFriendRequests =
          acceptedRequests.where((requestDoc) {
            final participants = List<String>.from(
              requestDoc.data()['participants'] ?? [],
            );
            final otherUserId = _extractOtherUserId(participants);
            if (otherUserId == null) {
              return false;
            }

            final username = _readString(userById[otherUserId]?.data(), const [
              'username',
            ]);
            return _matchesSearch(username, _chatSearchQuery);
          }).toList()..sort((a, b) {
            final firstOtherUserId = _extractOtherUserId(
              List<String>.from(a.data()['participants'] ?? []),
            );
            final secondOtherUserId = _extractOtherUserId(
              List<String>.from(b.data()['participants'] ?? []),
            );
            final firstUsername =
                _readString(userById[firstOtherUserId]?.data(), const [
                  'username',
                ]) ??
                '';
            final secondUsername =
                _readString(userById[secondOtherUserId]?.data(), const [
                  'username',
                ]) ??
                '';
            return firstUsername.toLowerCase().compareTo(
              secondUsername.toLowerCase(),
            );
          });

      final messageSearchResults = _buildMessageSearchResults(
        userById: userById,
        requestDocs: requestDocs,
        privateChatById: privateChatById,
        allMessageDocs: allMessageDocs,
      );

      final acceptedFriendIds = <String>{};
      for (final requestDoc in acceptedRequests) {
        final otherUserId = _extractOtherUserId(
          List<String>.from(requestDoc.data()['participants'] ?? []),
        );
        if (otherUserId != null) {
          acceptedFriendIds.add(otherUserId);
        }
      }

      final otherUsers =
          userById.values.where((userDoc) {
            final userData = userDoc.data();
            final username = _readString(userData, const ['username']);
            return userDoc.id != _currentUser.uid &&
                !acceptedFriendIds.contains(userDoc.id) &&
                _matchesSearch(username, _chatSearchQuery);
          }).toList()..sort((a, b) {
            final firstUsername =
                _readString(a.data(), const ['username'])?.toLowerCase() ?? '';
            final secondUsername =
                _readString(b.data(), const ['username'])?.toLowerCase() ?? '';
            return firstUsername.compareTo(secondUsername);
          });

      final hasResults =
          matchedFriendRequests.isNotEmpty ||
          messageSearchResults.isNotEmpty ||
          otherUsers.isNotEmpty;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChatSearchField(),
          if (matchedFriendRequests.isNotEmpty) ...[
            _buildSectionTitle(context, 'Bạn bè'),
            ...matchedFriendRequests.map((requestDoc) {
              final data = requestDoc.data();
              final otherUserId = _extractOtherUserId(
                List<String>.from(data['participants'] ?? []),
              );
              if (otherUserId == null) {
                return const SizedBox.shrink();
              }

              final otherUser = userById[otherUserId]?.data();
              final username =
                  _readString(otherUser, const ['username']) ?? 'User';
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
                chatData: privateChatById[requestDoc.id],
                isArchived: _isConversationArchivedForCurrentUser(
                  privateChatById[requestDoc.id],
                ),
              );
            }),
          ],
          if (messageSearchResults.isNotEmpty) ...[
            _buildSectionTitle(context, 'Tin nhắn'),
            ...messageSearchResults.map((result) {
              final statusLabel = result.isHidden
                  ? 'Đã xóa khỏi đoạn chat'
                  : result.isArchived
                  ? 'Đang lưu trữ'
                  : null;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  onTap: () => _showMatchedMessagesSheet(result),
                  leading: CircleAvatar(
                    foregroundImage: result.userImage != null
                        ? NetworkImage(result.userImage!)
                        : null,
                    child: result.userImage == null
                        ? Text(result.username[0].toUpperCase())
                        : null,
                  ),
                  title: Text(result.username),
                  subtitle: Text(
                    statusLabel == null
                        ? _formatMatchedMessageCount(result.matches.length)
                        : '${_formatMatchedMessageCount(result.matches.length)} • $statusLabel',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              );
            }),
          ],
          if (otherUsers.isNotEmpty) ...[
            _buildSectionTitle(context, 'Người khác'),
            ...otherUsers.map((userDoc) {
              final userData = userDoc.data();
              final username =
                  _readString(userData, const ['username']) ?? 'User';
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
              String subtitle = '';

              if (isIncomingPending && existingRequest != null) {
                subtitle = 'Đã gửi lời mời kết bạn cho bạn';
                trailing = Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _rejectFriendRequest(existingRequest.id),
                      child: const Text('Xóa'),
                    ),
                    ElevatedButton(
                      onPressed: () => _acceptFriendRequest(
                        existingRequest.id,
                        requestData!,
                      ),
                      child: const Text('Xác nhận'),
                    ),
                  ],
                );
              } else if (isOutgoingPending) {
                subtitle = 'Đã gửi yêu cầu kết bạn';
                trailing = const Text('Đã gửi');
              } else {
                trailing = ElevatedButton(
                  onPressed: () => _sendFriendRequest(userDoc.id),
                  child: const Text('Thêm'),
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
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  trailing: trailing,
                ),
              );
            }),
          ],
          if (!hasResults)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text(
                'Không tìm thấy bạn bè, tin nhắn hoặc người dùng phù hợp.',
              ),
            ),
        ],
      );
    }

    final visibleRequests = requestDocs.where((requestDoc) {
      final data = requestDoc.data();
      return data['status'] == 'accepted' &&
          !_isConversationArchivedForCurrentUser(
            privateChatById[requestDoc.id],
          ) &&
          !_isConversationHiddenForCurrentUser(privateChatById[requestDoc.id]);
    }).toList();

    if (visibleRequests.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChatSearchField(),
          _buildSectionTitle(context, 'Bạn bè'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Chưa có đoạn chat nào đang hiển thị. Hãy thêm bạn bè hoặc bỏ lưu trữ để tiếp tục trò chuyện.',
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildChatSearchField(),
        _buildSectionTitle(context, 'Bạn bè'),
        ...visibleRequests.map((requestDoc) {
          final data = requestDoc.data();
          final participants = List<String>.from(data['participants'] ?? []);
          final otherUserId = _extractOtherUserId(participants);

          if (otherUserId == null) {
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
            chatData: privateChatById[requestDoc.id],
          );
        }),
      ],
    );
  }

  Widget _buildArchivedSection(
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> userById,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> requestDocs,
    Map<String, Map<String, dynamic>> privateChatById,
  ) {
    final archivedRequests = requestDocs.where((requestDoc) {
      final data = requestDoc.data();
      return data['status'] == 'accepted' &&
          _isConversationArchivedForCurrentUser(
            privateChatById[requestDoc.id],
          ) &&
          !_isConversationHiddenForCurrentUser(privateChatById[requestDoc.id]);
    }).toList();

    if (archivedRequests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Lưu trữ'),
        ...archivedRequests.map((requestDoc) {
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
            chatData: privateChatById[requestDoc.id],
            isArchived: true,
          );
        }),
      ],
    );
  }

  Widget _buildChatSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: TextField(
        controller: _chatSearchController,
        onChanged: (value) {
          setState(() {
            _chatSearchQuery = value.trim().toLowerCase();
          });
        },
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'Tìm tên hoặc tin nhắn',
          suffixIcon: _chatSearchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _chatSearchController.clear();
                    setState(() {
                      _chatSearchQuery = '';
                    });
                  },
                  icon: const Icon(Icons.close),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          filled: true,
        ),
      ),
    );
  }

  Widget _buildAddFriendsSection(
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> userById,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> requestDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    Map<String, Map<String, dynamic>> privateChatById,
  ) {
    final currentUserData = userById[_currentUser.uid]?.data();
    final acceptedFriendIds = <String>{};
    final incomingPendingIds = <String>{};

    for (final requestDoc in requestDocs) {
      final data = requestDoc.data();
      final participants = List<String>.from(data['participants'] ?? []);
      final status = data['status'] as String?;
      final receiverId = data['receiverId'] as String?;

      for (final userId in participants) {
        if (userId == _currentUser.uid) {
          continue;
        }

        if (status == 'accepted') {
          acceptedFriendIds.add(userId);
        } else if (status == 'pending' && receiverId == _currentUser.uid) {
          incomingPendingIds.add(userId);
        }
      }
    }

    final addableUsers = users.where((userDoc) {
      return userDoc.id != _currentUser.uid &&
          !acceptedFriendIds.contains(userDoc.id) &&
          !incomingPendingIds.contains(userDoc.id);
    }).toList();

    if (addableUsers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileSection(currentUserData),
          _buildArchivedSection(userById, requestDocs, privateChatById),
          _buildIncomingRequestsSection(userById, requestDocs),
          _buildSectionTitle(context, 'Thêm bạn bè'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Tất cả người dùng có sẵn đều đã nằm trong danh sách bạn bè hoặc lời mời của bạn.',
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileSection(currentUserData),
        _buildArchivedSection(userById, requestDocs, privateChatById),
        _buildIncomingRequestsSection(userById, requestDocs),
        _buildSectionTitle(context, 'Thêm bạn bè'),
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
                  child: const Text('Xóa'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      _acceptFriendRequest(existingRequest.id, requestData!),
                  child: const Text('Xác nhận'),
                ),
              ],
            );
          } else if (isOutgoingPending) {
            trailing = const Text('Đã gửi');
          } else {
            trailing = ElevatedButton(
              onPressed: () => _sendFriendRequest(userDoc.id),
              child: const Text('Thêm'),
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
              subtitle: Text(isOutgoingPending ? 'Đã gửi yêu cầu' : ''),
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
      stream: _friendRequestsStream,
      builder: (context, requestSnapshot) {
        if (requestSnapshot.connectionState == ConnectionState.waiting &&
            !requestSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (requestSnapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Không thể tải yêu cầu.')),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _usersStream,
          builder: (context, usersSnapshot) {
            if (usersSnapshot.connectionState == ConnectionState.waiting &&
                !usersSnapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (usersSnapshot.hasError) {
              return const Scaffold(
                body: Center(child: Text('Không thể tải người dùng.')),
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _privateChatsStream,
              builder: (context, privateChatsSnapshot) {
                if (privateChatsSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    !privateChatsSnapshot.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final requestDocs = requestSnapshot.data?.docs ?? [];
                final users = usersSnapshot.data?.docs ?? [];
                final userById = {
                  for (final userDoc in users) userDoc.id: userDoc,
                };
                final privateChatById = <String, Map<String, dynamic>>{
                  for (final privateChatDoc
                      in privateChatsSnapshot.data?.docs ?? [])
                    privateChatDoc.id: privateChatDoc.data(),
                };

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _allMessagesStream,
                  builder: (context, messagesSnapshot) {
                    final allMessageDocs =
                        messagesSnapshot.data?.docs ?? const [];

                    return Scaffold(
                      appBar: AppBar(
                        title: const Text('Datdz'),
                        actions: _selectedTabIndex == 1
                            ? [
                                PopupMenuButton<_ChatMenuAction>(
                                  tooltip: 'Tùy chọn',
                                  onSelected: _handleMenuAction,
                                  icon: Icon(
                                    Icons.menu_rounded,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: _ChatMenuAction.changePassword,
                                      child: Text('Đổi mật khẩu'),
                                    ),
                                    PopupMenuItem(
                                      value: _ChatMenuAction.switchAccount,
                                      child: Text('Đổi tài khoản'),
                                    ),
                                    PopupMenuItem(
                                      value: _ChatMenuAction.logout,
                                      child: Text('Thoát'),
                                    ),
                                  ],
                                ),
                              ]
                            : null,
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
                            label: 'Đoạn chat',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.person_add_alt_1_outlined),
                            selectedIcon: Icon(Icons.person_add_alt_1),
                            label: 'Thêm bạn bè',
                          ),
                        ],
                      ),
                      body: ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: _selectedTabIndex == 0
                            ? [
                                _buildFriendsSection(
                                  userById,
                                  requestDocs,
                                  privateChatById,
                                  allMessageDocs,
                                ),
                              ]
                            : [
                                _buildAddFriendsSection(
                                  userById,
                                  requestDocs,
                                  users,
                                  privateChatById,
                                ),
                              ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
