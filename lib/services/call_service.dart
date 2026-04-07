import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallService {
  CallService._();

  static final CallService instance = CallService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection('calls');

  DocumentReference<Map<String, dynamic>> callDoc(String callId) =>
      _calls.doc(callId);

  CollectionReference<Map<String, dynamic>> offerCandidates(String callId) =>
      callDoc(callId).collection('offerCandidates');

  CollectionReference<Map<String, dynamic>> answerCandidates(String callId) =>
      callDoc(callId).collection('answerCandidates');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchIncomingCalls(
    String userId,
  ) {
    return _calls.where('calleeId', isEqualTo: userId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCall(String callId) {
    return callDoc(callId).snapshots();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getCall(String callId) {
    return callDoc(callId).get();
  }

  Future<DocumentReference<Map<String, dynamic>>> createOutgoingCall({
    required String chatId,
    required String callerId,
    required String calleeId,
    required String callerName,
    required bool isVideo,
    String? callerImage,
  }) {
    return _calls.add({
      'chatId': chatId,
      'participants': [callerId, calleeId],
      'callerId': callerId,
      'calleeId': calleeId,
      'callerName': callerName,
      if (callerImage != null && callerImage.trim().isNotEmpty)
        'callerImage': callerImage.trim(),
      'isVideo': isVideo,
      'status': 'ringing',
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> setOffer(String callId, RTCSessionDescription offer) {
    return callDoc(callId).set({
      'offer': sessionDescriptionToMap(offer),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> setAnswer(String callId, RTCSessionDescription answer) {
    return callDoc(callId).set({
      'answer': sessionDescriptionToMap(answer),
      'status': 'connecting',
      'acceptedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> addIceCandidate({
    required String callId,
    required bool fromCaller,
    required RTCIceCandidate candidate,
  }) {
    final targetCollection = fromCaller
        ? offerCandidates(callId)
        : answerCandidates(callId);
    return targetCollection.add({
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
      'createdAt': Timestamp.now(),
    });
  }

  Future<void> markActive(String callId) {
    return callDoc(callId).set({
      'status': 'active',
      'connectedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> declineCall(String callId, String declinedBy) {
    return callDoc(callId).set({
      'status': 'declined',
      'declinedBy': declinedBy,
      'endedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> endCall(
    String callId, {
    required String endedBy,
    String status = 'ended',
  }) {
    return callDoc(callId).set({
      'status': status,
      'endedBy': endedBy,
      'endedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> writeCallSummaryMessageIfNeeded(String callId) async {
    final callRef = callDoc(callId);

    await _firestore.runTransaction((transaction) async {
      final callSnapshot = await transaction.get(callRef);
      final callData = callSnapshot.data();
      if (callData == null) {
        return;
      }

      final status = _readString(callData, const ['status']);
      if (!_shouldWriteSummaryForStatus(status) ||
          callData['summaryMessageId'] != null) {
        return;
      }

      final chatId = callData['chatId'];
      final callerId = callData['callerId'];
      final calleeId = callData['calleeId'];
      final endedAt = callData['endedAt'];
      final connectedAt = callData['connectedAt'];
      final isVideo = callData['isVideo'] == true;

      if (chatId is! String ||
          callerId is! String ||
          calleeId is! String ||
          status == null ||
          endedAt is! Timestamp) {
        return;
      }

      final senderId = callerId;
      final recipientId = calleeId;
      final userSnapshot = await transaction.get(
        _firestore.collection('users').doc(senderId),
      );
      final userData = userSnapshot.data();

      final username = _readString(userData, const ['username']) ?? 'User';
      final userImage = _readString(userData, const [
        'image_url',
        'imageUrl',
        'userImage',
      ]);

      var durationSeconds = 0;
      if (status == 'ended' && connectedAt is Timestamp) {
        final diff =
            endedAt.millisecondsSinceEpoch - connectedAt.millisecondsSinceEpoch;
        if (diff > 0) {
          durationSeconds = diff ~/ 1000;
        }
      }

      final summaryText = _summaryTextForStatus(
        status: status,
        isVideo: isVideo,
        durationSeconds: durationSeconds,
      );
      final messageRef = _firestore
          .collection('private_chats')
          .doc(chatId)
          .collection('messages')
          .doc();

      transaction.set(messageRef, {
        'type': 'call_log',
        'text': summaryText,
        'createdAt': endedAt,
        'endedAt': endedAt,
        'durationSeconds': durationSeconds,
        'callMode': isVideo ? 'video' : 'voice',
        'callStatus': status,
        'userId': senderId,
        'username': username,
        'userImage': userImage ?? '',
        'recipientId': recipientId,
        'readBy': [senderId],
        'deletedFor': <String>[],
        'deletedForEveryone': false,
        'reactions': <String, String>{},
      });

      transaction.set(
        _firestore.collection('private_chats').doc(chatId),
        {
          'updatedAt': endedAt,
          'lastMessage': summaryText,
          'lastMessageSenderId': senderId,
        },
        SetOptions(merge: true),
      );

      transaction.set(callRef, {
        'summaryMessageId': messageRef.id,
        'summaryLoggedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    });
  }

  Map<String, dynamic> sessionDescriptionToMap(
    RTCSessionDescription description,
  ) {
    return {'type': description.type, 'sdp': description.sdp};
  }

  RTCSessionDescription? sessionDescriptionFromData(dynamic data) {
    if (data is! Map) {
      return null;
    }

    final normalized = Map<String, dynamic>.from(data);
    final type = normalized['type'];
    final sdp = normalized['sdp'];
    if (type is! String || sdp is! String) {
      return null;
    }

    return RTCSessionDescription(sdp, type);
  }

  RTCIceCandidate? candidateFromData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final candidate = data['candidate'];
    final sdpMid = data['sdpMid'];
    final sdpMLineIndex = data['sdpMLineIndex'];
    if (candidate is! String) {
      return null;
    }

    int? lineIndex;
    if (sdpMLineIndex is int) {
      lineIndex = sdpMLineIndex;
    } else if (sdpMLineIndex is num) {
      lineIndex = sdpMLineIndex.toInt();
    }

    return RTCIceCandidate(
      candidate,
      sdpMid is String ? sdpMid : null,
      lineIndex,
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

  String _formatDurationSeconds(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
    }

    return '${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }

  String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }

  bool _shouldWriteSummaryForStatus(String? status) {
    return status == 'ended' || status == 'declined' || status == 'missed';
  }

  String _summaryTextForStatus({
    required String status,
    required bool isVideo,
    required int durationSeconds,
  }) {
    if (status == 'ended') {
      return '${isVideo ? 'Cuộc gọi video' : 'Cuộc gọi thoại'} - ${_formatDurationSeconds(durationSeconds)}';
    }

    return 'Cuộc gọi nhỡ';
  }
}
