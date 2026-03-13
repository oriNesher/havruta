import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'services/firestore_service.dart';
import 'competition_invite_section.dart';

class CreateCompetitionScreen extends StatefulWidget {
  const CreateCompetitionScreen({super.key});

  @override
  State<CreateCompetitionScreen> createState() =>
      _CreateCompetitionScreenState();
}

class _CreateCompetitionScreenState extends State<CreateCompetitionScreen> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final targetNumberController = TextEditingController();
  final unitController = TextEditingController();

  final firestoreService = FirestoreService();
  final user = FirebaseAuth.instance.currentUser;

  bool isLoading = false;
  String? createdCompetitionId;
  String? createdCompetitionTitle;

  Future<void> createCompetition() async {
    final title = titleController.text.trim();
    final description = descriptionController.text.trim();
    final targetNumberText = targetNumberController.text.trim();
    final unit = unitController.text.trim();

    if (title.isEmpty ||
        description.isEmpty ||
        targetNumberText.isEmpty ||
        unit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final targetNumber = int.tryParse(targetNumberText);

    if (targetNumber == null || targetNumber <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target number must be a positive number')),
      );
      return;
    }

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logged in user found')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final creatorUsername = await firestoreService.getMyUsername(user!.uid);

      if (creatorUsername == null || creatorUsername.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find your username')),
        );
        return;
      }

      final competitionId = await firestoreService.createCompetition(
        title: title,
        description: description,
        targetNumber: targetNumber,
        unit: unit,
        createdBy: user!.uid,
        creatorUsername: creatorUsername,
      );

      if (!mounted) return;

      setState(() {
        createdCompetitionId = competitionId;
        createdCompetitionTitle = title;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Competition created')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating competition: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    targetNumberController.dispose();
    unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alreadyCreated = createdCompetitionId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Competition'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              enabled: !alreadyCreated,
              decoration: const InputDecoration(
                labelText: 'Competition title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              enabled: !alreadyCreated,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: targetNumberController,
              enabled: !alreadyCreated,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: unitController,
              enabled: !alreadyCreated,
              decoration: const InputDecoration(
                labelText: 'Unit',
                hintText: 'pushups / km / pages',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            if (!alreadyCreated)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : createCompetition,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create'),
                ),
              ),
            if (alreadyCreated) ...[
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Competition created successfully. You can invite users now.',
                ),
              ),
              const SizedBox(height: 24),
              CompetitionInviteSection(
                competitionId: createdCompetitionId!,
                competitionTitle: createdCompetitionTitle ?? '',
                currentUserUid: user!.uid,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}