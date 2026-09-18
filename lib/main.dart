import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'auth/auth_gate.dart';
import 'app_theme.dart';
import 'onboarding/onboarding_controller.dart';
import 'onboarding/onboarding_guide_layer.dart';
import 'services/deep_link_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
      // The guide layer sits above the Navigator so onboarding guidance can
      // be drawn over any real screen; it draws nothing at all unless the
      // controller is actively guiding this user.
      navigatorKey: OnboardingController.instance.navigatorKey,
      builder: (context, child) => OnboardingGuideLayer(child: child!),
      home: AuthGate(),
    );
  }
}