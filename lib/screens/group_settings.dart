import 'dart:io';

import 'package:chat_app/services/cloudinary_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  static const String _defaultQuickReaction = '👍';
  static const List<String> _quickReactionOptions = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '😡',
    '👌',
    '🔥',
    '👏',
    '🙏',
  ];
  static const List<Color> _themeColorOptions = [
    Color(0xFFF8F1E7),
    Color(0xFFEAF4FF),
    Color(0xFFEFF8EE),
    Color(0xFFFFEDF2),
    Color(0xFFF0EEFF),
    Color(0xFF1E293B),
  ];

  final _imagePicker = ImagePicker();
  bool _isDissolvingGroup = false;
  bool _isLeavingGroup = false;

  DocumentReference<Map<String, dynamic>> get _chatDocument =>
      FirebaseFirestore.instance.collection('private_chats').doc(widget.chatId);

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

  String _groupName(Map<String, dynamic>? chatData) {
    return _readString(chatData, const ['name', 'groupName']) ?? 'Nhóm chat';
  }

  String? _groupImageUrl(Map<String, dynamic>? chatData) {
    return _readString(chatData, const [
      'imageUrl',
      'image_url',
      'groupImage',
      'groupImageUrl',
    ]);
  }

  String? _groupNicknameFor(Map<String, dynamic>? chatData, String userId) {
    final rawMap = chatData?['groupNicknames'];
    if (rawMap is! Map) {
      return null;
    }

    final nickname = rawMap[userId];
    if (nickname is String && nickname.trim().isNotEmpty) {
      return nickname.trim();
    }

    return null;
  }

  String _quickReactionFor(Map<String, dynamic>? chatData) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return _defaultQuickReaction;
    }

    final rawMap = chatData?['quickReactions'];
    if (rawMap is! Map) {
      return _defaultQuickReaction;
    }

    final reaction = rawMap[currentUserId];
    if (reaction is String && reaction.trim().isNotEmpty) {
      return reaction.trim();
    }

    return _defaultQuickReaction;
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

  String _themeSubtitle(Map<String, dynamic>? chatData) {
    if (_readThemeImageUrl(chatData) != null) {
      return 'Đang dùng ảnh nền';
    }
    if (_readThemeColor(chatData) != null) {
      return 'Đang dùng màu nền';
    }
    return 'Mặc định';
  }

  bool _isGroupCreator(Map<String, dynamic>? chatData, String? userId) {
    if (userId == null) {
      return false;
    }

    return _readString(chatData, const ['createdBy']) == userId;
  }

  bool _isGroupDissolved(Map<String, dynamic>? chatData) {
    return chatData?['isDissolved'] == true ||
        chatData?['status'] == 'dissolved';
  }

  int _colorChannel(Color color, int shift) {
    return (color.toARGB32() >> shift) & 0xff;
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

  Future<void> _changeGroupAvatar() async {
    final pickedImage = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (pickedImage == null) {
      return;
    }

    try {
      _showSnackBar('Đang tải ảnh nhóm...');
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;
      final imageUrl = await CloudinaryService.uploadImage(
        File(pickedImage.path),
        publicId:
            '${widget.chatId}_${currentUserId}_${DateTime.now().millisecondsSinceEpoch}',
        folder: 'group_images',
      );
      await _chatDocument.set({
        'imageUrl': imageUrl,
        'updatedAt': Timestamp.now(),
        'settingsUpdatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      _showSnackBar('Đã đổi ảnh nhóm.');
    } catch (error) {
      _showSnackBar('Không đổi được ảnh nhóm: $error');
    }
  }

  Future<void> _saveMemberNickname({
    required String userId,
    required String nickname,
  }) async {
    final chatSnapshot = await _chatDocument.get();
    final groupNicknames = Map<String, dynamic>.from(
      chatSnapshot.data()?['groupNicknames'] ?? const {},
    );
    final trimmedNickname = nickname.trim();

    if (trimmedNickname.isEmpty) {
      groupNicknames.remove(userId);
    } else {
      groupNicknames[userId] = trimmedNickname;
    }

    await _chatDocument.set({
      'groupNicknames': groupNicknames,
      'settingsUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> _openMemberNicknameEditor({
    required String userId,
    required String username,
    required String? currentNickname,
  }) async {
    final result = await Navigator.of(context).push<_NicknameEditResult>(
      MaterialPageRoute(
        builder: (context) => _NicknameEditScreen(
          title: username,
          currentNickname: currentNickname,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      await _saveMemberNickname(userId: userId, nickname: result.nickname);
      _showSnackBar(
        result.nickname.trim().isEmpty
            ? 'Đã xóa biệt danh.'
            : 'Đã lưu biệt danh.',
      );
    } catch (error) {
      _showSnackBar('Không lưu được biệt danh: $error');
    }
  }

  Future<void> _saveQuickReaction(String reaction) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || reaction.trim().isEmpty) {
      return;
    }

    await _chatDocument.set({
      'quickReactions': {currentUserId: reaction.trim()},
      'settingsUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> _showQuickReactionSheet({
    required String currentReaction,
  }) async {
    final customReactionController = TextEditingController(
      text: currentReaction,
    );

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        Future<void> saveReaction(String reaction) async {
          final trimmedReaction = reaction.trim();
          if (trimmedReaction.isEmpty) {
            return;
          }

          Navigator.of(sheetContext).pop();
          try {
            await _saveQuickReaction(trimmedReaction);
            _showSnackBar('Đã đổi cảm xúc nhanh.');
          } catch (error) {
            _showSnackBar('Không đổi được cảm xúc nhanh: $error');
          }
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              24 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cảm xúc nhanh',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _quickReactionOptions.map((emoji) {
                    final isSelected = emoji == currentReaction;
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => saveReaction(emoji),
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(sheetContext).colorScheme.primary
                              : Theme.of(
                                  sheetContext,
                                ).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: customReactionController,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'Tùy chỉnh',
                    hintText: 'Nhập emoji hoặc ký hiệu',
                    border: OutlineInputBorder(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () =>
                        saveReaction(customReactionController.text),
                    child: const Text('Lưu'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    customReactionController.dispose();
  }

  Future<void> _saveThemeColor(Color color) async {
    await _chatDocument.set({
      'theme': {
        'type': 'color',
        'backgroundColor': color.toARGB32(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      },
      'settingsUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> _saveThemeImage(File imageFile) async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final imageUrl = await CloudinaryService.uploadImage(
      imageFile,
      publicId:
          '${widget.chatId}_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}',
      folder: 'chat_themes',
    );

    await _chatDocument.set({
      'theme': {
        'type': 'image',
        'imageUrl': imageUrl,
        'updatedBy': currentUser.uid,
      },
      'settingsUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> _resetConversationTheme() async {
    await _chatDocument.set({
      'theme': {
        'type': 'default',
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      },
      'settingsUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> _pickAndSaveThemeImage() async {
    final pickedImage = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (pickedImage == null) {
      return;
    }

    try {
      _showSnackBar('Đang tải ảnh nền...');
      await _saveThemeImage(File(pickedImage.path));
      _showSnackBar('Đã đổi ảnh nền nhóm.');
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _showThemeSheet({
    required Map<String, dynamic>? chatData,
  }) async {
    final currentColor = _readThemeColor(chatData) ?? const Color(0xFFF0EEFF);
    var red = _colorChannel(currentColor, 16);
    var green = _colorChannel(currentColor, 8);
    var blue = _colorChannel(currentColor, 0);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        Future<void> saveColor(Color color) async {
          Navigator.of(sheetContext).pop();
          try {
            await _saveThemeColor(color);
            _showSnackBar('Đã đổi màu nền nhóm.');
          } catch (error) {
            _showSnackBar('Không đổi được màu nền: $error');
          }
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final customColor = Color.fromARGB(255, red, green, blue);

            Widget buildColorSlider({
              required String label,
              required int value,
              required ValueChanged<int> onChanged,
            }) {
              return Row(
                children: [
                  SizedBox(width: 46, child: Text(label)),
                  Expanded(
                    child: Slider(
                      value: value.toDouble(),
                      min: 0,
                      max: 255,
                      divisions: 255,
                      label: value.toString(),
                      onChanged: (nextValue) {
                        setSheetState(() {
                          onChanged(nextValue.round());
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(value.toString(), textAlign: TextAlign.right),
                  ),
                ],
              );
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  24 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chủ đề',
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('Chọn ảnh từ thư viện'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _pickAndSaveThemeImage();
                      },
                    ),
                    const Divider(),
                    Text(
                      'Màu gợi ý',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _themeColorOptions.map((color) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => saveColor(color),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.black12),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Màu tùy chỉnh',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 62,
                      decoration: BoxDecoration(
                        color: customColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    buildColorSlider(
                      label: 'R',
                      value: red,
                      onChanged: (value) => red = value,
                    ),
                    buildColorSlider(
                      label: 'G',
                      value: green,
                      onChanged: (value) => green = value,
                    ),
                    buildColorSlider(
                      label: 'B',
                      value: blue,
                      onChanged: (value) => blue = value,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () async {
                            Navigator.of(sheetContext).pop();
                            try {
                              await _resetConversationTheme();
                              _showSnackBar('Đã đưa chủ đề về mặc định.');
                            } catch (error) {
                              _showSnackBar(
                                'Không đặt lại được chủ đề: $error',
                              );
                            }
                          },
                          child: const Text('Mặc định'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => saveColor(customColor),
                          child: const Text('Lưu màu'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAddMembers({required List<String> participantIds}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _AddGroupMembersScreen(
          chatId: widget.chatId,
          currentParticipantIds: participantIds,
        ),
      ),
    );
  }

  Future<void> _confirmAndDissolveGroup({
    required Map<String, dynamic>? chatData,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (!_isGroupCreator(chatData, currentUser?.uid)) {
      _showSnackBar('Chỉ chủ nhóm mới có thể giải tán nhóm.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Giải tán nhóm?'),
          content: const Text(
            'Nhóm sẽ biến mất khỏi danh sách chat của tất cả thành viên và không thể gửi tin nhắn mới.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Giải tán'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || currentUser == null || !mounted) {
      return;
    }

    setState(() {
      _isDissolvingGroup = true;
    });

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final chatSnapshot = await transaction.get(_chatDocument);
        final latestData = chatSnapshot.data();

        if (!chatSnapshot.exists || latestData == null) {
          throw Exception('Nhóm không còn tồn tại.');
        }

        if (!_isGroupCreator(latestData, currentUser.uid)) {
          throw Exception('Chỉ chủ nhóm mới có thể giải tán nhóm.');
        }

        if (_isGroupDissolved(latestData)) {
          return;
        }

        final currentParticipants = _readStringList(latestData, 'participants');
        final now = Timestamp.now();

        transaction.update(_chatDocument, {
          'participants': <String>[],
          'dissolvedParticipantIds': currentParticipants,
          'isDissolved': true,
          'status': 'dissolved',
          'dissolvedAt': now,
          'dissolvedBy': currentUser.uid,
          'lastMessage': 'Nhóm đã được giải tán',
          'lastMessageSenderId': currentUser.uid,
          'updatedAt': now,
          'settingsUpdatedAt': now,
        });
      });

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(content: Text('Đã giải tán nhóm.')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      _showSnackBar('Không giải tán được nhóm: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isDissolvingGroup = false;
        });
      }
    }
  }

  Future<void> _confirmAndLeaveGroup({
    required Map<String, dynamic>? chatData,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnackBar('Bạn cần đăng nhập để rời nhóm.');
      return;
    }

    if (_isGroupCreator(chatData, currentUser.uid)) {
      _showSnackBar('Chủ nhóm chỉ có thể giải tán nhóm.');
      return;
    }

    final participants = _readStringList(chatData, 'participants');
    if (!participants.contains(currentUser.uid)) {
      _showSnackBar('Bạn không còn là thành viên nhóm.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rời nhóm?'),
          content: const Text(
            'Bạn sẽ không còn nhận tin nhắn mới và nhóm sẽ biến mất khỏi danh sách chat của bạn.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Rời nhóm'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isLeavingGroup = true;
    });

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final chatSnapshot = await transaction.get(_chatDocument);
        final latestData = chatSnapshot.data();

        if (!chatSnapshot.exists || latestData == null) {
          throw Exception('Nhóm không còn tồn tại.');
        }

        if (_isGroupCreator(latestData, currentUser.uid)) {
          throw Exception('Chủ nhóm chỉ có thể giải tán nhóm.');
        }

        if (_isGroupDissolved(latestData)) {
          return;
        }

        final latestParticipants = _readStringList(latestData, 'participants');
        if (!latestParticipants.contains(currentUser.uid)) {
          return;
        }

        final now = Timestamp.now();
        final leftAtByUser = Map<String, dynamic>.from(
          latestData['leftAtByUser'] is Map
              ? latestData['leftAtByUser'] as Map
              : const {},
        );
        leftAtByUser[currentUser.uid] = now;

        transaction.update(_chatDocument, {
          'participants': FieldValue.arrayRemove([currentUser.uid]),
          'leftParticipantIds': FieldValue.arrayUnion([currentUser.uid]),
          'leftAtByUser': leftAtByUser,
          'lastMessage': 'Một thành viên đã rời nhóm',
          'lastMessageSenderId': currentUser.uid,
          'updatedAt': now,
          'settingsUpdatedAt': now,
        });
      });

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(const SnackBar(content: Text('Đã rời nhóm.')));
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      _showSnackBar('Không rời nhóm được: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLeavingGroup = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatDocument.snapshots(),
      builder: (context, chatSnapshot) {
        final chatData = chatSnapshot.data?.data();
        final groupName = _groupName(chatData);
        final groupImageUrl = _groupImageUrl(chatData);
        final participants = _readStringList(chatData, 'participants');
        final quickReaction = _quickReactionFor(chatData);
        final isDissolved = _isGroupDissolved(chatData);
        final isCreator = _isGroupCreator(chatData, currentUserId);
        final isCurrentMember =
            currentUserId != null && participants.contains(currentUserId);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, userSnapshot) {
            final userById = {
              for (final userDoc in userSnapshot.data?.docs ?? [])
                userDoc.id: userDoc.data(),
            };

            return Scaffold(
              appBar: AppBar(title: const Text('Thông tin nhóm')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _changeGroupAvatar,
                      child: CircleAvatar(
                        radius: 54,
                        foregroundImage: groupImageUrl != null
                            ? NetworkImage(groupImageUrl)
                            : null,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        child: groupImageUrl == null
                            ? const Icon(Icons.groups_rounded, size: 40)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    groupName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDissolved
                        ? 'Đã giải tán'
                        : '${participants.length} thành viên',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 28),
                  if (isDissolved)
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Nhóm đã được giải tán'),
                      subtitle: Text('Không thể thay đổi hoặc nhắn tin tiếp.'),
                    )
                  else ...[
                    ListTile(
                      leading: const Icon(Icons.photo_camera_outlined),
                      title: const Text('Đổi ảnh nhóm'),
                      subtitle: const Text('Chọn ảnh từ thư viện'),
                      onTap: _changeGroupAvatar,
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_1_outlined),
                      title: const Text('Thêm thành viên'),
                      subtitle: const Text('Chọn bạn bè đã kết bạn'),
                      onTap: () =>
                          _openAddMembers(participantIds: participants),
                    ),
                    ListTile(
                      leading: const Icon(Icons.emoji_emotions_outlined),
                      title: const Text('Cảm xúc nhanh'),
                      subtitle: Text('Đang dùng $quickReaction'),
                      onTap: () => _showQuickReactionSheet(
                        currentReaction: quickReaction,
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Thay đổi chủ đề'),
                      subtitle: Text(_themeSubtitle(chatData)),
                      onTap: () => _showThemeSheet(chatData: chatData),
                    ),
                    if (isCreator) ...[
                      const Divider(height: 28),
                      ListTile(
                        enabled: !_isDissolvingGroup,
                        leading: Icon(
                          Icons.delete_forever_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          'Giải tán nhóm',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: _isDissolvingGroup
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: _isDissolvingGroup
                            ? null
                            : () =>
                                  _confirmAndDissolveGroup(chatData: chatData),
                      ),
                    ] else if (isCurrentMember) ...[
                      const Divider(height: 28),
                      ListTile(
                        enabled: !_isLeavingGroup,
                        leading: Icon(
                          Icons.logout_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          'Rời nhóm',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text('Chỉ rời khỏi nhóm ở phía bạn'),
                        trailing: _isLeavingGroup
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: _isLeavingGroup
                            ? null
                            : () => _confirmAndLeaveGroup(chatData: chatData),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Biệt danh thành viên',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...participants.map((userId) {
                      final userData = userById[userId];
                      final username =
                          _readString(userData, const ['username']) ?? 'User';
                      final userImage = _readString(userData, const [
                        'image_url',
                        'imageUrl',
                        'userImage',
                      ]);
                      final nickname = _groupNicknameFor(chatData, userId);
                      final isCurrentUser = userId == currentUserId;
                      final subtitleParts = <String>[
                        if (nickname != null) username,
                        if (isCurrentUser) 'Bạn',
                      ];

                      return ListTile(
                        leading: CircleAvatar(
                          foregroundImage: userImage != null
                              ? NetworkImage(userImage)
                              : null,
                          child: userImage == null
                              ? Text(username[0].toUpperCase())
                              : null,
                        ),
                        title: Text(nickname ?? username),
                        subtitle: subtitleParts.isEmpty
                            ? null
                            : Text(subtitleParts.join(' • ')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openMemberNicknameEditor(
                          userId: userId,
                          username: isCurrentUser
                              ? '$username (Bạn)'
                              : username,
                          currentNickname: nickname,
                        ),
                      );
                    }),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AddGroupMembersScreen extends StatefulWidget {
  const _AddGroupMembersScreen({
    required this.chatId,
    required this.currentParticipantIds,
  });

  final String chatId;
  final List<String> currentParticipantIds;

  @override
  State<_AddGroupMembersScreen> createState() => _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState extends State<_AddGroupMembersScreen> {
  final _selectedUserIds = <String>{};
  bool _isAdding = false;

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

  Future<void> _addMembers() async {
    if (_isAdding || _selectedUserIds.isEmpty) {
      return;
    }

    setState(() {
      _isAdding = true;
    });

    try {
      final selectedUserIds = _selectedUserIds.toList()..sort();
      await FirebaseFirestore.instance
          .collection('private_chats')
          .doc(widget.chatId)
          .set({
            'participants': FieldValue.arrayUnion(selectedUserIds),
            'updatedAt': Timestamp.now(),
            'settingsUpdatedAt': Timestamp.now(),
          }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } catch (error) {
      _showSnackBar('Không thêm được thành viên: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Bạn cần đăng nhập để thêm thành viên.')),
      );
    }

    final existingParticipantIds = {
      ...widget.currentParticipantIds,
      currentUser.uid,
    };

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
              if (otherUserId != null &&
                  !existingParticipantIds.contains(otherUserId)) {
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
                title: const Text('Thêm thành viên'),
                actions: [
                  TextButton(
                    onPressed: _isAdding || _selectedUserIds.isEmpty
                        ? null
                        : _addMembers,
                    child: _isAdding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Thêm'),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  Text(
                    'Chọn bạn bè để thêm vào nhóm',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Không còn bạn bè nào để thêm vào nhóm.'),
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
                        onChanged: _isAdding
                            ? null
                            : (selected) {
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

class _NicknameEditResult {
  const _NicknameEditResult(this.nickname);

  final String nickname;
}

class _NicknameEditScreen extends StatefulWidget {
  const _NicknameEditScreen({
    required this.title,
    required this.currentNickname,
  });

  final String title;
  final String? currentNickname;

  @override
  State<_NicknameEditScreen> createState() => _NicknameEditScreenState();
}

class _NicknameEditScreenState extends State<_NicknameEditScreen> {
  late final TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: widget.currentNickname ?? '',
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(_NicknameEditResult(_nicknameController.text));
  }

  void _clear() {
    Navigator.of(context).pop(const _NicknameEditResult(''));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biệt danh'),
        actions: [TextButton(onPressed: _save, child: const Text('Lưu'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            widget.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nicknameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Biệt danh',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Xóa biệt danh'),
          ),
        ],
      ),
    );
  }
}
