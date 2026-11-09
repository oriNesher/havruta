import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_gate.dart';
import 'auth_service.dart' as auth_service;

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {

  final usernameController = TextEditingController();

  final user = FirebaseAuth.instance.currentUser!;
  final db = FirebaseFirestore.instance;

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Google/Facebook accounts arrive with a name; offer it as a starting
    // point (spaces dropped), still fully editable.
    final suggestion = user.displayName?.replaceAll(RegExp(r'\s+'), '');
    if (suggestion != null && suggestion.isNotEmpty) {
      usernameController.text = suggestion;
    }
  }

  /// For someone who signed in with the wrong account: back to the login
  /// screen, removing the just-created sign-in account while it still has
  /// no profile.
  Future<void> _useDifferentAccount() async {
    setState(() => _leaving = true);
    final navigator = Navigator.of(context);
    await auth_service.abandonUnfinishedSignIn();
    // Email sign-up pushes this screen as its own route; drop it so the
    // root AuthGate's login screen is what's left.
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> saveUsername() async {

    final username = usernameController.text.trim();

    if (username.isEmpty) return;

    await db.collection('users').doc(user.uid).set({
      "uid": user.uid,
      "email": user.email,
      "emailLower": user.email?.toLowerCase(),
      "username": username,
      "usernameLower": username.toLowerCase(),
      "createdAt": FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        // Re-enters AuthGate (rather than going to HomeScreen directly) so
        // its pending-invite-link check runs for newly-registered users too.
        builder: (context) => const AuthGate(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Choose username")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            const Text(
              "Choose a username",
              style: TextStyle(fontSize: 22),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                labelText: "Username",
              ),
            ),

            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: _leaving ? null : saveUsername,
              child: const Text("Continue"),
            ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: _leaving ? null : _useDifferentAccount,
              child: Text(
                user.email == null
                    ? 'Not you? Use a different account'
                    : 'Not ${user.email}? Use a different account',
              ),
            ),
          ],
        ),
      ),
    );
  }
}