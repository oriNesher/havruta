import 'package:flutter/widgets.dart';

import 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart'
    as impl;

/// The "Continue with Google" button rendered by Google's own web SDK —
/// on web, the only way to get the Google ID token before Firebase signs
/// in (needed for googleSignInPreflight). Taps surface as events on
/// GoogleSignIn.instance.authenticationEvents. Renders nothing off the web,
/// where the app's own button calls the native SDK instead.
Widget googleWebButton({required double width}) =>
    impl.googleWebButton(width: width);
