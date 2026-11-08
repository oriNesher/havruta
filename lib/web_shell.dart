import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The width the whole UI was designed against. Past this, a browser window
/// just stretches phone-shaped layouts across a monitor.
const double _shellMaxWidth = 480;

const Color _backdropColor = Color(0xFF08080D);
const Color _shellBorderColor = Color(0xFF1E1E30);

/// Constrains the app to a phone-width column when it's running in a browser
/// window wider than the layouts were built for. Below that width — every
/// phone, and native Android/iOS, which never enter this branch at all —
/// the child is returned untouched, so there is exactly one code path on
/// mobile and it is the original one.
///
/// Wraps FeatureTipLayer (see main.dart), so tip bubbles are held to the
/// same column as the screens they point at.
class WebShell extends StatelessWidget {
  final Widget child;

  const WebShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    final media = MediaQuery.of(context);
    if (media.size.width <= _shellMaxWidth) return child;

    return ColoredBox(
      color: _backdropColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _shellMaxWidth),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: _shellBorderColor),
              ),
            ),
            // Screens that measure themselves must see the column's width,
            // not the window's, or anything width-driven inside would size
            // against space it doesn't actually have.
            child: MediaQuery(
              data: media.copyWith(
                size: Size(_shellMaxWidth, media.size.height),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets a mouse drag scrollables, which Flutter otherwise restricts to
/// touch and stylus. Without it, the horizontal PageViews in this app are
/// simply unusable with a mouse — there is nothing to swipe with.
class WebScrollBehavior extends MaterialScrollBehavior {
  const WebScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}
