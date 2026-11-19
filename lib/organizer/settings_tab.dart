import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../competitions/challenge.dart';
import '../competitions/widgets/confirm_irreversible_dialog.dart';
import '../services/firestore_service.dart';
import 'format.dart';
import 'organizer_service.dart';

/// Edit the challenge after launch, manage co-organizers, end it early.
/// What may change when is decided server-side (planSettingsChange); this
/// form only offers what the mode has and shows the server's refusal as-is.
class SettingsTab extends StatefulWidget {
  final Challenge challenge;
  final String uid;

  const SettingsTab({super.key, required this.challenge, required this.uid});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _organizer = OrganizerService();
  late final _title = TextEditingController(text: widget.challenge.title);
  late final _description =
      TextEditingController(text: widget.challenge.description);
  late final _dailyMinimum = TextEditingController(
    text: widget.challenge.rules.dailyMinimum?.toString() ?? '',
  );
  late final _target = TextEditingController(
    text: widget.challenge.targetValue?.toString() ?? '',
  );
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _endsAtCleared = false;
  bool _saving = false;

  Challenge get challenge => widget.challenge;

  bool get _canEditRules => challenge.isActive;
  bool get _notStarted =>
      challenge.startsAt != null && challenge.startsAt!.isAfter(DateTime.now());
  bool get _isLos => challenge.winCondition == WinCondition.lastStanding;
  bool get _isRace =>
      challenge.winCondition == WinCondition.firstToTarget &&
      !challenge.isLegacyPersonal;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _dailyMinimum.dispose();
    _target.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _save() async {
    final title = _title.text.trim();
    final description = _description.text.trim();
    final minimum = _int(_dailyMinimum);
    final target = _int(_target);

    setState(() => _saving = true);
    try {
      await _organizer.updateSettings(
        challenge.id,
        title: title != challenge.title ? title : null,
        description: description != challenge.description ? description : null,
        startsAt: _startsAt,
        endsAt: _endsAt,
        clearEndsAt: _endsAtCleared,
        dailyMinimum: _isLos && minimum != challenge.rules.dailyMinimum
            ? minimum
            : null,
        targetValue: _isRace && target != challenge.targetValue ? target : null,
      );
      setState(() {
        _startsAt = null;
        _endsAt = null;
        _endsAtCleared = false;
      });
      _toast('Saved');
    } catch (e) {
      _toast(organizerErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Picks a calendar day; the challenge's boundaries are midnights in the
  /// organizer's own calendar, the same convention as Create Challenge.
  Future<DateTime?> _pickDay({required String help, DateTime? initial}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return showDatePicker(
      context: context,
      initialDate: initial ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 2)),
      helpText: help,
    );
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await _pickDay(
      help: 'Day 1',
      initial: DateTime(now.year, now.month, now.day + 1),
    );
    if (picked == null) return;
    if (!picked.isAfter(DateTime.now())) {
      _toast('The new start has to be in the future — pick tomorrow or later.');
      return;
    }
    setState(() => _startsAt = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDay(help: 'Challenge ends after');
    if (picked == null) return;
    setState(() {
      _endsAt = DateTime(picked.year, picked.month, picked.day + 1);
      _endsAtCleared = false;
    });
  }

  Future<void> _endEarly() async {
    final consequences = switch (challenge.winCondition) {
      WinCondition.firstToTarget => [
        'If nobody has finished, whoever is furthest along wins.',
        'Nobody can log progress after this.',
      ],
      WinCondition.mostProgress => [
        'Whoever has the most progress right now wins.',
        'Nobody can log progress after this.',
      ],
      WinCondition.lastStanding => [
        "Days that have ended are judged; today doesn't count.",
        'Everyone still standing shares the win.',
      ],
    };
    final reason = await confirmIrreversible(
      context,
      what: 'End ${challenge.title} now?',
      consequences: consequences,
      confirmLabel: 'End Challenge',
      reasonHint: 'Reason (optional, for the activity log)',
    );
    if (reason == null) return;
    try {
      final winners = await _organizer.endEarly(challenge.id, reason: reason);
      _toast(winners.isEmpty
          ? 'Challenge ended — no winner'
          : 'Challenge ended — ${winners.length == 1 ? 'a winner' : '${winners.length} winners'} announced');
    } catch (e) {
      _toast(organizerErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final endsAt = _endsAtCleared ? null : (_endsAt ?? challenge.endsAt);
    final startsAt = _startsAt ?? challenge.startsAt;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Challenge',
          children: [
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Rules & notes'),
            ),
            if (_canEditRules) ...[
              const SizedBox(height: 8),
              if (_notStarted)
                _DateRow(
                  label: 'Starts',
                  value: startsAt == null ? '—' : formatDate(startsAt),
                  onChange: _pickStart,
                ),
              _DateRow(
                label: 'Ends',
                value: endsAt == null
                    ? 'No end date'
                    : 'After ${formatDate(endsAt.subtract(const Duration(days: 1)))}',
                onChange: _pickEnd,
                onClear: endsAt != null &&
                        challenge.winCondition != WinCondition.mostProgress
                    ? () => setState(() {
                        _endsAt = null;
                        _endsAtCleared = true;
                      })
                    : null,
              ),
              if (_isLos) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _dailyMinimum,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Daily minimum',
                    suffixText: challenge.unit.isEmpty ? null : challenge.unit,
                    helperText: 'Applies from today on; days already judged '
                        "don't change.",
                  ),
                ),
              ],
              if (_isRace) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _target,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Target',
                    suffixText: challenge.unit.isEmpty ? null : challenge.unit,
                    helperText: 'Raise it any time. Lower it only above '
                        "everyone's current progress.",
                  ),
                ),
              ],
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "This challenge is over, so only its title and notes can "
                  'change.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save changes'),
              ),
            ),
          ],
        ),
        if (challenge.isActive) ...[
          const SizedBox(height: 16),
          _CommunitySection(challenge: challenge),
          const SizedBox(height: 16),
          _TeamsSection(challenge: challenge),
        ],
        const SizedBox(height: 16),
        _OrganizersSection(challenge: challenge, uid: widget.uid),
        if (challenge.isActive) ...[
          const SizedBox(height: 16),
          _Section(
            title: 'End the challenge',
            danger: true,
            children: [
              Text(
                'Stop it now and decide the result from where everyone '
                'stands. Winners get their celebration.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _endEarly,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('End challenge now…'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Co-organizers: listed by name, added by username, removed with a
/// confirm. The server keeps at least one.
class _OrganizersSection extends StatefulWidget {
  final Challenge challenge;
  final String uid;

  const _OrganizersSection({required this.challenge, required this.uid});

  @override
  State<_OrganizersSection> createState() => _OrganizersSectionState();
}

class _OrganizersSectionState extends State<_OrganizersSection> {
  final _organizer = OrganizerService();
  final _firestore = FirestoreService();
  final _username = TextEditingController();
  final Map<String, Future<String?>> _names = {};
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<String?> _nameOf(String uid) =>
      _names.putIfAbsent(uid, () => _firestore.getUsernameByUid(uid));

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final name = _username.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final user = await _firestore.findUserByUsername(name);
      final uid = user?['uid'] as String?;
      if (uid == null) {
        _toast('No user called "$name"');
        return;
      }
      await _organizer.addOrganizer(widget.challenge.id, uid);
      _username.clear();
      _toast('${user!['username']} is now an organizer');
    } catch (e) {
      _toast(organizerErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String uid, String name) async {
    final self = uid == widget.uid;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(self ? 'Stop organizing?' : 'Remove $name as organizer?'),
        content: Text(self
            ? "You'll lose access to this dashboard. If you also compete, "
                "you stay in the challenge."
            : "They'll lose access to this dashboard. If they also compete, "
                'they stay in the challenge.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (go != true) return;
    try {
      await _organizer.removeOrganizer(widget.challenge.id, uid);
      _toast('$name is no longer an organizer');
    } catch (e) {
      _toast(organizerErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final organizers = widget.challenge.organizerUids;
    return _Section(
      title: 'Organizers',
      children: [
        for (final uid in organizers)
          FutureBuilder<String?>(
            future: _nameOf(uid),
            builder: (context, snapshot) {
              final name = snapshot.data ?? '…';
              final competes = widget.challenge.isParticipant(uid);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: Text(uid == widget.uid ? '$name (you)' : name),
                subtitle: Text(competes ? 'Organizes and competes' : 'Organizes'),
                trailing: organizers.length > 1
                    ? IconButton(
                        tooltip: 'Remove as organizer',
                        icon: const Icon(Icons.close),
                        onPressed: () => _remove(uid, name),
                      )
                    : null,
              );
            },
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _username,
                onSubmitted: (_) => _add(),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Add a co-organizer by username',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _add,
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool danger;

  const _Section({
    required this.title,
    required this.children,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: danger
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppTheme.display(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: danger ? scheme.error : null,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onChange;
  final VoidCallback? onClear;

  const _DateRow({
    required this.label,
    required this.value,
    required this.onChange,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (onClear != null)
            TextButton(onPressed: onClear, child: const Text('Remove')),
          TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}

/// How the social layer scales, and whether Trash Talk is on. Each change
/// saves immediately (and lands in the activity log).
class _CommunitySection extends StatefulWidget {
  final Challenge challenge;

  const _CommunitySection({required this.challenge});

  @override
  State<_CommunitySection> createState() => _CommunitySectionState();
}

class _CommunitySectionState extends State<_CommunitySection> {
  final _organizer = OrganizerService();
  bool _busy = false;

  Future<void> _save(Future<void> Function() change, String done) async {
    setState(() => _busy = true);
    try {
      await change();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(organizerErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final challenge = widget.challenge;
    final count = challenge.participantUids.length;
    final now = challenge.isLarge
        ? 'Right now it behaves as a large community ($count participants).'
        : 'Right now it behaves as a friend challenge ($count participants).';

    return _Section(
      title: 'Community',
      children: [
        Text(
          "Size decides who sees what. A friend challenge shows everyone "
          "everything. A large community shows each person what's near "
          "them on the leaderboard, people they follow, their team and "
          "the big moments, and sends one daily digest at 20:00 instead "
          "of a notification per entry.",
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'auto',
              label: Text('Automatic'),
              tooltip: 'Large above ${Challenge.largeThreshold} participants',
            ),
            ButtonSegment(value: 'small', label: Text('Friend challenge')),
            ButtonSegment(value: 'large', label: Text('Large community')),
          ],
          selected: {challenge.socialScale},
          onSelectionChanged: _busy
              ? null
              : (selection) => _save(
                  () => _organizer.updateSettings(
                    challenge.id,
                    scale: selection.first,
                  ),
                  'Community size saved',
                ),
        ),
        const SizedBox(height: 6),
        Text(now, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Trash Talk'),
          subtitle: Text(
            challenge.trashTalkSetting == null
                ? 'Default: '
                    '${challenge.trashTalkEnabled ? 'on' : 'off'} for this '
                    'challenge. After a celebration, people can write and '
                    'share a brag.'
                : 'After a celebration, people can write and share a '
                    'brag.',
          ),
          value: challenge.trashTalkEnabled,
          onChanged: _busy
              ? null
              : (on) => _save(
                  () => _organizer.updateSettings(
                    challenge.id,
                    setTrashTalk: true,
                    trashTalk: on,
                  ),
                  on ? 'Trash Talk on' : 'Trash Talk off',
                ),
        ),
      ],
    );
  }
}

/// Create, rename and delete teams; people are put on teams from the
/// Participants tab.
class _TeamsSection extends StatefulWidget {
  final Challenge challenge;

  const _TeamsSection({required this.challenge});

  @override
  State<_TeamsSection> createState() => _TeamsSectionState();
}

class _TeamsSectionState extends State<_TeamsSection> {
  final _organizer = OrganizerService();
  late final Stream<Map<String, String>> _teams =
      FirestoreService().getTeams(widget.challenge.id);
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      _toast(done);
    } catch (e) {
      _toast(organizerErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await _run(() async {
      await _organizer.createTeam(widget.challenge.id, name);
      _name.clear();
    }, 'Team $name created');
  }

  Future<void> _rename(String teamId, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename team'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Team name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == current) return;
    await _run(
      () => _organizer.renameTeam(widget.challenge.id, teamId, name),
      'Renamed to $name',
    );
  }

  Future<void> _delete(String teamId, String name) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete team $name?'),
        content: const Text(
          "Its members stay in the challenge with their progress; they're "
          'just no longer on a team.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete team'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await _run(
      () => _organizer.deleteTeam(widget.challenge.id, teamId),
      'Team $name deleted',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      title: 'Teams',
      children: [
        Text(
          'Optional. Teams get their own leaderboard (average progress per '
          "member, so team size doesn't decide it), and in a large "
          "community teammates see each other's activity. Individual "
          'winners are unchanged. Put people on teams from the '
          'Participants tab.',
          style: theme.textTheme.bodySmall,
        ),
        StreamBuilder<Map<String, String>>(
          stream: _teams,
          builder: (context, snapshot) {
            final teams = snapshot.data ?? const {};
            return Column(
              children: [
                for (final MapEntry(key: id, value: name) in teams.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(name),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Rename',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _busy ? null : () => _rename(id, name),
                        ),
                        IconButton(
                          tooltip: 'Delete team',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy ? null : () => _delete(id, name),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                maxLength: 40,
                onSubmitted: (_) => _create(),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'New team name',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: const Text('Add team'),
            ),
          ],
        ),
      ],
    );
  }
}
