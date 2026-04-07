import 'dart:async';

import 'package:chat_app/models/call_screen_arguments.dart';
import 'package:chat_app/navigation/app_navigator.dart';
import 'package:chat_app/screens/call.dart';
import 'package:chat_app/services/call_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class IncomingCallListener extends StatefulWidget {
  const IncomingCallListener({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  final CallService _callService = CallService.instance;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _incomingCallSubscription;
  String? _presentedCallId;
  bool _isRoutingToCall = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthStateChanged,
    );
    _handleAuthStateChanged(FirebaseAuth.instance.currentUser);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _incomingCallSubscription?.cancel();
    super.dispose();
  }

  void _handleAuthStateChanged(User? user) {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = null;
    _presentedCallId = null;

    if (user == null) {
      return;
    }

    _incomingCallSubscription = _callService
        .watchIncomingCalls(user.uid)
        .listen((snapshot) {
          _handleIncomingCallSnapshot(snapshot, user.uid);
        });
  }

  void _handleIncomingCallSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String currentUserId,
  ) {
    if (!mounted || _isRoutingToCall) {
      return;
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? newestCallDoc;
    var newestTimestamp = -1;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['status'] != 'ringing' || data['calleeId'] != currentUserId) {
        continue;
      }

      final createdAt = data['createdAt'];
      final createdAtMillis = createdAt is Timestamp
          ? createdAt.millisecondsSinceEpoch
          : 0;
      if (createdAtMillis > newestTimestamp) {
        newestTimestamp = createdAtMillis;
        newestCallDoc = doc;
      }
    }

    if (newestCallDoc == null) {
      _presentedCallId = null;
      return;
    }

    if (_presentedCallId == newestCallDoc.id) {
      return;
    }

    _presentedCallId = newestCallDoc.id;
    unawaited(
      Future<void>.microtask(() {
        return _showIncomingCallDialog(newestCallDoc!);
      }),
    );
  }

  Future<void> _showIncomingCallDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> callDoc,
  ) async {
    if (!mounted || _isRoutingToCall) {
      return;
    }

    final navigator = AppNavigator.navigatorKey.currentState;
    final navigatorContext = navigator?.overlay?.context ?? navigator?.context;
    if (navigator == null || navigatorContext == null) {
      _presentedCallId = null;
      return;
    }

    final callData = callDoc.data();
    final callerId = callData['callerId'] as String? ?? '';
    final callerName = callData['callerName'] as String? ?? 'User';
    final callerImage = callData['callerImage'] as String?;
    final chatId = callData['chatId'] as String? ?? '';
    final isVideo = callData['isVideo'] == true;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    callWatcherSubscription;
    var isDialogActive = true;

    try {
      callWatcherSubscription = _callService.watchCall(callDoc.id).listen((
        snapshot,
      ) {
        final latestData = snapshot.data();
        final status = latestData?['status'];
        if (!mounted ||
            navigatorContext.mounted == false ||
            !isDialogActive ||
            _isRoutingToCall) {
          return;
        }

        if (latestData == null || status != 'ringing') {
          Navigator.of(navigatorContext, rootNavigator: true).pop();
        }
      });

      final accepted = await showGeneralDialog<bool>(
        context: navigatorContext,
        barrierDismissible: false,
        barrierLabel: 'incoming_call',
        barrierColor: const Color(0xB3000000),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          final hasImage = callerImage != null && callerImage.trim().isNotEmpty;
          return SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF101A30), Color(0xFF1D3557)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    const Spacer(),
                    Text(
                      isVideo ? 'Cuộc gọi video đến' : 'Cuộc gọi thoại đến',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 22),
                    CircleAvatar(
                      radius: 48,
                      foregroundImage: hasImage
                          ? NetworkImage(callerImage)
                          : null,
                      backgroundColor: Colors.white12,
                      child: hasImage
                          ? null
                          : Text(
                              callerName.isEmpty
                                  ? '?'
                                  : callerName[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      callerName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isVideo
                          ? 'Dang goi video cho ban'
                          : 'Dang goi thoai cho ban',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildActionButton(
                            icon: Icons.call_end_rounded,
                            label: 'Tu choi',
                            backgroundColor: const Color(0xFFE53935),
                            onTap: () => navigator.pop(false),
                          ),
                          _buildActionButton(
                            icon: isVideo
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            label: 'Tra loi',
                            backgroundColor: const Color(0xFF2E7D32),
                            onTap: () => navigator.pop(true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      );

      if (accepted == true) {
        isDialogActive = false;
        await callWatcherSubscription.cancel();
        callWatcherSubscription = null;
        _isRoutingToCall = true;
        await navigator.pushNamed(
          CallScreen.routeName,
          arguments: CallScreenArguments(
            callId: callDoc.id,
            chatId: chatId,
            otherUserId: callerId,
            isOutgoing: false,
            isVideo: isVideo,
            displayName: callerName,
            avatarUrl: callerImage,
          ),
        );
        _isRoutingToCall = false;
        _presentedCallId = null;
        return;
      }

      isDialogActive = false;
      if (accepted == null) {
        _presentedCallId = null;
        return;
      }

      final latestCallSnapshot = await _callService.getCall(callDoc.id);
      final latestCallData = latestCallSnapshot.data();
      if (latestCallData?['status'] != 'ringing') {
        _presentedCallId = null;
        return;
      }

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        await _callService.declineCall(callDoc.id, currentUserId);
        unawaited(
          _callService.writeCallSummaryMessageIfNeeded(callDoc.id).catchError((
            error,
            stackTrace,
          ) {
            debugPrint('Failed to write declined call summary: $error');
            debugPrintStack(stackTrace: stackTrace);
          }),
        );
      }
      _presentedCallId = null;
    } finally {
      await callWatcherSubscription?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
