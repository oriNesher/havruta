import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../app_theme.dart';
import '../home/home_pending_invites_section.dart';
import 'respect_notifications_section.dart';

class PendingInvitesScreen extends StatelessWidget {
  const PendingInvitesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESPECT',
              style: AppTheme.display(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            RespectNotificationsSection(uid: user.uid),
            const SizedBox(height: 24),
            Text(
              'INVITES',
              style: AppTheme.display(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            HomePendingInvitesSection(uid: user.uid),
          ],
        ),
      ),
    );
  }
}
