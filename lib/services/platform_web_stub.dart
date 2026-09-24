import 'dart:typed_data';

/// Non-web implementations. Mobile has no "save to downloads" affordance
/// that makes sense here — sharing goes through the native share sheet —
/// and no address bar to rewrite.

Future<bool> downloadBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async => false;

void replaceUrlPath(String path) {}
