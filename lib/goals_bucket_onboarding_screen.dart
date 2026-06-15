import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'services/firestore_service.dart';
import 'home_screen.dart';

class GoalsBucketOnboardingScreen extends StatefulWidget {
  const GoalsBucketOnboardingScreen({super.key});

  @override
  State<GoalsBucketOnboardingScreen> createState() =>
      _GoalsBucketOnboardingScreenState();
}

class _GoalsBucketOnboardingScreenState
    extends State<GoalsBucketOnboardingScreen> {
  final List<TextEditingController> _controllers = [TextEditingController()];
  final _firestoreService = FirestoreService();
  final _user = FirebaseAuth.instance.currentUser!;
  bool _isLoading = false;

  bool get _hasAtLeastOneGoal =>
      _controllers.any((c) => c.text.trim().isNotEmpty);

  void _addField() {
    if (_controllers.length >= 5) return;
    setState(() => _controllers.add(TextEditingController()));
  }

  Future<void> _save() async {
    final goals = _controllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (goals.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      await _firestoreService.addGoalsBatch(_user.uid, goals);
      await _firestoreService.markGoalsBucketCompleted(_user.uid);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving goals: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text(
                'What are two of your long term goals?',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Add two goals to your bucket. Later, you'll be able to create competition around them",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              ...List.generate(
                _controllers.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _controllers[i],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Goal ${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
              if (_controllers.length < 5)
                TextButton.icon(
                  onPressed: _addField,
                  icon: const Icon(Icons.add),
                  label: const Text('Add another goal'),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_hasAtLeastOneGoal && !_isLoading) ? _save : null,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
