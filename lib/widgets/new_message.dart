import 'dart:async';
import 'dart:io';

import 'package:chat_app/services/cloudinary_service.dart';
import 'package:chat_app/services/goong_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class NewMessage extends StatefulWidget {
  const NewMessage({
    super.key,
    required this.chatId,
    required this.otherUserId,
  });

  final String chatId;
  final String otherUserId;

  @override
  State<NewMessage> createState() {
    return _NewMessageState();
  }
}

class _NewMessageState extends State<NewMessage> {
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _imagePicker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final Map<String, StreamSubscription<Position>> _liveLocationSubscriptions =
      {};
  final Map<String, Timer> _liveLocationTimers = {};

  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _hasInputFocus = false;
  bool _isRecordingVoice = false;
  bool _isBusy = false;
  bool _cancelVoiceOnRelease = false;
  double? _voicePointerStartX;

  @override
  void initState() {
    super.initState();
    _messageFocusNode.addListener(() {
      if (!mounted) {
        return;
      }

      setState(() {
        _hasInputFocus = _messageFocusNode.hasFocus;
      });
    });
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

  String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }

  String _formatRecordingDuration(int totalSeconds) {
    final minutes = _twoDigits(totalSeconds ~/ 60);
    final seconds = _twoDigits(totalSeconds % 60);
    return '$minutes:$seconds';
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

  Future<({User user, String username, String? userImage})>
  _resolveSenderProfile() async {
    final user = FirebaseAuth.instance.currentUser!;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.data();
    final username =
        _readString(userData, const ['username']) ??
        (user.displayName?.trim().isNotEmpty ?? false
            ? user.displayName!.trim()
            : _emailLocalPart(user.email)) ??
        'Anonymous';
    final userImage =
        _readString(userData, const ['image_url', 'imageUrl', 'userImage']) ??
        (user.photoURL?.trim().isNotEmpty ?? false
            ? user.photoURL!.trim()
            : null);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'email': user.email,
      'username': username,
      if (userImage != null) 'image_url': userImage,
    }, SetOptions(merge: true));

    return (user: user, username: username, userImage: userImage);
  }

  Future<DocumentReference<Map<String, dynamic>>> _sendChatMessage({
    required String type,
    required String previewText,
    required Map<String, dynamic> extraData,
  }) async {
    final sender = await _resolveSenderProfile();
    final participants = [sender.user.uid, widget.otherUserId]..sort();

    await FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.chatId)
        .set({
          'participants': participants,
          'updatedAt': Timestamp.now(),
          'lastMessage': previewText,
          'lastMessageSenderId': sender.user.uid,
        }, SetOptions(merge: true));

    return FirebaseFirestore.instance
        .collection('private_chats')
        .doc(widget.chatId)
        .collection('messages')
        .add({
          'type': type,
          'text': previewText,
          'createdAt': Timestamp.now(),
          'userId': sender.user.uid,
          'username': sender.username,
          'userImage': sender.userImage ?? '',
          'recipientId': widget.otherUserId,
          'readBy': [sender.user.uid],
          'deletedFor': <String>[],
          'deletedForEveryone': false,
          'reactions': <String, String>{},
          ...extraData,
        });
  }

  Future<void> _submitMessage() async {
    final enteredMessage = _messageController.text.trim();
    if (enteredMessage.isEmpty || _isBusy) {
      return;
    }

    _messageFocusNode.unfocus();
    _messageController.clear();
    if (mounted) {
      setState(() {});
    }

    await _sendChatMessage(
      type: 'text',
      previewText: enteredMessage,
      extraData: const {},
    );
  }

  Future<void> _sendImage(File imageFile) async {
    setState(() {
      _isBusy = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final mediaUrl = await CloudinaryService.uploadImage(
        imageFile,
        publicId: '${user.uid}_${DateTime.now().millisecondsSinceEpoch}',
        folder: 'chat_images',
      );
      await _sendChatMessage(
        type: 'image',
        previewText: 'Đã gửi một ảnh',
        extraData: {'mediaUrl': mediaUrl},
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _sendVideo(File videoFile) async {
    setState(() {
      _isBusy = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final mediaUrl = await CloudinaryService.uploadMedia(
        videoFile,
        publicId: '${user.uid}_${DateTime.now().millisecondsSinceEpoch}',
        folder: 'chat_videos',
      );
      await _sendChatMessage(
        type: 'video',
        previewText: 'Đã gửi một video',
        extraData: {'mediaUrl': mediaUrl},
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _sendVoiceMessage(File audioFile, int durationMs) async {
    setState(() {
      _isBusy = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final mediaUrl = await CloudinaryService.uploadMedia(
        audioFile,
        publicId: '${user.uid}_${DateTime.now().millisecondsSinceEpoch}',
        folder: 'chat_voice',
      );
      await _sendChatMessage(
        type: 'voice',
        previewText: 'Đã gửi một tin nhắn thoại',
        extraData: {'mediaUrl': mediaUrl, 'durationMs': durationMs},
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<Position> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Vui lòng bật dịch vụ vị trí trên thiết bị.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Ứng dụng chưa được cấp quyền vị trí.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );
  }

  Future<void> _sendCurrentLocation() async {
    setState(() {
      _isBusy = true;
    });

    try {
      final position = await _getCurrentPosition();
      final details = await GoongService.reverseGeocode(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await _sendChatMessage(
        type: 'location',
        previewText: 'Đã chia sẻ vị trí',
        extraData: {
          'locationLatitude': details.latitude,
          'locationLongitude': details.longitude,
          'locationAddress': details.address,
          'locationPreviewUrl': details.staticMapUrl,
          'locationMapsUrl': details.mapsUrl,
          if (details.placeId != null) 'locationPlaceId': details.placeId,
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _shareLiveLocationForOneHour() async {
    setState(() {
      _isBusy = true;
    });

    try {
      final position = await _getCurrentPosition();
      final details = await GoongService.reverseGeocode(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final liveUntil = Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 1)),
      );
      final messageRef = await _sendChatMessage(
        type: 'live_location',
        previewText: 'Đã chia sẻ vị trí trực tiếp',
        extraData: {
          'locationLatitude': details.latitude,
          'locationLongitude': details.longitude,
          'locationAddress': details.address,
          'locationPreviewUrl': details.staticMapUrl,
          'locationMapsUrl': details.mapsUrl,
          if (details.placeId != null) 'locationPlaceId': details.placeId,
          'liveUntil': liveUntil,
        },
      );
      _startLiveLocationUpdates(
        messageId: messageRef.id,
        liveUntil: liveUntil.toDate(),
      );
      _showSnackBar('Đang chia sẻ vị trí trực tiếp trong 1 tiếng.');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _startLiveLocationUpdates({
    required String messageId,
    required DateTime liveUntil,
  }) {
    _liveLocationSubscriptions[messageId]?.cancel();
    _liveLocationTimers[messageId]?.cancel();

    final stream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 15,
      ),
    );

    _liveLocationSubscriptions[messageId] = stream.listen((position) async {
      if (DateTime.now().isAfter(liveUntil)) {
        await _stopLiveLocationUpdates(messageId);
        return;
      }

      await FirebaseFirestore.instance
          .collection('private_chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .update({
            'locationLatitude': position.latitude,
            'locationLongitude': position.longitude,
            'locationPreviewUrl': GoongService.buildStaticMapUrl(
              latitude: position.latitude,
              longitude: position.longitude,
            ),
            'locationMapsUrl': GoongService.buildMapsUrl(
              latitude: position.latitude,
              longitude: position.longitude,
            ),
            'lastLocationUpdatedAt': Timestamp.now(),
          });
    });

    _liveLocationTimers[messageId] = Timer(
      liveUntil.difference(DateTime.now()),
      () => _stopLiveLocationUpdates(messageId),
    );
  }

  Future<void> _stopLiveLocationUpdates(String messageId) async {
    await _liveLocationSubscriptions.remove(messageId)?.cancel();
    _liveLocationTimers.remove(messageId)?.cancel();
  }

  Future<void> _sendPickedImage(ImageSource source) async {
    final pickedFile = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (pickedFile == null) {
      return;
    }

    await _sendImage(File(pickedFile.path));
  }

  bool _isVideoFile(XFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.startsWith('video/')) {
      return true;
    }

    final path = file.path.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.m4v') ||
        path.endsWith('.avi') ||
        path.endsWith('.mkv') ||
        path.endsWith('.webm') ||
        path.endsWith('.3gp');
  }

  Future<void> _sendPickedGalleryMedia() async {
    final pickedFile = await _imagePicker.pickMedia();
    if (pickedFile == null) {
      return;
    }

    final mediaFile = File(pickedFile.path);
    if (_isVideoFile(pickedFile)) {
      await _sendVideo(mediaFile);
      return;
    }

    await _sendImage(mediaFile);
  }

  Future<void> _startVoiceRecording() async {
    if (_isBusy || _isRecordingVoice) {
      return;
    }

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Cấp quyền microphone.');
    }

    final tempDir = await getTemporaryDirectory();
    final recordingPath =
        '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _audioRecorder.start(const RecordConfig(), path: recordingPath);
    if (!mounted) {
      return;
    }

    setState(() {
      _isRecordingVoice = true;
      _recordingSeconds = 0;
      _cancelVoiceOnRelease = false;
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recordingSeconds += 1;
      });
    });
  }

  Future<void> _stopVoiceRecordingAndSend() async {
    if (!_isRecordingVoice) {
      return;
    }

    final recordedPath = await _audioRecorder.stop();
    _recordingTimer?.cancel();
    final durationMs = _recordingSeconds * 1000;
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingSeconds = 0;
        _cancelVoiceOnRelease = false;
        _voicePointerStartX = null;
      });
    }

    if (recordedPath == null || durationMs <= 0) {
      return;
    }

    await _sendVoiceMessage(File(recordedPath), durationMs);
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice) {
      return;
    }

    final recordedPath = await _audioRecorder.stop();
    _recordingTimer?.cancel();

    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingSeconds = 0;
        _cancelVoiceOnRelease = false;
        _voicePointerStartX = null;
      });
    }

    if (recordedPath != null) {
      final file = File(recordedPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _showPlusActions() async {
    _messageFocusNode.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        Future<void> handleAction(Future<void> Function() action) async {
          Navigator.of(sheetContext).pop();
          try {
            await action();
          } catch (error) {
            _showSnackBar(error.toString());
          }
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Gửi vị trí hiện tại'),
                onTap: () => handleAction(_sendCurrentLocation),
              ),
              ListTile(
                leading: const Icon(Icons.share_location_outlined),
                title: const Text('Chia sẻ vị trí 1 tiếng'),
                onTap: () => handleAction(_shareLiveLocationForOneHour),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    for (final subscription in _liveLocationSubscriptions.values) {
      subscription.cancel();
    }
    for (final timer in _liveLocationTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTextEmpty = _messageController.text.trim().isEmpty;
    final theme = Theme.of(context);
    const composerColor = Color(0xFFF0EEF5);
    final showQuickActions = !_hasInputFocus && isTextEmpty;

    Widget buildComposerButton({
      required IconData icon,
      required VoidCallback? onPressed,
      Color? color,
    }) {
      return IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: color ?? theme.colorScheme.primary,
        iconSize: 30,
        splashRadius: 22,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );
    }

    Widget buildHoldToRecordButton() {
      final color = _cancelVoiceOnRelease
          ? Colors.orangeAccent
          : _isRecordingVoice
          ? Colors.redAccent
          : theme.colorScheme.primary;

      return Listener(
        onPointerDown: _isBusy
            ? null
            : (event) async {
                try {
                  _voicePointerStartX = event.position.dx;
                  if (mounted) {
                    setState(() {
                      _cancelVoiceOnRelease = false;
                    });
                  }
                  await _startVoiceRecording();
                } catch (error) {
                  _showSnackBar(error.toString());
                }
              },
        onPointerMove: _isBusy
            ? null
            : (event) {
                if (!_isRecordingVoice || _voicePointerStartX == null) {
                  return;
                }

                final shouldCancel =
                    (_voicePointerStartX! - event.position.dx) > 90;
                if (shouldCancel == _cancelVoiceOnRelease || !mounted) {
                  return;
                }

                setState(() {
                  _cancelVoiceOnRelease = shouldCancel;
                });
              },
        onPointerUp: _isBusy
            ? null
            : (_) async {
                try {
                  _voicePointerStartX = null;
                  if (_cancelVoiceOnRelease) {
                    await _cancelVoiceRecording();
                    _showSnackBar('Đã hủy voice.');
                    return;
                  }

                  await _stopVoiceRecordingAndSend();
                } catch (error) {
                  _showSnackBar(error.toString());
                }
              },
        onPointerCancel: _isBusy
            ? null
            : (_) async {
                try {
                  _voicePointerStartX = null;
                  await _cancelVoiceRecording();
                } catch (error) {
                  _showSnackBar(error.toString());
                }
              },
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            _isRecordingVoice ? Icons.mic_rounded : Icons.mic_none_rounded,
            color: color,
            size: 30,
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            buildComposerButton(
              onPressed: (_isBusy || _isRecordingVoice)
                  ? null
                  : _showPlusActions,
              icon: Icons.add_circle_outline_rounded,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return SizeTransition(
                  sizeFactor: animation,
                  axis: Axis.horizontal,
                  axisAlignment: -1,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: showQuickActions
                  ? Row(
                      key: const ValueKey('quick-actions-visible'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        buildComposerButton(
                          onPressed: (_isBusy || _isRecordingVoice)
                              ? null
                              : () async {
                                  try {
                                    await _sendPickedImage(ImageSource.camera);
                                  } catch (error) {
                                    _showSnackBar(error.toString());
                                  }
                                },
                          icon: Icons.camera_alt_outlined,
                        ),
                        buildComposerButton(
                          onPressed: (_isBusy || _isRecordingVoice)
                              ? null
                              : () async {
                                  try {
                                    await _sendPickedGalleryMedia();
                                  } catch (error) {
                                    _showSnackBar(error.toString());
                                  }
                                },
                          icon: Icons.image_outlined,
                        ),
                        buildHoldToRecordButton(),
                      ],
                    )
                  : const SizedBox(
                      key: ValueKey('quick-actions-hidden'),
                      width: 0,
                    ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: composerColor,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: TextField(
                  focusNode: _messageFocusNode,
                  controller: _messageController,
                  onChanged: (_) => setState(() {}),
                  readOnly: _isRecordingVoice || _isBusy,
                  textCapitalization: TextCapitalization.sentences,
                  autocorrect: true,
                  enableSuggestions: true,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: _isRecordingVoice
                        ? _cancelVoiceOnRelease
                              ? 'Thả tay để hủy voice'
                              : 'Kéo sang trái để hủy • ${_formatRecordingDuration(_recordingSeconds)}'
                        : 'Nhắn tin',
                    hintMaxLines: 1,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _isBusy
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                : buildComposerButton(
                    onPressed: isTextEmpty ? null : _submitMessage,
                    icon: Icons.send_rounded,
                    color: isTextEmpty
                        ? Colors.grey.shade400
                        : theme.colorScheme.primary,
                  ),
          ],
        ),
      ),
    );
  }
}
