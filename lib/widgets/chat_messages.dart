import 'dart:io';
import 'dart:ui' as ui;

import 'package:chat_app/models/call_screen_arguments.dart';
import 'package:chat_app/screens/call.dart';
import 'package:chat_app/widgets/chat_message_content.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ChatMessages extends StatefulWidget {
  const ChatMessages({
    super.key,
    required this.chatId,
    this.otherUserId,
    this.isGroup = false,
    this.initialMessageId,
  });

  static const List<String> _reactionOptions = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '😡',
  ];

  final String chatId;
  final String? otherUserId;
  final bool isGroup;
  final String? initialMessageId;

  @override
  State<ChatMessages> createState() => ChatMessagesState();
}

class ChatMessagesState extends State<ChatMessages> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _chatStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _visibleMessages = const [];
  String? _pendingScrollMessageId;
  String? _selectedTimestampMessageId;

  @override
  void initState() {
    super.initState();
    _usersStream = FirebaseFirestore.instance.collection('users').snapshots();
    _configureChatStreams();
    _pendingScrollMessageId = widget.initialMessageId;
  }

  @override
  void didUpdateWidget(covariant ChatMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _configureChatStreams();
      _pendingScrollMessageId = widget.initialMessageId;
    } else if (oldWidget.initialMessageId != widget.initialMessageId &&
        widget.initialMessageId != null) {
      _pendingScrollMessageId = widget.initialMessageId;
    }
  }

  void _configureChatStreams() {
    _chatStream = FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.chatId)
        .snapshots();
    _messagesStream = FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  void scrollToMessage(String messageId) {
    _pendingScrollMessageId = messageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToPendingMessage();
    });
  }

  void _scrollToPendingMessage() {
    final messageId = _pendingScrollMessageId;
    if (messageId == null || !_itemScrollController.isAttached) {
      return;
    }

    final targetIndex = _visibleMessages.indexWhere(
      (messageDoc) => messageDoc.id == messageId,
    );
    if (targetIndex == -1) {
      return;
    }

    _pendingScrollMessageId = null;
    _itemScrollController.scrollTo(
      index: targetIndex,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      alignment: 0.18,
    );
  }

  void _toggleTimestamp(String messageId) {
    setState(() {
      _selectedTimestampMessageId = _selectedTimestampMessageId == messageId
          ? null
          : messageId;
    });
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

  String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }

  String _formatMessageTime(dynamic createdAt) {
    if (createdAt is! Timestamp) {
      return '';
    }

    final sentAt = createdAt.toDate();
    return '${_twoDigits(sentAt.hour)}:${_twoDigits(sentAt.minute)} • '
        '${_twoDigits(sentAt.day)}/${_twoDigits(sentAt.month)}/${sentAt.year}';
  }

  String _formatCallLogHeader(Map<String, dynamic> messageData) {
    return _formatMessageTime(
      messageData['endedAt'] ?? messageData['createdAt'],
    );
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
          'pinnedBy': _readString(rawMap, const ['pinnedBy']) ?? '',
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
        'pinnedBy': _readString(chatData, const ['pinnedBy']) ?? '',
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

  String? _resolveGroupNickname(
    Map<String, dynamic>? chatData,
    String? userId,
  ) {
    if (userId == null || userId.isEmpty) {
      return null;
    }

    final groupNicknames = chatData?['groupNicknames'];
    if (groupNicknames is! Map) {
      return null;
    }

    final nickname = groupNicknames[userId];
    if (nickname is String && nickname.trim().isNotEmpty) {
      return nickname.trim();
    }

    return null;
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

  int? _readInt(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) {
      return null;
    }

    for (final key in keys) {
      final value = data[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
    }

    return null;
  }

  Timestamp? _readTimestamp(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) {
      return null;
    }

    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) {
        return value;
      }
    }

    return null;
  }

  String _messageType(Map<String, dynamic> messageData) {
    return _readString(messageData, const ['type']) ?? 'text';
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

  Future<void> _copyMessageText(String text) async {
    if (text.trim().isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('Đã sao chép tin nhắn.');
  }

  Future<void> _saveMediaToGallery({
    required String mediaUrl,
    required bool isVideo,
  }) async {
    if (mediaUrl.trim().isEmpty) {
      return;
    }

    File? tempFile;

    try {
      final hasAccess = await Gal.requestAccess();
      if (!hasAccess) {
        _showSnackBar(
          isVideo
              ? 'Chưa được cấp quyền lưu video.'
              : 'Chưa được cấp quyền lưu ảnh.',
        );
        return;
      }

      if (isVideo) {
        tempFile = await _downloadMediaToTempFile(
          mediaUrl: mediaUrl,
          isVideo: true,
        );
        await Gal.putVideo(tempFile.path);
      } else {
        final imageBytes = await _downloadImageBytesForGallery(mediaUrl);
        await Gal.putImageBytes(
          imageBytes,
          name: 'chat_image_${DateTime.now().millisecondsSinceEpoch}',
        );
      }

      _showSnackBar(isVideo ? 'Đã lưu video vào máy.' : 'Đã lưu ảnh vào máy.');
    } on GalException catch (error, stackTrace) {
      debugPrint('Save media failed: ${error.type} ${error.platformException}');
      debugPrintStack(stackTrace: stackTrace);
      final message = switch (error.type) {
        GalExceptionType.accessDenied =>
          isVideo
              ? 'Chưa được cấp quyền lưu video.'
              : 'Chưa được cấp quyền lưu ảnh.',
        GalExceptionType.notSupportedFormat =>
          isVideo
              ? 'Định dạng video không được hỗ trợ.'
              : 'Định dạng ảnh không được hỗ trợ.',
        GalExceptionType.notEnoughSpace => 'Không đủ bộ nhớ để lưu tệp.',
        GalExceptionType.unexpected =>
          isVideo ? 'Không lưu được video.' : 'Không lưu được ảnh.',
      };
      _showSnackBar(message);
    } catch (error, stackTrace) {
      debugPrint('Save media failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showSnackBar(isVideo ? 'Không lưu được video.' : 'Không lưu được ảnh.');
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<File> _downloadMediaToTempFile({
    required String mediaUrl,
    required bool isVideo,
  }) async {
    final response = await http.get(
      Uri.parse(mediaUrl),
      headers: const {'User-Agent': 'Mozilla/5.0'},
    );
    if (response.statusCode >= 400) {
      throw Exception('Không thể tải xuống phương tiện.');
    }

    final uri = Uri.parse(mediaUrl);
    final lastSegment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final extensionPattern = RegExp(r'\.[a-zA-Z0-9]{3,5}$');
    final matchedExtension = extensionPattern.stringMatch(lastSegment);
    final resolvedExtension =
        matchedExtension ??
        _extensionFromContentType(
          response.headers['content-type'],
          isVideo: isVideo,
        );
    return _writeTempBytesToFile(
      bytes: response.bodyBytes,
      filePrefix: isVideo ? 'chat_video_' : 'chat_media_',
      extension: resolvedExtension,
    );
  }

  Future<Uint8List> _downloadImageBytesForGallery(String mediaUrl) async {
    final response = await http.get(
      Uri.parse(mediaUrl),
      headers: const {'User-Agent': 'Mozilla/5.0'},
    );
    if (response.statusCode >= 400) {
      throw Exception('Không thể tải xuống hình ảnh.');
    }

    try {
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          final byteData = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (byteData == null) {
            throw Exception('Không thể mã hóa hình ảnh.');
          }

          return byteData.buffer.asUint8List();
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return response.bodyBytes;
    }
  }

  Future<File> _writeTempBytesToFile({
    required Uint8List bytes,
    required String filePrefix,
    required String extension,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final safeExtension = extension.startsWith('.') ? extension : '.$extension';
    final tempPath =
        '${tempDir.path}/$filePrefix${DateTime.now().millisecondsSinceEpoch}$safeExtension';
    final file = File(tempPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _extensionFromContentType(
    String? contentType, {
    required bool isVideo,
  }) {
    final normalized = contentType?.toLowerCase() ?? '';
    if (normalized.contains('image/png')) {
      return '.png';
    }
    if (normalized.contains('image/webp')) {
      return '.webp';
    }
    if (normalized.contains('image/gif')) {
      return '.gif';
    }
    if (normalized.contains('image/heic')) {
      return '.heic';
    }
    if (normalized.contains('image/avif')) {
      return '.avif';
    }
    if (normalized.contains('video/quicktime')) {
      return '.mov';
    }
    if (normalized.contains('video/webm')) {
      return '.webm';
    }
    return isVideo ? '.mp4' : '.jpg';
  }

  bool _isDeletedForMe(Map<String, dynamic> messageData, String userId) {
    final deletedFor = List<String>.from(messageData['deletedFor'] ?? const []);
    return deletedFor.contains(userId);
  }

  bool _isDeletedForEveryone(Map<String, dynamic> messageData) {
    return messageData['deletedForEveryone'] == true;
  }

  String _messageText(Map<String, dynamic> messageData) {
    if (_isDeletedForEveryone(messageData)) {
      return 'Tin nhắn đã bị thu hồi';
    }

    return _readString(messageData, const ['text']) ?? '';
  }

  Future<void> _recallFromChat({
    required bool isVideo,
    required String displayName,
    String? avatarUrl,
  }) {
    final otherUserId = widget.otherUserId;
    if (widget.isGroup || otherUserId == null || otherUserId.isEmpty) {
      return Future.value();
    }

    return Navigator.of(context).pushNamed(
      CallScreen.routeName,
      arguments: CallScreenArguments(
        chatId: widget.chatId,
        otherUserId: otherUserId,
        isOutgoing: true,
        isVideo: isVideo,
        displayName: displayName,
        avatarUrl: avatarUrl,
      ),
    );
  }

  Map<String, bool> _buildCallLogHeaderVisibility(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> messages,
  ) {
    const clusterGap = Duration(minutes: 30);
    final visibilityById = <String, bool>{};
    DateTime? lastShownCallAt;

    for (final messageDoc in messages.reversed) {
      final messageData = messageDoc.data();
      if (_messageType(messageData) != 'call_log') {
        continue;
      }

      final endedAt = _readTimestamp(messageData, const ['endedAt']);
      if (endedAt == null) {
        visibilityById[messageDoc.id] = false;
        continue;
      }

      final endedAtDate = endedAt.toDate();
      final shouldShowHeader =
          lastShownCallAt == null ||
          endedAtDate.difference(lastShownCallAt) >= clusterGap;
      visibilityById[messageDoc.id] = shouldShowHeader;

      if (shouldShowHeader) {
        lastShownCallAt = endedAtDate;
      }
    }

    return visibilityById;
  }

  Widget? _buildMessageContent(
    Map<String, dynamic> messageData, {
    required String messageId,
    required bool isMe,
    required String otherUsername,
    String? otherUserImage,
  }) {
    final type = _messageType(messageData);
    final mediaUrl = _readString(messageData, const ['mediaUrl']);

    switch (type) {
      case 'image':
        if (mediaUrl == null) {
          return null;
        }
        return ChatImageMessage(imageUrl: mediaUrl);
      case 'video':
        if (mediaUrl == null) {
          return null;
        }
        return ChatVideoMessage(videoUrl: mediaUrl);
      case 'voice':
        if (mediaUrl == null) {
          return null;
        }
        return ChatVoiceMessage(
          audioUrl: mediaUrl,
          durationMs: _readInt(messageData, const ['durationMs']),
          isMe: isMe,
        );
      case 'call_log':
        if (widget.isGroup) {
          return null;
        }

        final callMode =
            _readString(messageData, const ['callMode']) ?? 'voice';
        final callStatus =
            _readString(messageData, const ['callStatus']) ?? 'ended';
        return ChatCallLogMessage(
          callMode: callMode,
          callStatus: callStatus,
          durationSeconds: _readInt(messageData, const ['durationSeconds']),
          isMe: isMe,
          onRecall: () => _recallFromChat(
            isVideo: callMode == 'video',
            displayName: otherUsername,
            avatarUrl: otherUserImage,
          ),
        );
      case 'location':
      case 'live_location':
        return ChatLocationMessage(
          address:
              _readString(messageData, const ['locationAddress']) ??
              'Vị trí đã chia sẻ',
          previewUrl: _readString(messageData, const ['locationPreviewUrl']),
          mapsUrl: _readString(messageData, const ['locationMapsUrl']),
          isLive: type == 'live_location',
          liveUntil: _readTimestamp(messageData, const ['liveUntil']),
          isMe: isMe,
        );
      default:
        return null;
    }
  }

  Map<String, String> _readReactions(Map<String, dynamic> messageData) {
    final rawReactions = Map<String, dynamic>.from(
      messageData['reactions'] ?? const {},
    );
    final reactions = <String, String>{};

    for (final entry in rawReactions.entries) {
      final emoji = entry.value;
      if (emoji is String && emoji.trim().isNotEmpty) {
        reactions[entry.key] = emoji.trim();
      }
    }

    return reactions;
  }

  Map<String, int> _countReactions(Map<String, String> reactions) {
    final counts = <String, int>{};

    for (final emoji in reactions.values) {
      counts.update(emoji, (value) => value + 1, ifAbsent: () => 1);
    }

    return counts;
  }

  Future<void> _toggleReaction({
    required String messageId,
    required String currentUserId,
    required String emoji,
    required Map<String, dynamic> messageData,
  }) async {
    if (_isDeletedForEveryone(messageData)) {
      return;
    }

    final currentReactions = _readReactions(messageData);
    final existingEmoji = currentReactions[currentUserId];
    final messageRef = FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(messageId);

    if (existingEmoji == emoji) {
      await messageRef.update({
        'reactions.$currentUserId': FieldValue.delete(),
      });
      return;
    }

    await messageRef.set({
      'reactions': {currentUserId: emoji},
    }, SetOptions(merge: true));
  }

  Future<void> _pinMessage({
    required String messageId,
    required String pinnedText,
    required String currentUserId,
  }) async {
    final chatRef = FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.chatId);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final chatSnapshot = await transaction.get(chatRef);
      final pinnedMessages = _readPinnedMessages(chatSnapshot.data());
      if (pinnedMessages.any((item) => item['messageId'] == messageId)) {
        return;
      }

      final now = Timestamp.now();
      transaction.set(chatRef, {
        'pinnedMessages': [
          {
            'messageId': messageId,
            'text': pinnedText,
            'pinnedBy': currentUserId,
            'pinnedAt': now,
          },
          ...pinnedMessages,
        ],
        'pinnedMessageId': FieldValue.delete(),
        'pinnedMessageText': FieldValue.delete(),
        'pinnedBy': FieldValue.delete(),
        'pinnedAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _unpinMessage(String messageId) async {
    final chatRef = FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.chatId);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final chatSnapshot = await transaction.get(chatRef);
      final updatedPinnedMessages = _readPinnedMessages(
        chatSnapshot.data(),
      ).where((item) => item['messageId'] != messageId).toList();

      transaction.set(chatRef, {
        'pinnedMessages': updatedPinnedMessages.isEmpty
            ? FieldValue.delete()
            : updatedPinnedMessages,
        'pinnedMessageId': FieldValue.delete(),
        'pinnedMessageText': FieldValue.delete(),
        'pinnedBy': FieldValue.delete(),
        'pinnedAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _deleteForMe({
    required String messageId,
    required String currentUserId,
  }) async {
    await FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(messageId)
        .update({
          'deletedFor': FieldValue.arrayUnion([currentUserId]),
        });
  }

  Future<void> _deleteForEveryone({
    required String messageId,
    required bool isLatestMessage,
    required String currentUserId,
    required List<Map<String, dynamic>> pinnedMessages,
  }) async {
    final chatRef = FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.chatId);
    final messageRef = chatRef.collection('messages').doc(messageId);
    final batch = FirebaseFirestore.instance.batch();

    batch.update(messageRef, {
      'text': 'Tin nhắn đã bị thu hồi',
      'deletedForEveryone': true,
      'deletedForEveryoneAt': Timestamp.now(),
      'reactions': {},
    });

    final chatUpdates = <String, dynamic>{};
    if (isLatestMessage) {
      chatUpdates['lastMessage'] = 'Tin nhắn đã bị thu hồi';
      chatUpdates['lastMessageSenderId'] = currentUserId;
      chatUpdates['updatedAt'] = Timestamp.now();
    }
    if (pinnedMessages.any((item) => item['messageId'] == messageId)) {
      final updatedPinnedMessages = pinnedMessages
          .where((item) => item['messageId'] != messageId)
          .toList();
      chatUpdates['pinnedMessages'] = updatedPinnedMessages.isEmpty
          ? FieldValue.delete()
          : updatedPinnedMessages;
      chatUpdates['pinnedMessageId'] = FieldValue.delete();
      chatUpdates['pinnedMessageText'] = FieldValue.delete();
      chatUpdates['pinnedBy'] = FieldValue.delete();
      chatUpdates['pinnedAt'] = FieldValue.delete();
    }
    if (chatUpdates.isNotEmpty) {
      batch.update(chatRef, chatUpdates);
    }

    await batch.commit();
  }

  Widget _buildReactionChip(BuildContext context, String emoji, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(count > 1 ? '$emoji $count' : emoji),
    );
  }

  Widget _buildReactionSummary({
    required BuildContext context,
    required bool isMe,
    required Map<String, int> reactionCounts,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 0 : 50,
        right: isMe ? 8 : 0,
        top: 2,
        bottom: 2,
      ),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: reactionCounts.entries
                .map(
                  (entry) =>
                      _buildReactionChip(context, entry.key, entry.value),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReadReceipt({
    required BuildContext context,
    required String? userImage,
    required String username,
  }) {
    final theme = Theme.of(context);
    final hasUserImage = userImage != null && userImage.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 2),
      child: CircleAvatar(
        foregroundImage: hasUserImage ? NetworkImage(userImage) : null,
        backgroundColor: theme.colorScheme.primaryContainer,
        radius: 8,
        child: hasUserImage
            ? null
            : Text(
                username.isEmpty ? '?' : username[0].toUpperCase(),
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildReactionButton(
    BuildContext context, {
    required String emoji,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }

  Future<void> _showMessageActions({
    required BuildContext context,
    required String messageId,
    required Map<String, dynamic> messageData,
    required String currentUserId,
    required List<Map<String, dynamic>> pinnedMessages,
    required bool isLatestMessage,
  }) async {
    final isMyMessage =
        _readString(messageData, const ['userId']) == currentUserId;
    final messageType = _messageType(messageData);
    final mediaUrl = _readString(messageData, const ['mediaUrl']);
    final isPinned = pinnedMessages.any(
      (item) => item['messageId'] == messageId,
    );
    final isDeletedForEveryone = _isDeletedForEveryone(messageData);
    final displayText = _messageText(messageData);
    final canCopyText =
        messageType == 'text' &&
        displayText.trim().isNotEmpty &&
        !isDeletedForEveryone;
    final canSaveMedia =
        !isMyMessage &&
        !isDeletedForEveryone &&
        mediaUrl != null &&
        (messageType == 'image' || messageType == 'video');

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isDeletedForEveryone) ...[
                  Text(
                    'Thả cảm xúc',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ChatMessages._reactionOptions.map((emoji) {
                      return _buildReactionButton(
                        sheetContext,
                        emoji: emoji,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          await _toggleReaction(
                            messageId: messageId,
                            currentUserId: currentUserId,
                            emoji: emoji,
                            messageData: messageData,
                          );
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                ],
                if (canCopyText)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.copy_all_outlined),
                    title: const Text('Sao chép tin nhắn'),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _copyMessageText(displayText);
                    },
                  ),
                if (canSaveMedia)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      messageType == 'video'
                          ? Icons.video_library_outlined
                          : Icons.download_outlined,
                    ),
                    title: Text(
                      messageType == 'video'
                          ? 'Lưu video vào máy'
                          : 'Lưu ảnh vào máy',
                    ),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _saveMediaToGallery(
                        mediaUrl: mediaUrl,
                        isVideo: messageType == 'video',
                      );
                    },
                  ),
                if (!isDeletedForEveryone || isPinned)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    title: Text(
                      isPinned ? 'Bỏ ghim tin nhắn' : 'Ghim tin nhắn',
                    ),
                    subtitle: Text(
                      displayText.isEmpty ? 'Tin nhắn trống' : displayText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      if (isPinned) {
                        await _unpinMessage(messageId);
                      } else {
                        await _pinMessage(
                          messageId: messageId,
                          pinnedText: displayText,
                          currentUserId: currentUserId,
                        );
                      }
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Xóa ở phía bạn'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _deleteForMe(
                      messageId: messageId,
                      currentUserId: currentUserId,
                    );
                  },
                ),
                if (isMyMessage && !isDeletedForEveryone)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_forever_outlined),
                    title: const Text('Xóa ở tất cả'),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _deleteForEveryone(
                        messageId: messageId,
                        isLatestMessage: isLatestMessage,
                        currentUserId: currentUserId,
                        pinnedMessages: pinnedMessages,
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedUser = FirebaseAuth.instance.currentUser!;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersStream,
      builder: (ctx, userSnapshots) {
        if (!userSnapshots.hasData &&
            userSnapshots.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (userSnapshots.hasError) {
          return const Center(child: Text('Đã xảy ra lỗi...'));
        }

        final userProfiles = {
          for (final userDoc in userSnapshots.data?.docs ?? [])
            userDoc.id: userDoc.data(),
        };

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _chatStream,
          builder: (ctx, chatDocSnapshot) {
            final chatData = chatDocSnapshot.data?.data();
            final pinnedMessages = _readPinnedMessages(chatData);
            final clearedAt = _readConversationClearedAt(
              chatData,
              authenticatedUser.uid,
            );

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (ctx, chatSnapshots) {
                if (!chatSnapshots.hasData &&
                    chatSnapshots.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (chatSnapshots.hasError) {
                  return const Center(child: Text('Đã xảy ra lỗi...'));
                }

                final rawMessages = chatSnapshots.data?.docs ?? [];
                final visibleMessages = rawMessages.where((messageDoc) {
                  final messageData = messageDoc.data();
                  return !_isDeletedForMe(messageData, authenticatedUser.uid) &&
                      !_wasMessageClearedForCurrentUser(messageData, clearedAt);
                }).toList();

                if (visibleMessages.isEmpty) {
                  return const Center(
                    child: Text('Không tìm thấy tin nhắn nào.'),
                  );
                }

                _visibleMessages = visibleMessages;
                if (_pendingScrollMessageId != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToPendingMessage();
                  });
                }

                String? latestReadMessageId;
                if (!widget.isGroup &&
                    widget.otherUserId != null &&
                    widget.otherUserId!.isNotEmpty) {
                  for (final messageDoc in visibleMessages) {
                    final messageData = messageDoc.data();
                    final readBy = List<String>.from(
                      messageData['readBy'] ?? const [],
                    );
                    if (readBy.contains(widget.otherUserId)) {
                      latestReadMessageId = messageDoc.id;
                      break;
                    }
                  }
                }

                final otherUserProfile = widget.otherUserId == null
                    ? null
                    : userProfiles[widget.otherUserId];
                final readReceiptUserImage = widget.isGroup
                    ? null
                    : _resolveUserImage(otherUserProfile, const {});
                final readReceiptUsername = widget.isGroup
                    ? 'User'
                    : _resolveUsername(otherUserProfile, const {}) ?? 'User';
                final otherUsername = readReceiptUsername;
                final otherUserImage = readReceiptUserImage;
                final callLogHeaderVisibility = _buildCallLogHeaderVisibility(
                  visibleMessages,
                );

                return ScrollablePositionedList.builder(
                  padding: const EdgeInsets.only(
                    bottom: 40,
                    left: 12,
                    right: 12,
                  ),
                  reverse: true,
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  itemCount: visibleMessages.length,
                  itemBuilder: (ctx, index) {
                    final messageDoc = visibleMessages[index];
                    final chatMessage = messageDoc.data();
                    final previousChatMessage = index > 0
                        ? visibleMessages[index - 1].data()
                        : null;
                    final currentMessageUserId = chatMessage['userId'];
                    final previousMessageUserId = previousChatMessage != null
                        ? previousChatMessage['userId']
                        : null;
                    final previousUserIsSame =
                        previousMessageUserId == currentMessageUserId;
                    final profileData = userProfiles[currentMessageUserId];
                    final username =
                        (widget.isGroup
                            ? _resolveGroupNickname(
                                chatData,
                                currentMessageUserId is String
                                    ? currentMessageUserId
                                    : null,
                              )
                            : null) ??
                        _resolveUsername(profileData, chatMessage) ??
                        'User';
                    final userImage = _resolveUserImage(
                      profileData,
                      chatMessage,
                    );
                    final isDeletedForEveryone = _isDeletedForEveryone(
                      chatMessage,
                    );
                    final isMe = authenticatedUser.uid == currentMessageUserId;
                    final showSenderHeader =
                        widget.isGroup && !isMe && !previousUserIsSame;
                    final messageType = _messageType(chatMessage);
                    final messageText = _messageText(chatMessage);
                    final messageContent = isDeletedForEveryone
                        ? null
                        : _buildMessageContent(
                            chatMessage,
                            messageId: messageDoc.id,
                            isMe: isMe,
                            otherUsername: otherUsername,
                            otherUserImage: otherUserImage,
                          );
                    final isBorderlessMedia =
                        !isDeletedForEveryone &&
                        (messageType == 'image' || messageType == 'video');
                    final reactions = isDeletedForEveryone
                        ? <String, String>{}
                        : _readReactions(chatMessage);
                    final reactionCounts = _countReactions(reactions);
                    final showReadReceipt =
                        messageDoc.id == latestReadMessageId;
                    final showTimestamp =
                        messageDoc.id == _selectedTimestampMessageId;
                    final timestampLabel = _formatMessageTime(
                      chatMessage['createdAt'],
                    );
                    final callLogHeaderLabel =
                        messageType == 'call_log' &&
                            (callLogHeaderVisibility[messageDoc.id] ?? false)
                        ? _formatCallLogHeader(chatMessage)
                        : '';
                    final isLatestMessage =
                        visibleMessages.isNotEmpty &&
                        visibleMessages.first.id == messageDoc.id;
                    final messageBubble = previousUserIsSame
                        ? MessageBubble.next(
                            message: messageText,
                            content: messageContent,
                            isMe: isMe,
                            isBorderlessMedia: isBorderlessMedia,
                            onTap: () => _toggleTimestamp(messageDoc.id),
                            isDeletedForEveryone: isDeletedForEveryone,
                            onLongPress: () => _showMessageActions(
                              context: context,
                              messageId: messageDoc.id,
                              messageData: chatMessage,
                              currentUserId: authenticatedUser.uid,
                              pinnedMessages: pinnedMessages,
                              isLatestMessage: isLatestMessage,
                            ),
                          )
                        : MessageBubble.first(
                            userImage: userImage,
                            username: username,
                            message: messageText,
                            content: messageContent,
                            isMe: isMe,
                            isBorderlessMedia: isBorderlessMedia,
                            onTap: () => _toggleTimestamp(messageDoc.id),
                            isDeletedForEveryone: isDeletedForEveryone,
                            onLongPress: () => _showMessageActions(
                              context: context,
                              messageId: messageDoc.id,
                              messageData: chatMessage,
                              currentUserId: authenticatedUser.uid,
                              pinnedMessages: pinnedMessages,
                              isLatestMessage: isLatestMessage,
                            ),
                          );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (callLogHeaderLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 6),
                            child: Text(
                              callLogHeaderLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (showSenderHeader)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 46,
                              top: 6,
                              bottom: 0,
                            ),
                            child: Text(
                              username,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        messageBubble,
                        if (showTimestamp && timestampLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 4),
                            child: Text(
                              timestampLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (reactionCounts.isNotEmpty)
                          _buildReactionSummary(
                            context: context,
                            isMe: isMe,
                            reactionCounts: reactionCounts,
                          ),
                        if (showReadReceipt)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _buildReadReceipt(
                                context: context,
                                userImage: readReceiptUserImage,
                                username: readReceiptUsername,
                              ),
                            ],
                          ),
                      ],
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
