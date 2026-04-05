import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.isBorderlessMedia = false,
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
    this.isBorderlessMedia = false,
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
  final bool isBorderlessMedia;
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
                                decoration: isBorderlessMedia
                                    ? null
                                    : BoxDecoration(
                                        color: isMe
                                            ? Colors.grey[300]
                                            : theme.colorScheme.secondary
                                                  .withAlpha(200),
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
                                padding: isBorderlessMedia
                                    ? EdgeInsets.zero
                                    : const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 14,
                                      ),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child:
                                    content ??
                                    _LinkifiedMessageText(
                                      message: message,
                                      chunkSize: safeChunkSize,
                                      style: TextStyle(
                                        height: 1.3,
                                        fontStyle: isDeletedForEveryone
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                        color: isMe
                                            ? Colors.black87
                                            : theme.colorScheme.onSecondary,
                                      ),
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

class _LinkifiedMessageText extends StatefulWidget {
  const _LinkifiedMessageText({
    required this.message,
    required this.chunkSize,
    required this.style,
  });

  final String message;
  final int chunkSize;
  final TextStyle style;

  @override
  State<_LinkifiedMessageText> createState() => _LinkifiedMessageTextState();
}

class _LinkifiedMessageTextState extends State<_LinkifiedMessageText> {
  static final RegExp _urlPattern = RegExp(
    r'((https?:\/\/|www\.)[^\s]+)',
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  String _wrapLongText(String text) {
    final longTokenPattern = RegExp('.{1,${widget.chunkSize}}', dotAll: true);

    return text.splitMapJoin(
      RegExp(r'\S+'),
      onMatch: (match) {
        final token = match.group(0)!;
        if (token.length <= widget.chunkSize) {
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

  Future<void> _openUrl(String rawUrl) async {
    final normalizedUrl = rawUrl.startsWith(RegExp(r'https?:\/\/'))
        ? rawUrl
        : 'https://$rawUrl';
    final uri = Uri.tryParse(normalizedUrl);

    if (uri == null) {
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || launched) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Không mở được đường link.')));
  }

  List<InlineSpan> _buildSpans() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final spans = <InlineSpan>[];
    var start = 0;

    for (final match in _urlPattern.allMatches(widget.message)) {
      if (match.start > start) {
        spans.add(
          TextSpan(
            text: _wrapLongText(widget.message.substring(start, match.start)),
          ),
        );
      }

      final urlText = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          _openUrl(urlText);
        };
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: _wrapLongText(urlText),
          style: widget.style.copyWith(
            color: Colors.blueAccent,
            decoration: TextDecoration.underline,
          ),
          recognizer: recognizer,
        ),
      );
      start = match.end;
    }

    if (start < widget.message.length) {
      spans.add(TextSpan(text: _wrapLongText(widget.message.substring(start))));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: _wrapLongText(widget.message)));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(style: widget.style, children: _buildSpans()),
      softWrap: true,
    );
  }
}
