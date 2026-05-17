import 'dart:io';

import 'package:chat_app/services/cloudinary_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ConversationSettingsScreen extends StatefulWidget {
  const ConversationSettingsScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.fallbackUsername,
    required this.fallbackUserImage,
  });

  final String chatId;
  final String otherUserId;
  final String fallbackUsername;
  final String? fallbackUserImage;

  @override
  State<ConversationSettingsScreen> createState() =>
      _ConversationSettingsScreenState();
}

class _ConversationSettingsScreenState
    extends State<ConversationSettingsScreen> {
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

  String? _readMappedString(
    Map<String, dynamic>? data,
    String field,
    String key,
  ) {
    final rawMap = data?[field];
    if (rawMap is! Map) {
      return null;
    }

    final value = rawMap[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return null;
  }

  String? _otherUserNickname(Map<String, dynamic>? chatData) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return null;
    }

    final nicknamesByUser = chatData?['nicknamesByUser'];
    if (nicknamesByUser is! Map) {
      return null;
    }

    final currentUserNicknames = nicknamesByUser[currentUserId];
    if (currentUserNicknames is! Map) {
      return null;
    }

    final nickname = currentUserNicknames[widget.otherUserId];
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

    return _readMappedString(chatData, 'quickReactions', currentUserId) ??
        _defaultQuickReaction;
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

  Future<void> _saveNickname(String nickname) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      throw Exception('Bạn cần đăng nhập lại để đổi biệt danh.');
    }

    final chatSnapshot = await _chatDocument.get();
    final chatData = chatSnapshot.data();
    final nicknamesByUser = Map<String, dynamic>.from(
      chatData?['nicknamesByUser'] ?? const {},
    );
    final currentUserNicknames = Map<String, dynamic>.from(
      nicknamesByUser[currentUserId] ?? const {},
    );
    final legacyNicknames = Map<String, dynamic>.from(
      chatData?['nicknames'] ?? const {},
    )..remove(widget.otherUserId);
    final trimmedNickname = nickname.trim();

    if (trimmedNickname.isEmpty) {
      currentUserNicknames.remove(widget.otherUserId);
    } else {
      currentUserNicknames[widget.otherUserId] = trimmedNickname;
    }

    if (currentUserNicknames.isEmpty) {
      nicknamesByUser.remove(currentUserId);
    } else {
      nicknamesByUser[currentUserId] = currentUserNicknames;
    }

    await _chatDocument.set({
      'nicknames': legacyNicknames,
      'nicknamesByUser': nicknamesByUser,
      'settingsUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> _openNicknameEditor({
    required String username,
    required String? currentNickname,
  }) async {
    final result = await Navigator.of(context).push<_NicknameEditResult>(
      MaterialPageRoute(
        builder: (context) => _NicknameEditScreen(
          username: username,
          currentNickname: currentNickname,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      await _saveNickname(result.nickname);
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
      _showSnackBar('Đã đổi ảnh nền cuộc trò chuyện.');
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
            _showSnackBar('Đã đổi màu nền cuộc trò chuyện.');
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

  Future<void> _openConversationSearch({
    required String currentUserId,
    required Timestamp? clearedAt,
  }) async {
    final selectedMessageId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => _ConversationSearchScreen(
          chatId: widget.chatId,
          currentUserId: currentUserId,
          clearedAt: clearedAt,
        ),
      ),
    );

    if (!mounted || selectedMessageId == null) {
      return;
    }

    Navigator.of(context).pop(selectedMessageId);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .snapshots(),
      builder: (context, userSnapshot) {
        final otherUserData = userSnapshot.data?.data();
        final username =
            _readString(otherUserData, const ['username']) ??
            widget.fallbackUsername;
        final userImage =
            _readString(otherUserData, const [
              'image_url',
              'imageUrl',
              'userImage',
            ]) ??
            widget.fallbackUserImage;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _chatDocument.snapshots(),
          builder: (context, chatSnapshot) {
            final chatData = chatSnapshot.data?.data();
            final nickname = _otherUserNickname(chatData);
            final displayName = nickname ?? username;
            final quickReaction = _quickReactionFor(chatData);
            final clearedAt = currentUserId == null
                ? null
                : _readConversationClearedAt(chatData, currentUserId);

            return Scaffold(
              appBar: AppBar(title: const Text('Thông tin')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  CircleAvatar(
                    radius: 52,
                    foregroundImage: userImage != null
                        ? NetworkImage(userImage)
                        : null,
                    child: userImage == null
                        ? Text(
                            displayName.isEmpty
                                ? '?'
                                : displayName[0].toUpperCase(),
                            style: const TextStyle(fontSize: 34),
                          )
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (nickname != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      username,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Biệt danh'),
                    subtitle: Text(nickname ?? 'Chưa đặt'),
                    onTap: () => _openNicknameEditor(
                      username: username,
                      currentNickname: nickname,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.search),
                    title: const Text('Tìm kiếm'),
                    subtitle: const Text('Tìm tin nhắn trong cuộc trò chuyện'),
                    onTap: currentUserId == null
                        ? null
                        : () => _openConversationSearch(
                            currentUserId: currentUserId,
                            clearedAt: clearedAt,
                          ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.emoji_emotions_outlined),
                    title: const Text('Cảm xúc nhanh'),
                    subtitle: Text('Đang dùng $quickReaction'),
                    onTap: () =>
                        _showQuickReactionSheet(currentReaction: quickReaction),
                  ),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Thay đổi chủ đề'),
                    subtitle: Text(_themeSubtitle(chatData)),
                    onTap: () => _showThemeSheet(chatData: chatData),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ConversationSearchScreen extends StatefulWidget {
  const _ConversationSearchScreen({
    required this.chatId,
    required this.currentUserId,
    required this.clearedAt,
  });

  final String chatId;
  final String currentUserId;
  final Timestamp? clearedAt;

  @override
  State<_ConversationSearchScreen> createState() =>
      _ConversationSearchScreenState();
}

class _ConversationSearchScreenState extends State<_ConversationSearchScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
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

  bool _isDeletedForMe(Map<String, dynamic>? data) {
    final deletedFor = List<String>.from(data?['deletedFor'] ?? const []);
    return deletedFor.contains(widget.currentUserId);
  }

  bool _wasMessageClearedForCurrentUser(Map<String, dynamic>? messageData) {
    if (messageData == null || widget.clearedAt == null) {
      return false;
    }

    final createdAt = messageData['createdAt'];
    if (createdAt is! Timestamp) {
      return false;
    }

    return createdAt.millisecondsSinceEpoch <=
        widget.clearedAt!.millisecondsSinceEpoch;
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

  bool _messageMatchesSearch(Map<String, dynamic> messageData) {
    if (_searchQuery.isEmpty ||
        _isDeletedForMe(messageData) ||
        _wasMessageClearedForCurrentUser(messageData) ||
        messageData['deletedForEveryone'] == true) {
      return false;
    }

    final preview = _messagePreview(messageData).trim().toLowerCase();
    return preview.contains(_searchQuery);
  }

  String _formatSearchResultTime(dynamic createdAt) {
    if (createdAt is! Timestamp) {
      return '';
    }

    final date = createdAt.toDate();
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')} '
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Tìm kiếm',
            border: InputBorder.none,
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value.trim().toLowerCase();
            });
          },
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('private_chats')
            .doc(widget.chatId)
            .collection('messages')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (_searchQuery.isEmpty) {
            return const Center(child: Text('Nhập từ khóa để tìm tin nhắn.'));
          }

          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final matches =
              snapshot.data?.docs
                  .where(
                    (messageDoc) => _messageMatchesSearch(messageDoc.data()),
                  )
                  .toList() ??
              const [];

          if (matches.isEmpty) {
            return const Center(
              child: Text('Không tìm thấy tin nhắn phù hợp.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: matches.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final messageDoc = matches[index];
              final messageData = messageDoc.data();
              final preview = _messagePreview(messageData);
              final timeLabel = _formatSearchResultTime(
                messageData['createdAt'],
              );

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.message_outlined),
                title: Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: timeLabel.isEmpty ? null : Text(timeLabel),
                onTap: () => Navigator.of(context).pop(messageDoc.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _NicknameEditResult {
  const _NicknameEditResult(this.nickname);

  final String nickname;
}

class _NicknameEditScreen extends StatefulWidget {
  const _NicknameEditScreen({
    required this.username,
    required this.currentNickname,
  });

  final String username;
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
          TextField(
            controller: _nicknameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Tên hiển thị',
              hintText: widget.username,
              border: const OutlineInputBorder(),
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
