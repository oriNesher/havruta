import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../home/home_pending_invites_section.dart';

class PendingInvitesScreen extends StatelessWidget {
  const PendingInvitesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pending Invites')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: HomePendingInvitesSection(uid: user.uid),
      ),
    );
  }
}
