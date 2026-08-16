import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/firestore_service.dart';
import 'challenge_invite_screen.dart';
import 'goals_bucket_bottom_sheet.dart';
import 'widgets/challenge_creation_stepper.dart';

class CreateCompetitionScreen extends StatefulWidget {
  const CreateCompetitionScreen({super.key});

  @override
  State<CreateCompetitionScreen> createState() =>
      _CreateCompetitionScreenState();
}

class _CreateCompetitionScreenState extends State<CreateCompetitionScreen> {
  String _selectedType = 'sharedGoalChallenge';

  final _titleController = TextEditingController();
  final _goalController = TextEditingController();
  final _targetController = TextEditingController();
  final _unitController = TextEditingController();
  final _deadlineController = TextEditingController();
  final _rulesController = TextEditingController();

  String? _linkedGoalTitle;

  final _firestoreService = FirestoreService();
  final _user = FirebaseAuth.instance.currentUser;

  bool _isLoading = false;

  bool get _isPersonal => _selectedType == 'personalGoalChallenge';

  @override
  void initState() {
    super.initState();
    _goalController.addListener(_syncTargetFromGoal);
  }

  // Detects the first number typed in the goal field (e.g. "Run 30km") and
  // mirrors it into Target. Always resyncs on every goal edit — a manual
  // edit to Target sticks only until the goal text changes again.
  void _syncTargetFromGoal() {
    final match = RegExp(r'\d+').firstMatch(_goalController.text);
    if (match != null) _targetController.text = match.group(0)!;
  }

  void _onTypeChanged(String newType) {
    setState(() {
      _selectedType = newType;
      _linkedGoalTitle = null;
    });
  }

  Future<void> _openGoalsBucketForLinkedGoal() async {
    FocusScope.of(context).unfocus();

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => GoalsBucketBottomSheet(uid: _user!.uid),
    );

    if (selected != null) {
      setState(() => _linkedGoalTitle = selected);
    }
  }

  Future<void> _createChallenge() async {
    final titleText = _titleController.text.trim();
    final goalText = _goalController.text.trim();
    final targetText = _targetController.text.trim();
    final unit = _unitController.text.trim();
    final deadline = _deadlineController.text.trim();
    final rules = _rulesController.text.trim();

    if (goalText.isEmpty || targetText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isPersonal
                ? 'Please fill in My personal goal and Target'
                : 'Please fill in Shared goal and Target',
          ),
        ),
      );
      return;
    }

    final challengeName = titleText.isEmpty ? goalText : titleText;

    final targetValue = int.tryParse(targetText);
    if (targetValue == null || targetValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target must be a positive number')),
      );
      return;
    }

    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logged in user found')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = _user.uid;
      final creatorUsername = await _firestoreService.getMyUsername(uid);

      if (creatorUsername == null || creatorUsername.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find your username')),
        );
        return;
      }

      String competitionId;
      String? createdGoalTitle;
      int? createdTargetValue;
      String? createdUnit;
      String? createdSharedGoalTitle;
      int? createdSharedTargetValue;
      String? createdSharedUnit;

      if (_isPersonal) {
        competitionId = await _firestoreService.createCompetition(
          title: challengeName,
          description: rules,
          createdBy: uid,
          creatorUsername: creatorUsername,
          goalTitle: goalText,
          targetValue: targetValue,
          unit: unit,
          deadline: deadline.isNotEmpty ? deadline : null,
          linkedGoalTitle: _linkedGoalTitle,
        );
        createdGoalTitle = goalText;
        createdTargetValue = targetValue;
        createdUnit = unit;

        final goalExists = await _firestoreService.goalExistsInBucket(
          uid,
          goalText,
        );
        if (!goalExists) {
          await _firestoreService.addGoal(uid, goalText);
        }
      } else {
        competitionId = await _firestoreService.createSharedGoalCompetition(
          title: challengeName,
          description: rules,
          createdBy: uid,
          creatorUsername: creatorUsername,
          sharedGoalTitle: goalText,
          sharedTargetValue: targetValue,
          sharedUnit: unit,
          deadline: deadline.isNotEmpty ? deadline : null,
        );
        createdSharedGoalTitle = goalText;
        createdSharedTargetValue = targetValue;
        createdSharedUnit = unit;
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeInviteScreen(
            competitionId: competitionId,
            competitionTitle: challengeName,
            competitionType: _selectedType,
            currentUserUid: uid,
            sharedGoalTitle: createdSharedGoalTitle,
            sharedTargetValue: createdSharedTargetValue,
            sharedUnit: createdSharedUnit,
            creatorGoalTitle: createdGoalTitle,
            creatorTargetValue: createdTargetValue,
            creatorUnit: createdUnit,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating challenge: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _goalController.removeListener(_syncTargetFromGoal);
    _titleController.dispose();
    _goalController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    _deadlineController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  Widget _fieldSection(String label, String tooltip, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: tooltip,
              triggerMode: TooltipTriggerMode.tap,
              preferBelow: false,
              child: const Icon(Icons.info_outline, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('New Challenge')),
      bottomNavigationBar: const ChallengeCreationStepper(currentStep: 1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type selector
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'personalGoalChallenge',
                  label: Text('Personal Goal'),
                ),
                ButtonSegment(
                  value: 'sharedGoalChallenge',
                  label: Text('Shared Goal'),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (selection) =>
                  _onTypeChanged(selection.first),
              style: ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(height: 16),

            // Type header and description
            Row(
              children: [
                Text(
                  _isPersonal
                      ? 'Personal Goal Challenge'
                      : 'Shared Goal Challenge',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: _isPersonal
                      ? "It's not always easy to find someone with the exact same goal as you. "
                          "Personal Goal Challenges let everyone work on their own goal, while still "
                          "sharing the motivation, accountability, and fun of a competition."
                      : "Everyone works toward the same goal, target, and unit. "
                          "You each track your own progress, and the first to reach the shared target wins.",
                  triggerMode: TooltipTriggerMode.tap,
                  preferBelow: false,
                  child: const Icon(Icons.info_outline, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _isPersonal
                  ? 'Work on your own goal, compete together.'
                  : 'Everyone works toward the same goal — first to reach it wins.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 28),

            // Goal field — label changes based on type
            _fieldSection(
              _isPersonal ? 'My personal goal' : 'Shared goal',
              _isPersonal
                  ? 'Something specific you can track with a number. '
                      'e.g. "Run 30km" or "Read 4 books" — not a vague long-term aspiration.'
                  : 'The specific, measurable goal everyone will work toward. '
                      'e.g. "Run 30km" or "Read 4 books".',
              TextField(
                controller: _goalController,
                decoration: InputDecoration(
                  hintText: 'Run 30km / Read 4 books / Do 300 pushups',
                  helperText: _isPersonal
                      ? 'Make it specific and measurable'
                      : 'Everyone will work toward this same goal',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Target
            _fieldSection(
              'Target',
              'The number you need to reach to complete the goal. e.g. 30 or 4.',
              TextField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '30',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Optional section header
            Row(
              children: [
                Text(
                  'Add more details',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'optional',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Title
            _fieldSection(
              'Title',
              'A name for this challenge. Leave it blank and the goal text will be used instead. '
              'e.g. "Family Health Challenge" or "Reading Challenge".',
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: 'Family Health Challenge',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Unit
            _fieldSection(
              'Unit',
              'How your target is measured. e.g. days, books, km. '
              'Skip this and progress will show as a number or percentage.',
              TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  hintText: 'days / books / km',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Connect to a bigger goal — Personal Goal only
            if (_isPersonal) ...[
              _fieldSection(
                'Connect to a bigger goal',
                'Link this challenge to one of your long-term goals. '
                'It connects the challenge to your personal growth journey.',
                InkWell(
                  onTap: _openGoalsBucketForLinkedGoal,
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.chevron_right),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                    ),
                    child: Text(
                      _linkedGoalTitle ?? 'Tap to select from your goals',
                      style: TextStyle(
                        color: _linkedGoalTitle == null
                            ? theme.hintColor
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              if (_linkedGoalTitle != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _linkedGoalTitle = null),
                    child: const Text('Remove'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Deadline or duration
            _fieldSection(
              'Deadline or duration',
              'Add a time frame if you want. e.g. "30 days" or "By August 1st".',
              TextField(
                controller: _deadlineController,
                decoration: const InputDecoration(
                  hintText: '30 days / By August 1st',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Rules or notes
            _fieldSection(
              'Rules or notes',
              'Any extra rules or clarifications. '
              'e.g. "Weekends count too" or "Only gym workouts count".',
              TextField(
                controller: _rulesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Weekends count too...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Create button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _createChallenge,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Challenge'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
