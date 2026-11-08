import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'auth/auth_gate.dart';
import 'app_theme.dart';
import 'services/deep_link_service.dart';
import 'tips/feature_tip_layer.dart';
import 'tips/feature_tips_controller.dart';
import 'web_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only. Every screen in the app is a single phone-width column
  // (leaderboards, the celebration card, the hold-to-submit button), and
  // landscape gives all of them a viewport too short to lay out in — the
  // native manifests lock this too, this is the belt to their braces. On
  // web the window is whatever size the browser is, and WebShell already
  // holds the UI to a phone-width column, so there's nothing to lock.
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Fire-and-forget: catches invite links regardless of auth state; the
  // token is picked up later by AuthGate once the user is signed in.
  DeepLinkService().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // Lets first-time feature tips keep to one per screen visit.
      navigatorObservers: [FeatureTipsController.instance.pageVisits],
      // On web only, a mouse can drag scrollables and the UI is held to a
      // phone-width column; on Android and iOS both are no-ops.
      scrollBehavior: kIsWeb ? const WebScrollBehavior() : null,
      // The tip layer sits above the Navigator so a tip can be drawn over
      // any real screen; it draws nothing unless a tip is owed right there.
      builder: (context, child) =>
          WebShell(child: FeatureTipLayer(child: child!)),
      home: AuthGate(),
    );
  }
}
