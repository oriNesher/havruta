import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Wraps the bytes in a Blob and clicks a synthetic anchor, which is the
/// only portable way to hand a file to the user from a browser. The object
/// URL is revoked immediately — the browser has already taken ownership of
/// the download by the time click() returns.
Future<bool> downloadBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return true;
}

/// replaceState rather than pushState: the consumed invite URL should not
/// become somewhere the back button can return to.
void replaceUrlPath(String path) {
  web.window.history.replaceState(null, '', path);
}
