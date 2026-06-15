import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'services/firestore_service.dart';
import 'competition_invite_section.dart';
import 'goals_bucket_bottom_sheet.dart';

class CreateCompetitionScreen extends StatefulWidget {
  const CreateCompetitionScreen({super.key});

  @override
  State<CreateCompetitionScreen> createState() =>
      _CreateCompetitionScreenState();
}

class _CreateCompetitionScreenState extends State<CreateCompetitionScreen> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final goalTitleController = TextEditingController();
  final targetValueController = TextEditingController();
  final unitController = TextEditingController();
  final _goalFocusNode = FocusNode();

  final firestoreService = FirestoreService();
  final user = FirebaseAuth.instance.currentUser;

  bool isLoading = false;
  String? createdCompetitionId;
  String? createdCompetitionTitle;

  Future<void> _showGoalsBucketSheet() async {
    // Only open the sheet when the field is empty — otherwise let the user edit directly
    if (goalTitleController.text.isNotEmpty) return;

    FocusScope.of(context).unfocus();

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GoalsBucketBottomSheet(uid: user!.uid),
    );

    if (selected != null) {
      goalTitleController.text = selected;
    } else {
      // User dismissed without picking — let them type manually
      _goalFocusNode.requestFocus();
    }
  }

  Future<void> createCompetition() async {
    final title = titleController.text.trim();
    final description = descriptionController.text.trim();
    final goalTitle = goalTitleController.text.trim();
    final targetValueText = targetValueController.text.trim();
    final unit = unitController.text.trim();

    if (title.isEmpty ||
        description.isEmpty ||
        goalTitle.isEmpty ||
        targetValueText.isEmpty ||
        unit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final targetValue = int.tryParse(targetValueText);

    if (targetValue == null || targetValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target value must be a positive number')),
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
        createdBy: user!.uid,
        creatorUsername: creatorUsername,
        goalTitle: goalTitle,
        targetValue: targetValue,
        unit: unit,
      );

      final goalExists = await firestoreService.goalExistsInBucket(
        user!.uid,
        goalTitle,
      );
      if (!goalExists) {
        await firestoreService.addGoal(user!.uid, goalTitle);
      }

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
    goalTitleController.dispose();
    targetValueController.dispose();
    unitController.dispose();
    _goalFocusNode.dispose();
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
              controller: goalTitleController,
              focusNode: _goalFocusNode,
              enabled: !alreadyCreated,
              onTap: _showGoalsBucketSheet,
              decoration: const InputDecoration(
                labelText: 'My goal',
                hintText: 'Get fitter / Study more / Read more',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: targetValueController,
              enabled: !alreadyCreated,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'My target value',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: unitController,
              enabled: !alreadyCreated,
              decoration: const InputDecoration(
                labelText: 'My unit',
                hintText: 'pushups / minutes / pages / km',
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