import 'dart:async';

import 'package:chat_app/models/call_screen_arguments.dart';
import 'package:chat_app/navigation/app_navigator.dart';
import 'package:chat_app/services/call_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class ActiveCallSession extends ChangeNotifier {
  ActiveCallSession._();

  static final ActiveCallSession instance = ActiveCallSession._();

  final CallService _callService = CallService.instance;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  final Set<String> _handledCandidateIds = <String>{};
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _candidateSubscription;
  Timer? _ringTimeoutTimer;

  CallScreenArguments? _currentArguments;
  String? _callId;
  String _displayName = 'User';
  String? _avatarUrl;
  String _statusText = 'Starting call...';
  bool _isVideoCall = false;
  bool _isMicEnabled = true;
  bool _isCameraEnabled = true;
  bool _isSpeakerOn = true;
  bool _isCallConnected = false;
  bool _hasRemoteDescription = false;
  bool _isEnding = false;
  bool _renderersReady = false;
  bool _isMinimized = false;
  bool _hasOngoingCall = false;
  bool _notificationScheduled = false;
  int _setupToken = 0;

  CallScreenArguments? get currentArguments => _currentArguments;
  String get displayName => _displayName;
  String? get avatarUrl => _avatarUrl;
  String get statusText => _statusText;
  bool get isVideoCall => _isVideoCall;
  bool get isMicEnabled => _isMicEnabled;
  bool get isCameraEnabled => _isCameraEnabled;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isCallConnected => _isCallConnected;
  bool get isEnding => _isEnding;
  bool get isMinimized => _isMinimized;
  bool get hasOngoingCall => _hasOngoingCall;
  bool get showSpeakerToggle => !_isVideoCall;

  bool get hasRemoteVideo =>
      _isVideoCall &&
      _remoteStream != null &&
      _remoteStream!.getVideoTracks().isNotEmpty;

  bool get hasLocalVideo =>
      _isVideoCall &&
      _localStream != null &&
      _localStream!.getVideoTracks().isNotEmpty;

  Future<void> attach(CallScreenArguments arguments) async {
    if (_hasOngoingCall && _isSameSession(arguments)) {
      _isMinimized = false;
      _notifyListenersSafely();
      return;
    }

    if (_hasOngoingCall) {
      await endCall();
    }

    _currentArguments = arguments;
    _callId = arguments.callId;
    _displayName = arguments.displayName?.trim().isNotEmpty == true
        ? arguments.displayName!.trim()
        : 'User';
    _avatarUrl = arguments.avatarUrl;
    _statusText = 'Starting call...';
    _isVideoCall = arguments.isVideo;
    _isMicEnabled = true;
    _isCameraEnabled = arguments.isVideo;
    _isSpeakerOn = arguments.isVideo;
    _isCallConnected = false;
    _hasRemoteDescription = false;
    _isEnding = false;
    _isMinimized = false;
    _hasOngoingCall = true;
    _handledCandidateIds.clear();
    _pendingRemoteCandidates.clear();
    _notifyListenersSafely();

    final setupToken = ++_setupToken;
    await _initializeCall(arguments, setupToken);
  }

  Future<void> minimize() async {
    if (!_hasOngoingCall) {
      return;
    }

    _isMinimized = true;
    _notifyListenersSafely();
  }

  Future<void> toggleMicrophone() async {
    final audioTrack = _firstAudioTrack();
    if (audioTrack == null) {
      return;
    }

    final nextValue = !_isMicEnabled;
    audioTrack.enabled = nextValue;
    _isMicEnabled = nextValue;
    _notifyListenersSafely();
  }

  Future<void> toggleCamera() async {
    final videoTrack = _firstVideoTrack();
    if (videoTrack == null) {
      return;
    }

    final nextValue = !_isCameraEnabled;
    videoTrack.enabled = nextValue;
    _isCameraEnabled = nextValue;
    _notifyListenersSafely();
  }

  Future<void> switchCamera() async {
    final videoTrack = _firstVideoTrack();
    if (videoTrack == null) {
      return;
    }

    await Helper.switchCamera(videoTrack);
    _notifyListenersSafely();
  }

  Future<void> toggleSpeaker() async {
    if (_isVideoCall) {
      return;
    }

    final nextValue = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(nextValue);
    _isSpeakerOn = nextValue;
    _notifyListenersSafely();
  }

  Future<void> endCall({String status = 'ended'}) async {
    if (!_hasOngoingCall || _isEnding) {
      return;
    }

    final resolvedStatus = _resolveEndStatus(status);
    _isEnding = true;
    _statusText = resolvedStatus == 'missed'
        ? 'Cuộc gọi bị nhỡ'
        : 'Kết thúc cuộc gọi...';
    _notifyListenersSafely();

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final callId = _callId;
    if (currentUserId != null && callId != null) {
      unawaited(
        _callService
            .endCall(callId, endedBy: currentUserId, status: resolvedStatus)
            .then((_) {
              if (_shouldWriteSummaryForStatus(resolvedStatus)) {
                return _callService.writeCallSummaryMessageIfNeeded(callId);
              }
            })
            .catchError((error, stackTrace) {
              debugPrint('Failed to update ended call state: $error');
              debugPrintStack(stackTrace: stackTrace);
            }),
      );
      if (resolvedStatus == 'missed') {
        _showGlobalCallNotice('Cuộc gọi bị nhỡ');
      }
    }

    await _cleanupSession();
  }

  Future<void> _initializeCall(
    CallScreenArguments arguments,
    int setupToken,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (_isSetupActive(setupToken)) {
        await _cleanupSession();
      }
      return;
    }

    if (!arguments.isOutgoing) {
      final callId = _callId;
      if (callId == null) {
        if (_isSetupActive(setupToken)) {
          await _cleanupSession();
        }
        return;
      }

      final snapshot = await _callService.getCall(callId);
      if (!_isSetupActive(setupToken)) {
        return;
      }
      final callData = snapshot.data();
      if (callData == null) {
        if (_isSetupActive(setupToken)) {
          await _cleanupSession();
        }
        return;
      }
      _applyCallMetadata(callData, currentUser.uid);
    }

    final hasPermission = await _requestPermissions();
    if (!_isSetupActive(setupToken)) {
      return;
    }
    if (!hasPermission) {
      await endCall(status: 'failed');
      return;
    }

    if (!_renderersReady) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersReady = true;
    }
    if (!_isSetupActive(setupToken)) {
      return;
    }

    try {
      await Helper.setSpeakerphoneOn(_isVideoCall);
    } catch (_) {}

    final openedLocalMedia = await _openLocalMedia(setupToken);
    if (!openedLocalMedia || !_isSetupActive(setupToken)) {
      return;
    }

    final createdPeerConnection = await _createPeerConnection(
      arguments,
      setupToken,
    );
    if (!createdPeerConnection || !_isSetupActive(setupToken)) {
      return;
    }

    if (arguments.isOutgoing) {
      await _startOutgoingCall(currentUser.uid, setupToken);
      if (!_isSetupActive(setupToken)) {
        return;
      }
    } else {
      _statusText = 'Joining call...';
      _notifyListenersSafely();
    }

    _listenToCallDocument(currentUser.uid, arguments);
    _listenToRemoteCandidates(arguments);
    _notifyListenersSafely();
  }

  Future<bool> _requestPermissions() async {
    final microphoneStatus = await Permission.microphone.request();
    if (!microphoneStatus.isGranted) {
      return false;
    }

    if (!_isVideoCall) {
      return true;
    }

    final cameraStatus = await Permission.camera.request();
    return cameraStatus.isGranted;
  }

  Future<bool> _openLocalMedia(int setupToken) async {
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': _isVideoCall
          ? <String, dynamic>{
              'facingMode': 'user',
              'width': 1280,
              'height': 720,
              'frameRate': 30,
            }
          : false,
    };

    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (!_isSetupActive(setupToken)) {
      for (final track in stream.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
      return false;
    }

    _localStream = stream;
    if (_isVideoCall) {
      localRenderer.srcObject = _localStream;
    }
    return true;
  }

  Future<bool> _createPeerConnection(
    CallScreenArguments arguments,
    int setupToken,
  ) async {
    final peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });
    if (!_isSetupActive(setupToken)) {
      try {
        await peerConnection.close();
      } catch (_) {}
      try {
        await peerConnection.dispose();
      } catch (_) {}
      return false;
    }
    _peerConnection = peerConnection;

    final localStream = _localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        await peerConnection.addTrack(track, localStream);
      }
    }

    peerConnection.onIceCandidate = (candidate) async {
      final callId = _callId;
      if (callId == null || candidate.candidate == null) {
        return;
      }

      await _callService.addIceCandidate(
        callId: callId,
        fromCaller: arguments.isOutgoing,
        candidate: candidate,
      );
    };

    peerConnection.onTrack = (event) async {
      if (event.streams.isEmpty) {
        return;
      }

      _remoteStream = event.streams.first;
      remoteRenderer.srcObject = _remoteStream;

      if (!_isCallConnected && _callId != null) {
        _isCallConnected = true;
        _statusText = 'Connected';
        _notifyListenersSafely();
        await _callService.markActive(_callId!);
      } else {
        _notifyListenersSafely();
      }
    };

    peerConnection.onConnectionState = (state) async {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          if (!_isCallConnected && _callId != null) {
            _isCallConnected = true;
            _statusText = 'Connected';
            _notifyListenersSafely();
            await _callService.markActive(_callId!);
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _statusText = 'Connecting...';
          _notifyListenersSafely();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _statusText = 'Connection lost';
          _notifyListenersSafely();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          break;
      }
    };
    return true;
  }

  Future<void> _startOutgoingCall(String currentUserId, int setupToken) async {
    final currentArguments = _currentArguments;
    if (currentArguments == null || !_isSetupActive(setupToken)) {
      return;
    }

    final identity = await _loadCurrentUserIdentity(currentUserId);
    if (!_isSetupActive(setupToken)) {
      return;
    }

    final callRef = await _callService.createOutgoingCall(
      chatId: currentArguments.chatId,
      callerId: currentUserId,
      calleeId: currentArguments.otherUserId,
      callerName: identity.$1,
      callerImage: identity.$2,
      isVideo: _isVideoCall,
    );
    if (!_isSetupActive(setupToken)) {
      await _abortStaleOutgoingCall(callRef.id, currentUserId);
      return;
    }

    _callId = callRef.id;
    _currentArguments = _currentArguments?.copyWith(
      callId: callRef.id,
      displayName: _displayName,
      avatarUrl: _avatarUrl,
    );
    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      await _abortStaleOutgoingCall(callRef.id, currentUserId);
      return;
    }

    final offer = await peerConnection.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': _isVideoCall ? 1 : 0,
    });
    if (!_isSetupActive(setupToken) || _peerConnection != peerConnection) {
      await _abortStaleOutgoingCall(callRef.id, currentUserId);
      return;
    }

    await peerConnection.setLocalDescription(offer);
    if (!_isSetupActive(setupToken) || _peerConnection != peerConnection) {
      await _abortStaleOutgoingCall(callRef.id, currentUserId);
      return;
    }

    await _callService.setOffer(callRef.id, offer);
    if (!_isSetupActive(setupToken)) {
      await _abortStaleOutgoingCall(callRef.id, currentUserId);
      return;
    }

    _statusText = _isVideoCall ? 'Calling video...' : 'Calling voice...';
    _notifyListenersSafely();

    _ringTimeoutTimer = Timer(const Duration(seconds: 30), () async {
      final callId = _callId;
      if (callId == null || _isCallConnected || _isEnding) {
        return;
      }

      final snapshot = await _callService.getCall(callId);
      final callData = snapshot.data();
      if (callData == null || callData['status'] != 'ringing') {
        return;
      }

      await _callService.endCall(
        callId,
        endedBy: currentUserId,
        status: 'missed',
      );
    });
  }

  void _applyCallMetadata(Map<String, dynamic> callData, String currentUserId) {
    _isVideoCall = callData['isVideo'] == true;
    _isCameraEnabled = _isVideoCall;

    final isCurrentUserCaller = callData['callerId'] == currentUserId;
    final name = isCurrentUserCaller
        ? _readString(callData, const ['calleeName'])
        : _readString(callData, const ['callerName']);
    final image = isCurrentUserCaller
        ? _readString(callData, const ['calleeImage'])
        : _readString(callData, const ['callerImage']);

    _displayName = name ?? _displayName;
    _avatarUrl = image ?? _avatarUrl;
    _currentArguments = _currentArguments?.copyWith(
      displayName: _displayName,
      avatarUrl: _avatarUrl,
      isVideo: _isVideoCall,
      callId: _callId,
    );
  }

  Future<(String, String?)> _loadCurrentUserIdentity(String userId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    final userData = userSnapshot.data();

    final username =
        _readString(userData, const ['username']) ??
        (currentUser?.displayName?.trim().isNotEmpty ?? false
            ? currentUser!.displayName!.trim()
            : _emailLocalPart(currentUser?.email)) ??
        'User';
    final imageUrl =
        _readString(userData, const ['image_url', 'imageUrl', 'userImage']) ??
        (currentUser?.photoURL?.trim().isNotEmpty ?? false
            ? currentUser!.photoURL!.trim()
            : null);

    return (username, imageUrl);
  }

  void _listenToCallDocument(
    String currentUserId,
    CallScreenArguments arguments,
  ) {
    final callId = _callId;
    if (callId == null) {
      return;
    }

    _callSubscription = _callService.watchCall(callId).listen((snapshot) async {
      final callData = snapshot.data();
      if (callData == null) {
        await _cleanupSession();
        return;
      }

      _applyCallMetadata(callData, currentUserId);

      if (!arguments.isOutgoing && !_hasRemoteDescription) {
        final offer = _callService.sessionDescriptionFromData(
          callData['offer'],
        );
        if (offer != null) {
          final peerConnection = _peerConnection;
          if (peerConnection == null) {
            return;
          }
          await peerConnection.setRemoteDescription(offer);
          if (_peerConnection != peerConnection) {
            return;
          }
          _hasRemoteDescription = true;
          await _flushPendingRemoteCandidates();
          final answer = await peerConnection.createAnswer({
            'offerToReceiveAudio': 1,
            'offerToReceiveVideo': _isVideoCall ? 1 : 0,
          });
          if (_peerConnection != peerConnection) {
            return;
          }
          await peerConnection.setLocalDescription(answer);
          await _callService.setAnswer(callId, answer);
          _statusText = 'Connecting...';
          _notifyListenersSafely();
        }
      }

      if (arguments.isOutgoing && !_hasRemoteDescription) {
        final answer = _callService.sessionDescriptionFromData(
          callData['answer'],
        );
        if (answer != null) {
          final peerConnection = _peerConnection;
          if (peerConnection == null) {
            return;
          }
          await peerConnection.setRemoteDescription(answer);
          if (_peerConnection != peerConnection) {
            return;
          }
          _hasRemoteDescription = true;
          await _flushPendingRemoteCandidates();
          _statusText = 'Connecting...';
          _notifyListenersSafely();
        }
      }

      final status = _readString(callData, const ['status']) ?? 'ringing';
      if (_isTerminalStatus(status)) {
        if (status == 'ended' || status == 'declined' || status == 'missed') {
          unawaited(
            _callService.writeCallSummaryMessageIfNeeded(callId).catchError((
              error,
              stackTrace,
            ) {
              debugPrint('Failed to ensure call summary message: $error');
              debugPrintStack(stackTrace: stackTrace);
            }),
          );
        }
        final terminalLabel = _labelForTerminalStatus(status);
        _statusText = terminalLabel;
        _notifyListenersSafely();
        if (status == 'declined' || status == 'missed') {
          _showGlobalCallNotice(terminalLabel);
        }
        await _cleanupSession();
        return;
      }

      if (!_isCallConnected) {
        _statusText = _labelForStatus(arguments, status);
        _notifyListenersSafely();
      }
    });
  }

  void _listenToRemoteCandidates(CallScreenArguments arguments) {
    final callId = _callId;
    if (callId == null) {
      return;
    }

    final remoteCandidateStream = arguments.isOutgoing
        ? _callService.answerCandidates(callId).snapshots()
        : _callService.offerCandidates(callId).snapshots();

    _candidateSubscription = remoteCandidateStream.listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) {
          continue;
        }
        if (_handledCandidateIds.contains(change.doc.id)) {
          continue;
        }

        _handledCandidateIds.add(change.doc.id);
        final candidate = _callService.candidateFromData(change.doc.data());
        if (candidate == null) {
          continue;
        }

        if (!_hasRemoteDescription) {
          _pendingRemoteCandidates.add(candidate);
          continue;
        }

        await _peerConnection?.addCandidate(candidate);
      }
    });
  }

  Future<void> _flushPendingRemoteCandidates() async {
    if (!_hasRemoteDescription || _pendingRemoteCandidates.isEmpty) {
      return;
    }

    for (final candidate in List<RTCIceCandidate>.from(
      _pendingRemoteCandidates,
    )) {
      await _peerConnection?.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  bool _isTerminalStatus(String status) {
    return status == 'ended' ||
        status == 'declined' ||
        status == 'missed' ||
        status == 'failed';
  }

  bool _shouldWriteSummaryForStatus(String status) {
    return status == 'ended' || status == 'declined' || status == 'missed';
  }

  String _labelForStatus(CallScreenArguments arguments, String status) {
    switch (status) {
      case 'active':
        return 'Connected';
      case 'connecting':
        return 'Connecting...';
      case 'ringing':
        return arguments.isOutgoing ? 'Ringing...' : 'Incoming call';
      default:
        return _statusText;
    }
  }

  String _labelForTerminalStatus(String status) {
    switch (status) {
      case 'declined':
        return 'Cuộc gọi bị từ chối';
      case 'missed':
        return 'Cuộc gọi bị nhỡ';
      case 'failed':
        return 'Không thể thực hiện cuộc gọi';
      case 'ended':
      default:
        return 'Cuộc gọi đã kết thúc';
    }
  }

  MediaStreamTrack? _firstAudioTrack() {
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    return tracks.isEmpty ? null : tracks.first;
  }

  MediaStreamTrack? _firstVideoTrack() {
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    return tracks.isEmpty ? null : tracks.first;
  }

  Future<void> _cleanupSession() async {
    _setupToken++;
    _callSubscription?.cancel();
    _callSubscription = null;
    _candidateSubscription?.cancel();
    _candidateSubscription = null;
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;

    try {
      await _peerConnection?.close();
    } catch (_) {}
    try {
      await _peerConnection?.dispose();
    } catch (_) {}
    _peerConnection = null;

    final localStream = _localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }
      try {
        await localStream.dispose();
      } catch (_) {}
    }
    _localStream = null;

    final remoteStream = _remoteStream;
    if (remoteStream != null) {
      try {
        await remoteStream.dispose();
      } catch (_) {}
    }
    _remoteStream = null;

    if (_renderersReady) {
      try {
        localRenderer.srcObject = null;
      } catch (_) {}
      try {
        remoteRenderer.srcObject = null;
      } catch (_) {}
    }

    _currentArguments = null;
    _callId = null;
    _displayName = 'User';
    _avatarUrl = null;
    _statusText = 'Call ended';
    _isVideoCall = false;
    _isMicEnabled = true;
    _isCameraEnabled = true;
    _isSpeakerOn = true;
    _isCallConnected = false;
    _hasRemoteDescription = false;
    _isEnding = false;
    _isMinimized = false;
    _hasOngoingCall = false;
    _handledCandidateIds.clear();
    _pendingRemoteCandidates.clear();
    _notifyListenersSafely();
  }

  bool _isSetupActive(int setupToken) {
    return setupToken == _setupToken && _hasOngoingCall && !_isEnding;
  }

  String _resolveEndStatus(String status) {
    if (status != 'ended') {
      return status;
    }

    final isOutgoing = _currentArguments?.isOutgoing == true;
    if (isOutgoing && !_isCallConnected) {
      return 'missed';
    }

    return status;
  }

  Future<void> _abortStaleOutgoingCall(
    String callId,
    String currentUserId,
  ) async {
    try {
      await _callService.endCall(callId, endedBy: currentUserId);
    } catch (_) {}
  }

  bool _isSameSession(CallScreenArguments arguments) {
    final currentArguments = _currentArguments;
    if (currentArguments == null) {
      return false;
    }

    if (_callId != null && arguments.callId != null) {
      return _callId == arguments.callId;
    }

    return currentArguments.chatId == arguments.chatId &&
        currentArguments.otherUserId == arguments.otherUserId &&
        currentArguments.isOutgoing == arguments.isOutgoing &&
        currentArguments.isVideo == arguments.isVideo;
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

  String? _emailLocalPart(String? email) {
    if (email == null || email.trim().isEmpty || !email.contains('@')) {
      return null;
    }

    final localPart = email.split('@').first.trim();
    return localPart.isEmpty ? null : localPart;
  }

  void _notifyListenersSafely() {
    if (!hasListeners) {
      return;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
      return;
    }

    if (_notificationScheduled) {
      return;
    }

    _notificationScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  void _showGlobalCallNotice(String message) {
    final messenger = AppNavigator.scaffoldMessengerKey.currentState;
    if (messenger == null || message.trim().isEmpty) {
      return;
    }

    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
