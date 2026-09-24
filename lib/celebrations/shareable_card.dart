import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart';
import '../services/platform_web.dart';

const Color _cardBase = Color(0xFF181824);
const Color _screenBase = Color(0xFF0F0F17);

/// A strong, unmistakably-tinted version of [accent] over the app's base
/// background — used for both the shareable card's own fill and the full
/// screen behind it, so the theme color reads as "the screen is green/red",
/// not a faint tint on an otherwise neutral surface.
Color screenTintColor(Color accent) =>
    Color.alphaBlend(accent.withValues(alpha: 0.28), _screenBase);

/// Wraps celebratory content in a fixed-size branded card. Both shareable
/// screens (celebration, trash talk) render their content through this so
/// anything captured out of the app always carries the Havruta logo.
///
/// Deliberately square-cornered, not rounded, and borderless: a rounded (or
/// bordered) RepaintBoundary capture can leave the PNG's edges looking off
/// against WhatsApp's own preview chrome. A plain rectangular fill has no
/// such artifacting.
class ShareableCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;

  const ShareableCard({
    super.key,
    required this.child,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accentColor.withValues(alpha: 0.55), _cardBase),
            screenTintColor(accentColor),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/icon/icon.png', width: 20, height: 20),
              const SizedBox(width: 8),
              Text(
                'HAVRUTA',
                style: AppTheme.display(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.85),
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rasterizes the [RepaintBoundary] identified by [boundaryKey] to PNG bytes
/// and hands them to the user alongside [shareText].
///
/// On Android and iOS this opens the native share sheet. Browsers only
/// expose a share sheet through the Web Share API, and most desktop ones
/// refuse file payloads outright, so web degrades to downloading the card
/// and copying the text — the user still ends up with both pieces.
///
/// Returns whether anything was actually presented to the user (false if
/// the card couldn't be captured). Resolves once the sheet is dismissed;
/// what, if anything, the user shared is not knowable.
Future<bool> captureAndShareCard({
  required GlobalKey boundaryKey,
  required String shareText,
  String? subject,
}) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) return false;

  final image = await renderObject.toImage(pixelRatio: 3.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) return false;
  final Uint8List bytes = byteData.buffer.asUint8List();

  const filename = 'havruta-celebration.png';

  final params = ShareParams(
    text: shareText,
    subject: subject,
    files: [XFile.fromData(bytes, mimeType: 'image/png', name: filename)],
  );

  if (!kIsWeb) {
    await SharePlus.instance.share(params);
    return true;
  }

  try {
    final result = await SharePlus.instance.share(params);
    if (result.status != ShareResultStatus.unavailable) return true;
  } catch (_) {
    // Browser has no Web Share API, or refuses file payloads. Fall through.
  }

  await Clipboard.setData(ClipboardData(text: shareText));
  await downloadBytes(bytes: bytes, filename: filename, mimeType: 'image/png');
  return true;
}
