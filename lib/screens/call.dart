import 'package:chat_app/models/call_screen_arguments.dart';
import 'package:chat_app/services/active_call_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallScreen extends StatefulWidget {
  static const routeName = '/call';

  const CallScreen({super.key, required this.arguments});

  final CallScreenArguments arguments;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final ActiveCallSession _session = ActiveCallSession.instance;
  bool _canPopScreen = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_handleSessionChanged);
    _session.attach(widget.arguments);
  }

  @override
  void dispose() {
    _session.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    if (!mounted) {
      return;
    }

    if (!_session.hasOngoingCall) {
      _popScreen();
      return;
    }

    setState(() {});
  }

  void _popScreen() {
    if (!mounted || _canPopScreen) {
      return;
    }

    _canPopScreen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    });
  }

  Future<void> _minimizeCall() async {
    await _session.minimize();
    _popScreen();
  }

  Widget _buildRemoteSurface() {
    if (_session.hasRemoteVideo) {
      return RTCVideoView(
        _session.remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    final theme = Theme.of(context);
    final hasAvatar =
        _session.avatarUrl != null && _session.avatarUrl!.trim().isNotEmpty;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF141E30), Color(0xFF243B55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 52,
              foregroundImage: hasAvatar
                  ? NetworkImage(_session.avatarUrl!)
                  : null,
              backgroundColor: Colors.white12,
              child: hasAvatar
                  ? null
                  : Text(
                      _session.displayName.isEmpty
                          ? '?'
                          : _session.displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            Text(
              _session.displayName,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _session.statusText,
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Text(
              _session.isVideoCall ? 'Video call' : 'Voice call',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalPreview() {
    if (!_session.hasLocalVideo) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 24,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 118,
          height: 174,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(20),
          ),
          child: RTCVideoView(
            _session.localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    Color backgroundColor = const Color(0x22FFFFFF),
    Color foregroundColor = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: foregroundColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _canPopScreen,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _minimizeCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildRemoteSurface(),
              _buildLocalPreview(),
              Positioned(
                top: 18,
                left: 16,
                child: IconButton(
                  onPressed: _minimizeCall,
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        _session.statusText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _buildControlButton(
                          icon: _session.isMicEnabled
                              ? Icons.mic
                              : Icons.mic_off,
                          onTap: () => _session.toggleMicrophone(),
                        ),
                        if (_session.isVideoCall)
                          _buildControlButton(
                            icon: _session.isCameraEnabled
                                ? Icons.videocam
                                : Icons.videocam_off,
                            onTap: () => _session.toggleCamera(),
                          ),
                        if (_session.isVideoCall)
                          _buildControlButton(
                            icon: Icons.cameraswitch_outlined,
                            onTap: () => _session.switchCamera(),
                          ),
                        if (_session.showSpeakerToggle)
                          _buildControlButton(
                            icon: _session.isSpeakerOn
                                ? Icons.volume_up_rounded
                                : Icons.volume_down_rounded,
                            onTap: () => _session.toggleSpeaker(),
                          ),
                        _buildControlButton(
                          icon: Icons.call_end_rounded,
                          onTap: () => _session.endCall(),
                          backgroundColor: const Color(0xFFE53935),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
