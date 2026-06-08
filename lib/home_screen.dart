import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'create_competition_screen.dart';
import 'services/firestore_service.dart';
import 'home_events_section.dart';
import 'home_pending_invites_section.dart';
import 'home_competitions_section.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('No logged in user')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Havruta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String?>(
              future: _firestoreService.getMyUsername(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Text(
                    'Hello...',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  );
                }
                final username = snapshot.data;
                return Text(
                  'Hello ${username ?? user.email ?? ""}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            HomeEventsSection(uid: user.uid),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateCompetitionScreen(),
                    ),
                  );
                },
                child: const Text('Create Competition'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Pending Invites',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            HomePendingInvitesSection(uid: user.uid),
            const SizedBox(height: 24),
            const Text(
              'My Competitions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            HomeCompetitionsSection(uid: user.uid),
          ],
        ),
      ),
    );
  }
}
