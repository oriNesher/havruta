import 'dart:typed_data';

import 'platform_web_stub.dart'
    if (dart.library.js_interop) 'platform_web_impl.dart'
    as impl;

/// Browser-only capabilities, behind a conditional import so Android and iOS
/// never compile against `package:web`. Every function here is a no-op off
/// the web, so callers don't need a `kIsWeb` check of their own.

/// Hands [bytes] to the user as a downloadable file. On web this triggers a
/// browser download; on mobile there is no equivalent (the share sheet is
/// the real affordance), so it does nothing and reports false.
///
/// Returns whether the download was actually started.
Future<bool> downloadBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) => impl.downloadBytes(bytes: bytes, filename: filename, mimeType: mimeType);

/// Rewrites the browser's address bar to [path] without navigating or adding
/// a history entry. Used to strip a consumed invite token out of the URL, so
/// it isn't re-read on reload or copied out of the address bar by the user.
void replaceUrlPath(String path) => impl.replaceUrlPath(path);
