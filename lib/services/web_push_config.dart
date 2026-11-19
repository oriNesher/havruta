/// The Web Push (VAPID) public key from Firebase console → Project settings
/// → Cloud Messaging → Web configuration → Web Push certificates. It's a
/// public key, safe to ship in the client.
///
/// Empty means web push stays off: the web app never asks for permission
/// and registers no token, exactly as before it existed.
const String kWebPushVapidKey =
    'BHC3gcO5oukgQSqzhj6nVpwmEUTMF7j8czouEnM7wz7z6RWCVe05nOVYTZQcjrQA8Cz1LmwOEn68fM2d1SEvUT0';

bool get webPushConfigured => kWebPushVapidKey.isNotEmpty;
