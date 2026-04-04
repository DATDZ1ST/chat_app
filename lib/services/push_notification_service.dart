import 'package:chat_app/navigation/app_navigator.dart';
import 'package:chat_app/screens/conversation.dart';
import 'package:chat_app/screens/chat.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _isInitialized = true;

    await _messaging.requestPermission();
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseAuth.instance.authStateChanges().listen((user) {
      _handleAuthStateChanged(user);
    });
    _messaging.onTokenRefresh.listen((token) async {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return;
      }

      try {
        await _registerTokenForUser(currentUser.uid, token);
      } catch (error, stackTrace) {
        debugPrint('Failed to refresh FCM token registration: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageTap(initialMessage);
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await _handleSignedInUser(currentUser);
    }
  }

  Future<void> _handleAuthStateChanged(User? user) async {
    if (user == null) {
      return;
    }

    try {
      await _handleSignedInUser(user);
    } catch (error, stackTrace) {
      debugPrint('Failed to sync signed-in user token: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _handleSignedInUser(User user) async {
    final token = await _messaging.getToken();
    if (token == null) {
      return;
    }

    await _registerTokenForUser(user.uid, token);
  }

  Future<void> signOutCurrentUser() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId != null) {
      try {
        await _removeTokenFromUser(currentUserId);
      } catch (error, stackTrace) {
        debugPrint('Failed to unregister FCM token before sign out: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    await FirebaseAuth.instance.signOut();
  }

  Future<void> _registerTokenForUser(String userId, String token) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  Future<void> _removeTokenFromUser(
    String? userId, {
    String? tokenOverride,
  }) async {
    if (userId == null) {
      return;
    }

    final token = tokenOverride ?? await _messaging.getToken();
    if (token == null) {
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
    }, SetOptions(merge: true));
  }

  void _handleMessageTap(RemoteMessage message) {
    if (FirebaseAuth.instance.currentUser == null) {
      return;
    }

    final chatId = message.data['chatId'];
    final otherUserId = message.data['otherUserId'];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = AppNavigator.navigatorKey.currentState;
      if (navigator == null) {
        return;
      }

      navigator.pushNamedAndRemoveUntil(ChatScreen.routeName, (route) => false);

      if (chatId is String &&
          chatId.isNotEmpty &&
          otherUserId is String &&
          otherUserId.isNotEmpty) {
        navigator.pushNamed(
          ConversationScreen.routeName,
          arguments: ConversationScreenArguments(
            chatId: chatId,
            otherUserId: otherUserId,
          ),
        );
      }
    });
  }
}
