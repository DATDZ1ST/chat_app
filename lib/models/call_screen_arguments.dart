class CallScreenArguments {
  const CallScreenArguments({
    this.callId,
    required this.chatId,
    required this.otherUserId,
    required this.isOutgoing,
    this.isVideo = false,
    this.displayName,
    this.avatarUrl,
  });

  final String? callId;
  final String chatId;
  final String otherUserId;
  final bool isOutgoing;
  final bool isVideo;
  final String? displayName;
  final String? avatarUrl;

  CallScreenArguments copyWith({
    String? callId,
    String? chatId,
    String? otherUserId,
    bool? isOutgoing,
    bool? isVideo,
    String? displayName,
    String? avatarUrl,
  }) {
    return CallScreenArguments(
      callId: callId ?? this.callId,
      chatId: chatId ?? this.chatId,
      otherUserId: otherUserId ?? this.otherUserId,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isVideo: isVideo ?? this.isVideo,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
