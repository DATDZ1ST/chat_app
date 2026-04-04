import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

double _resolveMessageContentWidth(
  BoxConstraints constraints, {
  double preferredWidth = 220,
}) {
  final maxWidth = constraints.maxWidth;
  if (!maxWidth.isFinite || maxWidth <= 0) {
    return preferredWidth;
  }

  return maxWidth < preferredWidth ? maxWidth : preferredWidth;
}

class ChatImageMessage extends StatelessWidget {
  const ChatImageMessage({super.key, required this.imageUrl});

  final String imageUrl;

  void _openFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Center(
                        child: InteractiveViewer(
                          minScale: 0.8,
                          maxScale: 4,
                          child: Hero(
                            tag: imageUrl,
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const _MessageFallbackBox(
                                  icon: Icons.broken_image_outlined,
                                  label: 'Không tải được ảnh',
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final messageWidth = _resolveMessageContentWidth(constraints);

        return GestureDetector(
          onTap: () => _openFullScreenImage(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Hero(
              tag: imageUrl,
              child: Image.network(
                imageUrl,
                width: messageWidth,
                height: messageWidth,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _MessageFallbackBox(
                    icon: Icons.broken_image_outlined,
                    label: 'Không tải được ảnh',
                    width: messageWidth,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class ChatVideoMessage extends StatefulWidget {
  const ChatVideoMessage({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  State<ChatVideoMessage> createState() => _ChatVideoMessageState();
}

class _ChatVideoMessageState extends State<ChatVideoMessage> {
  VideoPlayerController? _controller;
  bool _isInitializing = true;
  bool _hasError = false;
  bool _hasStartedInlinePlayback = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );

    try {
      await controller.initialize();
      controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _hasError = true;
        _isInitializing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleInlineTap() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    if (!_hasStartedInlinePlayback) {
      await controller.play();
      if (mounted) {
        setState(() {
          _hasStartedInlinePlayback = true;
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenVideoViewer(videoUrl: widget.videoUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const SizedBox(
        width: 220,
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasError || _controller == null) {
      return const _MessageFallbackBox(
        icon: Icons.videocam_off_outlined,
        label: 'Không tải được video',
      );
    }

    final controller = _controller!;
    return GestureDetector(
      onTap: _handleInlineTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
            GestureDetector(
              onTap: _hasStartedInlinePlayback ? _togglePlay : null,
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0x88000000),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  !_hasStartedInlinePlayback || !controller.value.isPlaying
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenVideoViewer extends StatefulWidget {
  const _FullScreenVideoViewer({required this.videoUrl});

  final String videoUrl;

  @override
  State<_FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<_FullScreenVideoViewer> {
  VideoPlayerController? _controller;
  bool _isInitializing = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );

    try {
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) {
        return;
      }

      setState(() {
        _hasError = true;
        _isInitializing = false;
      });
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _togglePlayback,
                child: Center(
                  child: _isInitializing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : _hasError || _controller == null
                      ? const _MessageFallbackBox(
                          icon: Icons.videocam_off_outlined,
                          label: 'Không tải được video',
                        )
                      : InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
            if (!_isInitializing && !_hasError && _controller != null)
              Center(
                child: GestureDetector(
                  onTap: _togglePlayback,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      color: Color(0x88000000),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _controller!.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatVoiceMessage extends StatefulWidget {
  const ChatVoiceMessage({
    super.key,
    required this.audioUrl,
    this.durationMs,
    required this.isMe,
  });

  final String audioUrl;
  final int? durationMs;
  final bool isMe;

  @override
  State<ChatVoiceMessage> createState() => _ChatVoiceMessageState();
}

class _ChatVoiceMessageState extends State<ChatVoiceMessage> {
  final AudioPlayer _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _duration = Duration(milliseconds: widget.durationMs ?? 0);
    _player.onPositionChanged.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = position;
      });
    });
    _player.onDurationChanged.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = duration;
      });
    });
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _playerState = state;
        if (state == PlayerState.completed) {
          _position = Duration.zero;
        }
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
      return;
    }

    if (_playerState == PlayerState.paused) {
      await _player.resume();
      return;
    }

    await _player.play(UrlSource(widget.audioUrl));
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isMe
        ? Theme.of(context).colorScheme.primary
        : Colors.white;
    final total = _duration.inMilliseconds <= 0
        ? Duration(milliseconds: widget.durationMs ?? 1)
        : _duration;
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton(
            onPressed: _togglePlayback,
            icon: Icon(
              _playerState == PlayerState.playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
            ),
            color: activeColor,
            iconSize: 34,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tin nhắn thoại',
                  style: TextStyle(
                    color: widget.isMe ? Colors.black87 : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: widget.isMe
                        ? Colors.black12
                        : Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatDuration(
              _playerState == PlayerState.playing ? _position : total,
            ),
            style: TextStyle(
              color: widget.isMe ? Colors.black54 : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatLocationMessage extends StatelessWidget {
  const ChatLocationMessage({
    super.key,
    required this.address,
    required this.previewUrl,
    required this.mapsUrl,
    required this.isLive,
    required this.liveUntil,
    required this.isMe,
  });

  final String address;
  final String? previewUrl;
  final String? mapsUrl;
  final bool isLive;
  final Timestamp? liveUntil;
  final bool isMe;

  String _liveStatus() {
    if (!isLive) {
      return 'Vị trí hiện tại';
    }

    if (liveUntil == null) {
      return 'Chia sẻ vị trí trực tiếp';
    }

    final remaining = liveUntil!.toDate().difference(DateTime.now());
    if (remaining.isNegative) {
      return 'Vị trí trực tiếp đã kết thúc';
    }

    final remainingMinutes = remaining.inMinutes;
    return 'Chia sẻ vị trí trực tiếp • còn $remainingMinutes phút';
  }

  Future<void> _openMap() async {
    final url = mapsUrl ?? previewUrl;
    if (url == null || url.trim().isEmpty) {
      return;
    }

    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = isMe ? Colors.black87 : Colors.white;
    final subtitleColor = isMe ? Colors.black54 : Colors.white70;

    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: previewUrl != null && previewUrl!.trim().isNotEmpty
                ? Image.network(
                    previewUrl!,
                    headers: const {'User-Agent': 'Mozilla/5.0'},
                    height: 120,
                    width: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const _MessageFallbackBox(
                        icon: Icons.location_pin,
                        label: 'Xem vị trí',
                        height: 120,
                      );
                    },
                  )
                : const _MessageFallbackBox(
                    icon: Icons.location_pin,
                    label: 'Xem vị trí',
                    height: 120,
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            _liveStatus(),
            style: TextStyle(color: titleColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: subtitleColor, height: 1.25),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _openMap,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: titleColor,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Mở Goong Map'),
          ),
        ],
      ),
    );
  }
}

class _MessageFallbackBox extends StatelessWidget {
  const _MessageFallbackBox({
    required this.icon,
    required this.label,
    this.width = 220,
    this.height = 220,
  });

  final IconData icon;
  final String label;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.black12,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.black54),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
