# chat_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Cross-network calling

This app uses Firestore for signaling and WebRTC for audio/video media. Calls
across different networks usually require a TURN relay.

Preferred setup: let the app fetch short-lived TURN credentials from Firebase
Functions automatically.

1. Configure your TURN server to use shared-secret auth.
2. Set Firebase Functions secrets:

```powershell
npx -y firebase-tools@latest functions:secrets:set TURN_URLS
npx -y firebase-tools@latest functions:secrets:set TURN_AUTH_SECRET
npx -y firebase-tools@latest functions:secrets:set TURN_TTL_SECONDS
```

3. Deploy functions:

```powershell
npx -y firebase-tools@latest deploy --only functions
```

After that, signed-in clients will call `getTurnCredentials` automatically
before starting a call. No per-device TURN setup is needed.

Setup without Firebase Functions:

1. Create the Firestore document `app_config/webrtc`.
2. Put your TURN config in that document with these fields:

```json
{
  "turnUrls": [
    "turn:YOUR_HOST:3478?transport=udp",
    "turn:YOUR_HOST:3478?transport=tcp",
    "turns:YOUR_HOST:5349"
  ],
  "username": "YOUR_TURN_USERNAME",
  "credential": "YOUR_TURN_PASSWORD",
  "forceRelay": true
}
```

A ready-to-copy example also exists at
[env/webrtc.firestore.example.json](env/webrtc.firestore.example.json).

If your Firestore rules currently block that document, merge the rule from
[firestore.webrtc.rules](firestore.webrtc.rules) into your existing rules.

The app will try Firebase Functions first, then automatically fall back to
this Firestore document. This is simpler, but less secure because TURN
credentials are distributed to clients directly.

Fallback setup for local development:

1. Open [env/webrtc.local.json](env/webrtc.local.json) and replace the TURN
   values with your real relay credentials.
2. In VS Code, run the `chat_app (TURN)` launch configuration.
3. Or run from terminal:

```powershell
flutter run --dart-define-from-file=env/webrtc.local.json
```

The committed sample file is [env/webrtc.example.json](env/webrtc.example.json).
If `env/webrtc.local.json` does not exist yet, the VS Code launch task will
create it from the sample file. The local file is ignored by git so TURN
credentials do not get committed.
