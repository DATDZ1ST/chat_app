import 'package:chat_app/firebase_options.dart';
import 'package:chat_app/models/call_screen_arguments.dart';
import 'package:chat_app/navigation/app_navigator.dart';
import 'package:chat_app/screens/auth.dart';
import 'package:chat_app/screens/call.dart';
import 'package:chat_app/screens/chat.dart';
import 'package:chat_app/screens/change_password.dart';
import 'package:chat_app/screens/conversation.dart';
import 'package:chat_app/screens/splash.dart';
import 'package:chat_app/services/push_notification_service.dart';
import 'package:chat_app/widgets/active_call_overlay.dart';
import 'package:chat_app/widgets/incoming_call_listener.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    PushNotificationService.instance.initialize().catchError((
      error,
      stackTrace,
    ) {
      debugPrint('Push notification setup skipped: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigator.navigatorKey,
      scaffoldMessengerKey: AppNavigator.scaffoldMessengerKey,
      title: 'Datdz',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 63, 17, 177),
        ),
      ),
      builder: (context, child) {
        return IncomingCallListener(
          child: ActiveCallOverlay(child: child ?? const SizedBox.shrink()),
        );
      },
      routes: {ChatScreen.routeName: (ctx) => const ChatScreen()},
      onGenerateRoute: (settings) {
        if (settings.name == ChangePasswordScreen.routeName) {
          return MaterialPageRoute(
            builder: (context) => const ChangePasswordScreen(),
          );
        }

        if (settings.name == ConversationScreen.routeName) {
          final arguments = settings.arguments as ConversationScreenArguments;
          return MaterialPageRoute(
            builder: (context) => ConversationScreen(arguments: arguments),
          );
        }

        if (settings.name == CallScreen.routeName) {
          final arguments = settings.arguments as CallScreenArguments;
          return MaterialPageRoute(
            builder: (context) => CallScreen(arguments: arguments),
          );
        }

        return null;
      },
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return SplashScreen();
          }

          if (snapshot.hasData) {
            return const ChatScreen();
          }
          return AuthScreen();
        },
      ),
    );
  }
}
