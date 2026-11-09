// OAuth client ids whose Google ID tokens googleSignInPreflight accepts.
// Public identifiers (they ship inside every app build), not secrets. The
// app requests every token for the Web client (serverClientId on Android
// and iOS, clientId on web); the iOS client is accepted as well because
// iOS can mint tokens for its own client id. Both come from the Firebase
// project's Google sign-in provider — must match
// lib/auth/social_auth_config.dart.
export const GOOGLE_OAUTH_CLIENT_IDS: string[] = [
  // Web client (auto created by Google Service)
  "943688238219-4h068r6tlmhkmmgdqcemmcri8t1l77s1.apps.googleusercontent.com",
  // iOS client, com.orinesher.havruta
  "943688238219-dhvmaqh82efj1o1081ao342vf63d4ru8.apps.googleusercontent.com",
];
