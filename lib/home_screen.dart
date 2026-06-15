import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'create_competition_screen.dart';
import 'pending_invites_screen.dart';
import 'services/firestore_service.dart';
import 'services/progress_snapshot_cache.dart';
import 'home_events_section.dart';
import 'home_competitions_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ProgressSnapshotCache.instance.persist(_firestoreService);
    }
  }

  Future<void> _signOut() async {
    await ProgressSnapshotCache.instance.persistAndClear(_firestoreService);
    await FirebaseAuth.instance.signOut();
  }

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
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestoreService.getPendingInvites(user.uid),
            builder: (context, snapshot) {
              final count = snapshot.data?.docs.length ?? 0;
              return IconButton(
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.mail_outline),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PendingInvitesScreen(),
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
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
