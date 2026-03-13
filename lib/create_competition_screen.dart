import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firestore_service.dart';

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

  final firebaseService = FirestoreService();
  final user = FirebaseAuth.instance.currentUser;

  bool isLoading = false;

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
      await firebaseService.createCompetition(
        title: title,
        description: description,
        targetNumber: targetNumber,
        unit: unit,
        createdBy: user!.uid,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Competition created')),
      );

      Navigator.pop(context);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Competition'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Competition title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: targetNumberController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: unitController,
              decoration: const InputDecoration(
                labelText: 'Unit',
                hintText: 'pushups / km / pages',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
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
          ],
        ),
      ),
    );
  }
}