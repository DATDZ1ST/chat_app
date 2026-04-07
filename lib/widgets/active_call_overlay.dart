import 'package:chat_app/navigation/app_navigator.dart';
import 'package:chat_app/screens/call.dart';
import 'package:chat_app/services/active_call_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ActiveCallOverlay extends StatefulWidget {
  const ActiveCallOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<ActiveCallOverlay> createState() => _ActiveCallOverlayState();
}

class _ActiveCallOverlayState extends State<ActiveCallOverlay> {
  static const double _overlayWidth = 220;
  static const double _voiceOverlayHeight = 76;
  static const double _videoOverlayHeight = 160;
  static const double _screenPadding = 16;
  static const double _bottomPadding = 28;

  Offset? _overlayOffset;

  double _overlayHeight(ActiveCallSession session) {
    return session.isVideoCall && session.hasRemoteVideo
        ? _videoOverlayHeight
        : _voiceOverlayHeight;
  }

  Offset _defaultOffset(Size screenSize, double overlayHeight) {
    return Offset(
      screenSize.width - _overlayWidth - _screenPadding,
      screenSize.height - overlayHeight - _bottomPadding,
    );
  }

  Offset _clampOffset(Offset offset, Size screenSize, double overlayHeight) {
    final maxX = (screenSize.width - _overlayWidth - _screenPadding).clamp(
      _screenPadding,
      double.infinity,
    );
    final maxY = (screenSize.height - overlayHeight - _screenPadding).clamp(
      _screenPadding,
      double.infinity,
    );

    return Offset(
      offset.dx.clamp(_screenPadding, maxX),
      offset.dy.clamp(_screenPadding, maxY),
    );
  }

  void _openCall() {
    final session = ActiveCallSession.instance;
    final args = session.currentArguments;
    final navigator = AppNavigator.navigatorKey.currentState;
    if (args == null || navigator == null) {
      return;
    }

    navigator.pushNamed(CallScreen.routeName, arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    final session = ActiveCallSession.instance;

    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final showOverlay = session.hasOngoingCall && session.isMinimized;
        final hasAvatar =
            session.avatarUrl != null && session.avatarUrl!.trim().isNotEmpty;
        final isVideoPreview = session.isVideoCall && session.hasRemoteVideo;

        return LayoutBuilder(
          builder: (context, constraints) {
            final screenSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final overlayHeight = _overlayHeight(session);
            final effectiveOffset = _clampOffset(
              _overlayOffset ?? _defaultOffset(screenSize, overlayHeight),
              screenSize,
              overlayHeight,
            );

            return Stack(
              children: [
                widget.child,
                if (showOverlay)
                  Positioned(
                    left: effectiveOffset.dx,
                    top: effectiveOffset.dy,
                    child: GestureDetector(
                      onTap: _openCall,
                      onPanUpdate: (details) {
                        setState(() {
                          _overlayOffset = _clampOffset(
                            effectiveOffset + details.delta,
                            screenSize,
                            overlayHeight,
                          );
                        });
                      },
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: _overlayWidth,
                          decoration: BoxDecoration(
                            color: const Color(0xEE101418),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: isVideoPreview
                              ? _buildVideoOverlayCard(session)
                              : _buildVoiceOverlayCard(session, hasAvatar),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildVoiceOverlayCard(ActiveCallSession session, bool hasAvatar) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            foregroundImage: hasAvatar
                ? NetworkImage(session.avatarUrl!)
                : null,
            backgroundColor: Colors.white10,
            child: hasAvatar
                ? null
                : Text(
                    session.displayName.isEmpty
                        ? '?'
                        : session.displayName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Voice call',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.call_rounded, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildVideoOverlayCard(ActiveCallSession session) {
    return SizedBox(
      height: _videoOverlayHeight,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: RTCVideoView(
              session.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
          if (session.hasLocalVideo)
            Positioned(
              top: 10,
              right: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 56,
                  height: 78,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: RTCVideoView(
                    session.localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
