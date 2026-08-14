import 'package:flutter/material.dart';

import '../services/firestore_service.dart';

class GoalsBucketBottomSheet extends StatelessWidget {
  final String uid;

  const GoalsBucketBottomSheet({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Want to use an already existing goal?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a goal to use it, or dismiss to type a new one.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<String>>(
            stream: firestoreService.getUserGoals(uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final goals = snapshot.data ?? [];

              if (goals.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No goals in your bucket yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return Column(
                children: goals
                    .map(
                      (goal) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(goal),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                        ),
                        onTap: () => Navigator.pop(context, goal),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
