import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The width the whole UI was designed against. Past this, a browser window
/// just stretches phone-shaped layouts across a monitor.
const double _shellMaxWidth = 480;

const Color _backdropColor = Color(0xFF08080D);
const Color _shellBorderColor = Color(0xFF1E1E30);

/// Screens built for a desktop browser (the organizer dashboard) lift the
/// phone-width column while they're mounted: [acquire] in initState,
/// [release] in dispose. A count rather than a flag, so stacked wide
/// screens don't switch it off under each other. Changes are deferred to
/// after the frame, since initState/dispose run mid-build and WebShell sits
/// above the Navigator.
class WebShellWide {
  WebShellWide._();

  static final ValueNotifier<int> _requests = ValueNotifier(0);

  static void acquire() => WidgetsBinding.instance.addPostFrameCallback(
    (_) => _requests.value++,
  );

  static void release() => WidgetsBinding.instance.addPostFrameCallback(
    (_) => _requests.value = _requests.value > 0 ? _requests.value - 1 : 0,
  );
}

/// Constrains the app to a phone-width column when it's running in a browser
/// window wider than the layouts were built for — unless a wide screen has
/// asked for the whole window (WebShellWide). At or below that width (every
/// phone browser) nothing binds and the child fills the window. Native
/// Android/iOS never enter this at all: the child is returned untouched, so
/// mobile keeps exactly one code path and it is the original one.
///
/// Wraps FeatureTipLayer (see main.dart), so tip bubbles are held to the
/// same column as the screens they point at.
class WebShell extends StatelessWidget {
  final Widget child;

  const WebShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    return ValueListenableBuilder<int>(
      valueListenable: WebShellWide._requests,
      builder: (context, wideRequests, _) {
        final media = MediaQuery.of(context);
        final column =
            wideRequests == 0 && media.size.width > _shellMaxWidth;

        // One fixed widget structure for every case, varying only its
        // parameters: switching between "column" and "full width" must
        // never re-parent the Navigator below, or open screens (and the
        // tip layer) would lose their state.
        return ColoredBox(
          color: column ? _backdropColor : Colors.transparent,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: column ? _shellMaxWidth : double.infinity,
              ),
              child: DecoratedBox(
                decoration: column
                    ? const BoxDecoration(
                        border: Border.symmetric(
                          vertical: BorderSide(color: _shellBorderColor),
                        ),
                      )
                    : const BoxDecoration(),
                // Screens that measure themselves must see the column's
                // width, not the window's, or anything width-driven inside
                // would size against space it doesn't actually have.
                child: MediaQuery(
                  data: column
                      ? media.copyWith(
                          size: Size(_shellMaxWidth, media.size.height),
                        )
                      : media,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
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
