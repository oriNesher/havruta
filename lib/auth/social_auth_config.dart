import 'package:flutter/foundation.dart';

/// Google OAuth client ids for the havruta-app Firebase project. Public
/// identifiers that ship inside every build, not secrets. Every Google ID
/// token the app requests is minted for the Web client (passed as
/// serverClientId on Android/iOS and clientId on web), which is what the
/// googleSignInPreflight callable verifies against — keep these in sync
/// with functions/src/auth/config.ts.
const String googleWebClientId =
    '943688238219-4h068r6tlmhkmmgdqcemmcri8t1l77s1.apps.googleusercontent.com';
const String googleIosClientId =
    '943688238219-dhvmaqh82efj1o1081ao342vf63d4ru8.apps.googleusercontent.com';

/// Flipped once the Meta app exists and its App ID / Client Token are in
/// android/app/src/main/res/values/strings.xml and ios/Runner/Info.plist.
const bool facebookConfigured = false;

/// Google and Facebook sign-in are offered on Android and web only. iOS
/// stays email-only until Sign in with Apple ships alongside them: App
/// Store Review Guideline 4.8 effectively requires it once a third-party
/// login is offered.
bool get _socialPlatform =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.android;

bool get googleSignInAvailable =>
    _socialPlatform && googleWebClientId.isNotEmpty;

bool get facebookSignInAvailable => _socialPlatform && facebookConfigured;
