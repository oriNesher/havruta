import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'auth_service.dart';
import 'google_web_button.dart';
import 'social_auth_config.dart';
import 'username_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final auth = FirebaseAuth.instance;

  bool isSignUp = false;
  bool isSubmitting = false;

  /// Web only: Google's rendered button reports sign-ins on this stream.
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleWebEvents;
  Future<void>? _googleWebReady;

  /// While the connect-your-account dialog is up it owns Google events.
  bool _connectDialogOpen = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && googleSignInAvailable) {
      _googleWebReady = ensureGoogleInitialized().then((_) {
        _googleWebEvents = GoogleSignIn.instance.authenticationEvents.listen(
          _onGoogleWebEvent,
          onError: (Object e) => _showError(authErrorMessage(e)),
        );
      });
    }
  }

  @override
  void dispose() {
    _googleWebEvents?.cancel();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() => isSignUp = !isSignUp);
  }

  Future<void> _submit() async {
    setState(() => isSubmitting = true);
    try {
      if (isSignUp) {
        await auth.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UsernameScreen()),
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email above first.');
      return;
    }
    try {
      await sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'If $email has a Havruta account, a reset link is on its way.',
          ),
        ),
      );
    } catch (e) {
      _showError(authErrorMessage(e));
    }
  }

  void _onGoogleWebEvent(GoogleSignInAuthenticationEvent event) {
    if (_connectDialogOpen || event is! GoogleSignInAuthenticationEventSignIn) {
      return;
    }
    final idToken = event.user.authentication.idToken;
    if (idToken == null) {
      _showError('Google sign-in failed. Please try again.');
      return;
    }
    _runSocial(() => continueWithGoogleIdToken(idToken));
  }

  /// Runs a Google/Facebook sign-in. On success AuthGate takes over (this
  /// screen is replaced); if the email already has an account, the user
  /// is walked through connecting the provider to it instead.
  Future<void> _runSocial(Future<SocialSignInResult> Function() signIn) async {
    if (isSubmitting) return;
    setState(() => isSubmitting = true);
    try {
      final result = await signIn();
      if (result is SocialNeedsExistingAccount && mounted) {
        _connectDialogOpen = true;
        await showDialog<void>(
          context: context,
          builder: (_) => _ConnectExistingAccountDialog(pending: result.pending),
        );
        _connectDialogOpen = false;
      }
    } catch (e) {
      _showError(authErrorMessage(e));
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSocial = googleSignInAvailable || facebookSignInAvailable;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSignUp ? 'Create account' : 'Welcome back',
                  style: theme.textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  isSignUp
                      ? 'Sign up to start your Havruta'
                      : 'Sign in to continue',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),

                const SizedBox(height: 32),

                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Email"),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Password"),
                ),

                if (!isSignUp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isSubmitting ? null : _forgotPassword,
                      child: const Text('Forgot password?'),
                    ),
                  )
                else
                  const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSubmitting ? null : _submit,
                    child: isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isSignUp ? "Create Account" : "Login"),
                  ),
                ),

                if (showSocial) ...[
                  const SizedBox(height: 24),
                  const _OrDivider(),
                  const SizedBox(height: 24),
                  if (googleSignInAvailable)
                    kIsWeb
                        ? _GoogleWebButtonSlot(ready: _googleWebReady)
                        : _SocialButton(
                            provider: SocialProvider.google,
                            onPressed: isSubmitting
                                ? null
                                : () => _runSocial(signInWithGoogle),
                          ),
                  if (googleSignInAvailable && facebookSignInAvailable)
                    const SizedBox(height: 12),
                  if (facebookSignInAvailable)
                    _SocialButton(
                      provider: SocialProvider.facebook,
                      onPressed: isSubmitting
                          ? null
                          : () => _runSocial(signInWithFacebook),
                    ),
                ],

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: Center(
                    child: TextButton(
                      onPressed: isSubmitting ? null : _toggleMode,
                      child: Text(
                        isSignUp
                            ? "Already have an account? Sign In"
                            : "Don't have an account? Sign Up",
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.45);
    return Row(
      children: [
        Expanded(child: Divider(color: muted.withValues(alpha: 0.3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: muted)),
        ),
        Expanded(child: Divider(color: muted.withValues(alpha: 0.3))),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final SocialProvider provider;
  final VoidCallback? onPressed;

  const _SocialButton({required this.provider, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
        icon: PhosphorIcon(
          switch (provider) {
            SocialProvider.google => PhosphorIconsBold.googleLogo,
            SocialProvider.facebook => PhosphorIconsBold.facebookLogo,
          },
          size: 20,
        ),
        label: Text('Continue with ${provider.label}'),
      ),
    );
  }
}

/// Google's rendered web button, once its SDK has loaded.
class _GoogleWebButtonSlot extends StatelessWidget {
  final Future<void>? ready;
  const _GoogleWebButtonSlot({required this.ready});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError) {
          return const SizedBox(height: 44);
        }
        return LayoutBuilder(
          builder: (context, constraints) => Center(
            child: googleWebButton(width: constraints.maxWidth),
          ),
        );
      },
    );
  }
}

/// Shown when a Google/Facebook account's email already belongs to a
/// Havruta account that a plain provider sign-in can't (or mustn't) join
/// on its own. The user signs in to that account the usual way, and the
/// provider is linked to it — same uid, every existing credential kept.
class _ConnectExistingAccountDialog extends StatefulWidget {
  final PendingLink pending;
  const _ConnectExistingAccountDialog({required this.pending});

  @override
  State<_ConnectExistingAccountDialog> createState() =>
      _ConnectExistingAccountDialogState();
}

class _ConnectExistingAccountDialogState
    extends State<_ConnectExistingAccountDialog> {
  late final _emailController = TextEditingController(
    text: widget.pending.email ?? '',
  );
  final _passwordController = TextEditingController();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleWebEvents;

  bool _busy = false;
  String? _error;
  String? _info;

  PendingLink get _pending => widget.pending;

  bool get _offersGoogleWebButton =>
      kIsWeb &&
      googleSignInAvailable &&
      _pending.otherProviders.contains(SocialProvider.google);

  @override
  void initState() {
    super.initState();
    if (_offersGoogleWebButton) {
      _googleWebEvents = GoogleSignIn.instance.authenticationEvents.listen((
        event,
      ) {
        if (event is! GoogleSignInAuthenticationEventSignIn) return;
        final idToken = event.user.authentication.idToken;
        if (idToken == null) return;
        _signInAnotherWay(() => continueWithGoogleIdToken(idToken));
      }, onError: (Object e) => _fail(authErrorMessage(e)));
    }
  }

  @override
  void dispose() {
    _googleWebEvents?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _signInWithPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _fail('Enter your email and password.');
      return;
    }
    await _run(
      () => signInWithPasswordAndLink(
        email: email,
        password: password,
        pending: _pending,
      ),
    );
  }

  /// Signs in to the existing account with one of its other providers,
  /// then links the pending one.
  Future<void> _signInAnotherWay(
    Future<SocialSignInResult> Function() signIn,
  ) async {
    await _run(() async {
      final result = await signIn();
      switch (result) {
        case SocialSignedIn():
          await linkPending(_pending);
        case SocialCancelled():
          throw const _Cancelled();
        case SocialNeedsExistingAccount():
          throw const AuthFailure(
            'This account has a password — enter it above to connect.',
          );
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('${_pending.provider.label} connected.')),
      );
    } on _Cancelled {
      // Nothing to report.
    } catch (e) {
      if (FirebaseAuth.instance.currentUser != null) {
        // Signed in, only the link failed: the user is in their account,
        // so let them carry on and say what didn't work.
        navigator.pop();
        messenger.showSnackBar(SnackBar(content: Text(authErrorMessage(e))));
        return;
      }
      _fail(authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _fail('Enter your email first.');
      return;
    }
    try {
      await sendPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _error = null;
        _info = _pending.provider == SocialProvider.google
            ? 'Reset link sent to $email. After setting a new password, '
                  'sign in here — or just use Continue with Google, which '
                  'will then connect to this account by itself.'
            : 'Reset link sent to $email. Set a new password, then sign '
                  'in here to connect ${_pending.provider.label}.';
      });
    } catch (e) {
      _fail(authErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providerName = _pending.provider.label;
    final who = _pending.email ?? 'This email';

    return AlertDialog(
      title: Text('Connect $providerName to your account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$who already has a Havruta account. Sign in to it the way '
              'you usually do and $providerName will be connected to it — '
              'your challenges and progress stay exactly as they are.',
              style: theme.textTheme.bodyMedium,
            ),
            if (_pending.mayHavePassword) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                enabled: _pending.email == null,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => _signInWithPassword(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              ElevatedButton(
                onPressed: _busy ? null : _signInWithPassword,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Sign in & connect $providerName'),
              ),
            ],
            for (final other in _pending.otherProviders)
              if (other == SocialProvider.google ? googleSignInAvailable : facebookSignInAvailable) ...[
                const SizedBox(height: 12),
                if (other == SocialProvider.google && kIsWeb)
                  LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: googleWebButton(width: constraints.maxWidth),
                    ),
                  )
                else
                  _SocialButton(
                    provider: other,
                    onPressed: _busy
                        ? null
                        : () => _signInAnotherWay(
                            other == SocialProvider.google
                                ? signInWithGoogle
                                : signInWithFacebook,
                          ),
                  ),
              ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (_info != null) ...[
              const SizedBox(height: 12),
              Text(_info!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
