import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../app_theme.dart';
import 'auth_service.dart';
import 'social_auth_config.dart';

const _cardColor = Color(0xFF181824);
const _lineColor = Color(0xFF2A2A42);
const _mutedColor = Color(0xFF8888A0);
const _connectedColor = Color(0xFF2DD4BF);

/// Who you're signed in as, and which ways you can sign in. Existing users
/// connect Google or Facebook from here — linking keeps the same account,
/// so every challenge, progress report and Respect stays put. Also home to
/// sign-out.
class AccountScreen extends StatefulWidget {
  /// Clears per-user app state, then signs out (HomeScreen owns that).
  final Future<void> Function() onSignOut;

  const AccountScreen({super.key, required this.onSignOut});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
  _profileSub;
  String? _username;
  SocialProvider? _linking;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (doc) {
            if (mounted) {
              setState(() => _username = doc.data()?['username'] as String?);
            }
          },
          // Permission-denied lands here at sign-out; stay quiet.
          onError: (Object e) => debugPrint('Account profile stream: $e'),
        );
  }

  @override
  void dispose() {
    _profileSub.cancel();
    super.dispose();
  }

  Future<void> _connect(SocialProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _linking = provider);
    try {
      final linked = await linkProvider(provider);
      if (linked) {
        messenger.showSnackBar(
          SnackBar(content: Text('${provider.label} connected.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(authErrorMessage(e, provider: provider))),
      );
    } finally {
      if (mounted) setState(() => _linking = null);
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    final navigator = Navigator.of(context);
    await widget.onSignOut();
    // AuthGate shows the login screen underneath; drop back to it.
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold();
    final linked = user.providerData.map((p) => p.providerId).toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsFill.userCircle,
                  size: 40,
                  color: _mutedColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _username ?? '…',
                        style: AppTheme.display(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (user.email != null)
                        Text(
                          user.email!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _mutedColor),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'SIGN-IN METHODS',
            style: AppTheme.display(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: _mutedColor,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Connect another way to sign in to this same account. Your '
            'challenges and progress stay exactly as they are.',
            style: TextStyle(color: _mutedColor, fontSize: 13),
          ),
          const SizedBox(height: 12),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (linked.contains('password'))
                  _MethodRow(
                    icon: PhosphorIconsBold.envelopeSimple,
                    label: 'Email & password',
                    connected: true,
                  ),
                if (googleSignInAvailable)
                  _MethodRow(
                    icon: PhosphorIconsBold.googleLogo,
                    label: 'Google',
                    connected: linked.contains(SocialProvider.google.providerId),
                    busy: _linking == SocialProvider.google,
                    onConnect: _linking == null
                        ? () => _connect(SocialProvider.google)
                        : null,
                  ),
                if (facebookSignInAvailable)
                  _MethodRow(
                    icon: PhosphorIconsBold.facebookLogo,
                    label: 'Facebook',
                    connected: linked.contains(
                      SocialProvider.facebook.providerId,
                    ),
                    busy: _linking == SocialProvider.facebook,
                    onConnect: _linking == null
                        ? () => _connect(SocialProvider.facebook)
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _signingOut ? null : _signOut,
            icon: PhosphorIcon(PhosphorIconsFill.signOut, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _lineColor),
      ),
      child: child,
    );
  }
}

class _MethodRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool connected;
  final bool busy;
  final VoidCallback? onConnect;

  const _MethodRow({
    required this.icon,
    required this.label,
    required this.connected,
    this.busy = false,
    this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: PhosphorIcon(icon, color: Colors.white),
      title: Text(label),
      trailing: connected
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 16, color: _connectedColor),
                SizedBox(width: 6),
                Text('Connected', style: TextStyle(color: _connectedColor)),
              ],
            )
          : busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(onPressed: onConnect, child: const Text('Connect')),
    );
  }
}
