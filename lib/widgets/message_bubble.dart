import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble.first({
    super.key,
    required this.userImage,
    required this.username,
    required this.message,
    this.content,
    required this.isMe,
    this.onTap,
    this.onLongPress,
    this.isDeletedForEveryone = false,
    this.showReadReceipt = false,
    this.readReceiptUserImage,
    this.readReceiptUsername,
  }) : isFirstInSequence = true;

  const MessageBubble.next({
    super.key,
    required this.message,
    this.content,
    required this.isMe,
    this.onTap,
    this.onLongPress,
    this.isDeletedForEveryone = false,
    this.showReadReceipt = false,
    this.readReceiptUserImage,
    this.readReceiptUsername,
  }) : isFirstInSequence = false,
       userImage = null,
       username = null;

  final bool isFirstInSequence;
  final String? userImage;
  final String? username;
  final String message;
  final Widget? content;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isDeletedForEveryone;
  final bool showReadReceipt;
  final String? readReceiptUserImage;
  final String? readReceiptUsername;
  final bool isMe;

  String _avatarLabel() {
    final trimmedUsername = username?.trim();
    if (trimmedUsername == null || trimmedUsername.isEmpty) {
      return '?';
    }

    return trimmedUsername[0].toUpperCase();
  }

  String _wrapLongText(String text, int chunkSize) {
    final longTokenPattern = RegExp('.{1,$chunkSize}', dotAll: true);

    return text.splitMapJoin(
      RegExp(r'\S+'),
      onMatch: (match) {
        final token = match.group(0)!;
        if (token.length <= chunkSize) {
          return token;
        }

        return longTokenPattern
            .allMatches(token)
            .map((chunkMatch) => chunkMatch.group(0)!)
            .join('\u200B');
      },
      onNonMatch: (value) => value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUserImage = userImage != null && userImage!.trim().isNotEmpty;
    final showSenderAvatar = !isMe && isFirstInSequence;

    return Stack(
      children: [
        if (showSenderAvatar)
          Positioned(
            top: 15,
            child: CircleAvatar(
              foregroundImage: hasUserImage ? NetworkImage(userImage!) : null,
              backgroundColor: theme.colorScheme.primaryContainer,
              radius: 19,
              child: hasUserImage
                  ? null
                  : Text(
                      _avatarLabel(),
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        Container(
          width: double.infinity,
          margin: EdgeInsets.only(left: 42, right: isMe ? 2 : 42),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxBubbleWidth = constraints.maxWidth * 0.7;
              final estimatedChunkSize = (maxBubbleWidth / 11).floor();
              final safeChunkSize = estimatedChunkSize < 18
                  ? 18
                  : estimatedChunkSize;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: isMe
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (isFirstInSequence) const SizedBox(height: 18),
                            GestureDetector(
                              onTap: onTap,
                              onLongPress: onLongPress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.grey[300]
                                      : theme.colorScheme.secondary.withAlpha(
                                          200,
                                        ),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(12),
                                    topRight: const Radius.circular(12),
                                    bottomLeft: !isMe && isFirstInSequence
                                        ? Radius.zero
                                        : const Radius.circular(12),
                                    bottomRight: isMe && isFirstInSequence
                                        ? Radius.zero
                                        : const Radius.circular(12),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 14,
                                ),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child:
                                    content ??
                                    Text(
                                      _wrapLongText(message, safeChunkSize),
                                      style: TextStyle(
                                        height: 1.3,
                                        fontStyle: isDeletedForEveryone
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                        color: isMe
                                            ? Colors.black87
                                            : theme.colorScheme.onSecondary,
                                      ),
                                      softWrap: true,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
