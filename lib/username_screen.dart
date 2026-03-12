import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {

  final usernameController = TextEditingController();

  final user = FirebaseAuth.instance.currentUser!;
  final db = FirebaseFirestore.instance;

  Future<void> saveUsername() async {

    final username = usernameController.text.trim();

    if (username.isEmpty) return;

    await db.collection('users').doc(user.uid).set({
      "uid": user.uid,
      "email": user.email,
      "username": username,
      "usernameLower": username.toLowerCase(),
      "createdAt": FieldValue.serverTimestamp(),
    });

    Navigator.pop(context);
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
              onPressed: saveUsername,
              child: const Text("Continue"),
            ),
          ],
        ),
      ),
    );
  }
}