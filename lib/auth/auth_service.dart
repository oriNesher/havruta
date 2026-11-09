import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'social_auth_config.dart';

final auth = FirebaseAuth.instance;

Future<UserCredential> signUp({
  required String email,
  required String password,
}) {
  return auth.createUserWithEmailAndPassword(
    email: email,
    password: password,
  );
}

Future<UserCredential> signIn({
  required String email,
  required String password,
}) {
  return auth.signInWithEmailAndPassword(
    email: email,
    password: password,
  );
}

/// Signs out of Firebase and of the provider SDKs too, so the next Google
/// or Facebook sign-in shows the account chooser instead of silently
/// reusing the last account.
Future<void> signOut() async {
  if (_googleInit != null) {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('Google sign-out error: $e');
    }
  }
  if (!kIsWeb && facebookSignInAvailable) {
    try {
      await FacebookAuth.instance.logOut();
    } catch (e) {
      debugPrint('Facebook sign-out error: $e');
    }
  }
  await auth.signOut();
}

// ─────────────────────────────────────────────
// Google & Facebook sign-in.
//
// Every user's data hangs off their Firebase uid, so the one rule here is
// that a returning person must land on the uid they already have. Firebase
// keeps one account per email; the two ways that can still go wrong are
// handled explicitly:
//
// - Google sign-in to an email whose existing account isn't verified (every
//   email/password account Havruta has, since it never sent verification
//   mail) keeps the uid but deletes the password. googleSignInPreflight
//   detects that first, and the user links Google from their existing
//   sign-in instead, which keeps the password.
// - Facebook sign-in to an email that already has an account fails with
//   account-exists-with-different-credential; same remedy.
// ─────────────────────────────────────────────

enum SocialProvider {
  google('google.com', 'Google'),
  facebook('facebook.com', 'Facebook');

  final String providerId;
  final String label;
  const SocialProvider(this.providerId, this.label);
}

/// A provider credential that couldn't be used to sign in because its
/// email already belongs to a Havruta account. It gets linked to that
/// account once the user signs in to it the way they normally do.
class PendingLink {
  final SocialProvider provider;
  final AuthCredential credential;
  final String? email;

  /// Firebase provider ids ('password', 'google.com', 'facebook.com') the
  /// existing account signs in with, when known. Null when Firebase didn't
  /// say (Facebook conflicts — email enumeration protection hides it).
  final List<String>? existingMethods;

  const PendingLink({
    required this.provider,
    required this.credential,
    required this.email,
    required this.existingMethods,
  });

  /// Whether the existing account may sign in with an email & password.
  bool get mayHavePassword =>
      existingMethods == null || existingMethods!.contains('password');

  /// The other social providers the existing account may sign in with.
  List<SocialProvider> get otherProviders => SocialProvider.values
      .where((p) => p != provider)
      .where(
        (p) => existingMethods == null || existingMethods!.contains(p.providerId),
      )
      .toList();
}

sealed class SocialSignInResult {
  const SocialSignInResult();
}

class SocialSignedIn extends SocialSignInResult {
  const SocialSignedIn();
}

class SocialCancelled extends SocialSignInResult {
  const SocialCancelled();
}

class SocialNeedsExistingAccount extends SocialSignInResult {
  final PendingLink pending;
  const SocialNeedsExistingAccount(this.pending);
}

/// A sign-in failure with a message fit to show the user as-is.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => message;
}

Future<void>? _googleInit;

/// GoogleSignIn must be initialized exactly once before any other call.
Future<void> ensureGoogleInitialized() {
  return _googleInit ??= GoogleSignIn.instance.initialize(
    clientId: kIsWeb ? googleWebClientId : null,
    serverClientId: kIsWeb ? null : googleWebClientId,
  );
}

/// Native Google sign-in (Android). On web the account comes from the
/// button Google's SDK renders instead — see [continueWithGoogleIdToken].
Future<SocialSignInResult> signInWithGoogle() async {
  final idToken = await _authenticateWithGoogle();
  if (idToken == null) return const SocialCancelled();
  return continueWithGoogleIdToken(idToken);
}

/// Second half of Google sign-in, shared with the web button: asks the
/// backend whether a plain sign-in would strip an existing account's
/// password before letting Firebase sign in.
Future<SocialSignInResult> continueWithGoogleIdToken(String idToken) async {
  final credential = GoogleAuthProvider.credential(idToken: idToken);

  final Map<String, dynamic> decision;
  try {
    final result = await FirebaseFunctions.instance
        .httpsCallable('googleSignInPreflight')
        .call<Map<String, dynamic>>({'idToken': idToken});
    decision = result.data;
  } on FirebaseFunctionsException catch (e) {
    debugPrint('googleSignInPreflight error: ${e.code} ${e.message}');
    throw const AuthFailure(
      "Couldn't reach Havruta to finish signing in. Please try again.",
    );
  }

  if (decision['action'] == 'linkRequired') {
    return SocialNeedsExistingAccount(
      PendingLink(
        provider: SocialProvider.google,
        credential: credential,
        email: _emailFromIdToken(idToken),
        existingMethods: (decision['methods'] as List?)?.cast<String>(),
      ),
    );
  }

  return _signInWithCredential(SocialProvider.google, credential);
}

Future<SocialSignInResult> signInWithFacebook() async {
  if (kIsWeb) {
    try {
      await auth.signInWithPopup(FacebookAuthProvider()..addScope('email'));
      return const SocialSignedIn();
    } on FirebaseAuthException catch (e) {
      return _handleSignInError(SocialProvider.facebook, e, fallback: null);
    }
  }

  final credential = await _facebookCredential();
  if (credential == null) return const SocialCancelled();
  return _signInWithCredential(SocialProvider.facebook, credential);
}

/// Signs in to the existing account with its password, then links the
/// pending provider to it.
Future<void> signInWithPasswordAndLink({
  required String email,
  required String password,
  required PendingLink pending,
}) async {
  try {
    await auth.signInWithEmailAndPassword(email: email, password: password);
  } on FirebaseAuthException catch (e) {
    throw AuthFailure(authErrorMessage(e));
  }
  await linkPending(pending);
}

/// Links [pending] to whoever is signed in now.
Future<void> linkPending(PendingLink pending) async {
  final user = auth.currentUser;
  if (user == null) return;
  try {
    await user.linkWithCredential(pending.credential);
  } on FirebaseAuthException catch (e) {
    throw AuthFailure(
      "You're signed in, but ${pending.provider.label} couldn't be "
      'connected: ${authErrorMessage(e, provider: pending.provider)}',
    );
  }
  await _syncProfileEmail();
}

/// Connects [provider] to the signed-in account (the Account screen).
/// Linking is always safe for existing credentials — only *signing in*
/// with Google can replace them. Returns false if the user cancelled.
Future<bool> linkProvider(SocialProvider provider) async {
  final user = auth.currentUser;
  if (user == null) return false;
  try {
    if (kIsWeb) {
      await user.linkWithPopup(switch (provider) {
        SocialProvider.google => GoogleAuthProvider(),
        SocialProvider.facebook => FacebookAuthProvider()..addScope('email'),
      });
    } else {
      final AuthCredential? credential = switch (provider) {
        SocialProvider.google => await _googleCredential(),
        SocialProvider.facebook => await _facebookCredential(),
      };
      if (credential == null) return false;
      await user.linkWithCredential(credential);
    }
  } on FirebaseAuthException catch (e) {
    if (_isCancellation(e)) return false;
    throw AuthFailure(authErrorMessage(e, provider: provider));
  }
  await _syncProfileEmail();
  return true;
}

/// Enumeration-safe: Firebase reports success whether or not the email is
/// registered. Completing the reset also verifies the email, after which a
/// Google sign-in links to the account instead of replacing its password.
Future<void> sendPasswordReset(String email) async {
  try {
    await auth.sendPasswordResetEmail(email: email);
  } on FirebaseAuthException catch (e) {
    throw AuthFailure(authErrorMessage(e));
  }
}

/// "Not you?" on the username screen: gets someone who signed in with the
/// wrong account back to the login screen. The sign-in account they just
/// created is deleted too — but only while it has no Havruta profile, so
/// this can never remove an account with data.
Future<void> abandonUnfinishedSignIn() async {
  final user = auth.currentUser;
  if (user != null) {
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!profile.exists) await user.delete();
    } catch (e) {
      // e.g. requires-recent-login: leave the empty account, just sign out.
      debugPrint('Unfinished account cleanup skipped: $e');
    }
  }
  await signOut();
}

String authErrorMessage(Object e, {SocialProvider? provider}) {
  final name = provider?.label ?? 'That';
  if (e is AuthFailure) return e.message;
  if (e is GoogleSignInException) {
    return switch (e.code) {
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        "Google sign-in isn't set up for this version of the app yet.",
      GoogleSignInExceptionCode.uiUnavailable =>
        "Google sign-in can't open here. Try again from the app.",
      _ => 'Google sign-in failed. Please try again.',
    };
  }
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-email' => 'Incorrect email or password.',
      'credential-already-in-use' =>
        '$name account is already connected to a different Havruta account.',
      'email-already-in-use' =>
        "$name account's email already belongs to a different Havruta account.",
      'provider-already-linked' => '$name is already connected.',
      'user-disabled' => 'This account has been disabled.',
      'too-many-requests' => 'Too many attempts. Please wait and try again.',
      'network-request-failed' => 'No connection. Check your internet.',
      'popup-blocked' =>
        'Your browser blocked the sign-in window. Allow pop-ups and retry.',
      'operation-not-supported-in-this-environment' || 'web-storage-unsupported' =>
        "Sign-in can't run inside this app's browser. Open Havruta in "
            'Chrome or Safari, or use email and password.',
      _ => e.message ?? 'Sign-in failed. Please try again.',
    };
  }
  return 'Sign-in failed. Please try again.';
}

// ── internals ──

Future<SocialSignInResult> _signInWithCredential(
  SocialProvider provider,
  AuthCredential credential,
) async {
  try {
    await auth.signInWithCredential(credential);
    return const SocialSignedIn();
  } on FirebaseAuthException catch (e) {
    return _handleSignInError(provider, e, fallback: credential);
  }
}

SocialSignInResult _handleSignInError(
  SocialProvider provider,
  FirebaseAuthException e, {
  required AuthCredential? fallback,
}) {
  if (_isCancellation(e)) return const SocialCancelled();
  if (e.code == 'account-exists-with-different-credential') {
    final credential = e.credential ?? fallback;
    if (credential != null) {
      return SocialNeedsExistingAccount(
        PendingLink(
          provider: provider,
          credential: credential,
          email: e.email,
          existingMethods: null,
        ),
      );
    }
  }
  throw AuthFailure(authErrorMessage(e, provider: provider));
}

bool _isCancellation(FirebaseAuthException e) =>
    e.code == 'popup-closed-by-user' ||
    e.code == 'cancelled-popup-request' ||
    e.code == 'web-context-canceled';

/// The chosen Google account's ID token, or null if the user cancelled.
Future<String?> _authenticateWithGoogle() async {
  await ensureGoogleInitialized();
  try {
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure('Google sign-in failed. Please try again.');
    }
    return idToken;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    debugPrint('Google sign-in error: ${e.code} ${e.description}');
    throw AuthFailure(authErrorMessage(e));
  }
}

Future<AuthCredential?> _googleCredential() async {
  final idToken = await _authenticateWithGoogle();
  return idToken == null ? null : GoogleAuthProvider.credential(idToken: idToken);
}

/// Native Facebook login. On iOS the SDK may hand back a Limited Login
/// OIDC token instead of a Graph access token; Firebase accepts that as an
/// ID token checked against the raw nonce.
Future<AuthCredential?> _facebookCredential() async {
  final rawNonce = _randomNonce();
  final result = await FacebookAuth.instance.login(
    nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
  );
  switch (result.status) {
    case LoginStatus.success:
      final token = result.accessToken!;
      return token.type == AccessTokenType.limited
          ? OAuthProvider('facebook.com').credential(
              idToken: token.tokenString,
              rawNonce: rawNonce,
            )
          : FacebookAuthProvider.credential(token.tokenString);
    case LoginStatus.cancelled:
      return null;
    case LoginStatus.failed:
    case LoginStatus.operationInProgress:
      debugPrint('Facebook login failed: ${result.message}');
      throw const AuthFailure('Facebook sign-in failed. Please try again.');
  }
}

String _randomNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

/// Display-only peek at the email inside a Google ID token, for the
/// "connect your account" prompt. The token's authenticity is checked by
/// the backend and Firebase, never by this.
String? _emailFromIdToken(String idToken) {
  try {
    final parts = idToken.split('.');
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    return (jsonDecode(payload) as Map<String, dynamic>)['email'] as String?;
  } catch (_) {
    return null;
  }
}

/// A Facebook account may not have an email; if linking just gave the user
/// one, record it on their profile so invite-by-email can find them.
Future<void> _syncProfileEmail() async {
  final user = auth.currentUser;
  if (user == null) return;
  try {
    await user.reload();
    final email = auth.currentUser?.email;
    if (email == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final profile = await ref.get();
    if (profile.exists && profile.data()?['emailLower'] == null) {
      await ref.update({'email': email, 'emailLower': email.toLowerCase()});
    }
  } catch (e) {
    debugPrint('Profile email sync error: $e');
  }
}
