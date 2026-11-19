import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../competitions/challenge.dart';
import '../competitions/challenge_standings.dart';
import '../competitions/widgets/confirm_irreversible_dialog.dart';
import '../services/firestore_service.dart';
import '../services/platform_web.dart';
import 'format.dart';
import 'organizer_service.dart';
import 'participant_report.dart';

enum _Filter { all, notPaid, notLoggedToday, out }

/// Everyone in the challenge with status and progress, the paid flag, CSV
/// export, and the per-participant moderation actions (correct progress,
/// reinstate, remove).
class ParticipantsTab extends StatefulWidget {
  final Challenge challenge;

  const ParticipantsTab({super.key, required this.challenge});

  @override
  State<ParticipantsTab> createState() => _ParticipantsTabState();
}

class _ParticipantsTabState extends State<ParticipantsTab> {
  final _organizer = OrganizerService();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _participants =
      FirestoreService().getCompetitionParticipants(widget.challenge.id);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _organizerData =
      _organizer.organizerData(widget.challenge.id);
  late final Stream<Map<String, String>> _teams =
      FirestoreService().getTeams(widget.challenge.id);
  Map<String, String> _teamNames = const {};

  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  Challenge get challenge => widget.challenge;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      _toast(done);
    } catch (e) {
      _toast(organizerErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, String>>(
      stream: _teams,
      builder: (context, teamsSnapshot) {
        _teamNames = teamsSnapshot.data ?? const {};
        return _withPaid(context);
      },
    );
  }

  Widget _withPaid(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _organizerData,
      builder: (context, paidSnapshot) {
        final paidByUid = <String, bool>{
          for (final doc in paidSnapshot.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            doc.id: doc.data()['paid'] == true,
        };
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _participants,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final now = DateTime.now();
            final rows = ParticipantReport.build(
              challenge: challenge,
              ranked: rankParticipants(
                challenge,
                snapshot.data!.docs.map((d) => d.data()),
              ),
              paidByUid: paidByUid,
              now: now,
            );
            return _content(context, rows, now);
          },
        );
      },
    );
  }

  Widget _content(
    BuildContext context,
    List<ParticipantReport> rows,
    DateTime now,
  ) {
    final query = _search.text.trim().toLowerCase();
    final visible = rows.where((r) {
      if (query.isNotEmpty && !r.username.toLowerCase().contains(query)) {
        return false;
      }
      return switch (_filter) {
        _Filter.all => true,
        _Filter.notPaid => !r.paid,
        _Filter.notLoggedToday => r.today == 0 && !r.isEliminated,
        _Filter.out => r.isEliminated,
      };
    }).toList();

    final isLos = challenge.winCondition == WinCondition.lastStanding;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Stat(label: 'Participants', value: '${rows.length}'),
            _Stat(
              label: 'Paid',
              value: '${rows.where((r) => r.paid).length} / ${rows.length}',
            ),
            _Stat(
              label: 'Logged today',
              value: '${rows.where((r) => r.today > 0).length}',
            ),
            if (isLos)
              _Stat(
                label: 'Still in',
                value: '${rows.where((r) => !r.isEliminated).length}',
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search by name',
                ),
              ),
            ),
            for (final (filter, label) in [
              (_Filter.all, 'All'),
              (_Filter.notPaid, 'Not paid'),
              (_Filter.notLoggedToday, 'Not logged today'),
              if (isLos) (_Filter.out, 'Out'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              ),
            TextButton.icon(
              onPressed: rows.isEmpty ? null : () => _exportCsv(rows),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'Nobody has joined yet. Share the invite link from the '
                'Challenge page.',
              ),
            ),
          )
        else if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('Nobody matches.')),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 28,
                headingTextStyle: Theme.of(context).textTheme.labelMedium,
                columns: [
                  const DataColumn(label: Text('#'), numeric: true),
                  const DataColumn(label: Text('Name')),
                  if (_teamNames.isNotEmpty)
                    const DataColumn(label: Text('Team')),
                  const DataColumn(label: Text('Status')),
                  DataColumn(
                    label: Text(
                      challenge.unit.isEmpty
                          ? 'Progress'
                          : 'Progress (${challenge.unit})',
                    ),
                    numeric: true,
                  ),
                  const DataColumn(label: Text('Today'), numeric: true),
                  const DataColumn(label: Text('Last update')),
                  const DataColumn(label: Text('Paid')),
                  const DataColumn(label: Text('')),
                ],
                rows: [for (final r in visible) _row(r, now)],
              ),
            ),
          ),
      ],
    );
  }

  DataRow _row(ParticipantReport r, DateTime now) {
    final mono = AppTheme.mono(fontSize: 13);
    final progress = r.target == null
        ? '${r.progress}'
        : '${r.progress} / ${r.target}';
    return DataRow(
      cells: [
        DataCell(Text('${r.rank}', style: mono)),
        DataCell(Text(r.username)),
        if (_teamNames.isNotEmpty) DataCell(_teamPicker(r)),
        DataCell(_StatusChip(status: r.status, out: r.isEliminated)),
        DataCell(Text(progress, style: mono)),
        DataCell(Text('${r.today}', style: mono)),
        DataCell(Text(formatAgo(r.lastUpdate, now))),
        DataCell(
          Checkbox(
            value: r.paid,
            onChanged: (paid) => _run(
              () => _organizer.setPaid(challenge.id, r.uid, paid ?? false),
              paid == true
                  ? '${r.username} marked paid'
                  : '${r.username} marked not paid',
            ),
          ),
        ),
        DataCell(_actions(r)),
      ],
    );
  }

  Widget _teamPicker(ParticipantReport r) {
    final current = _teamNames.containsKey(r.teamId) ? r.teamId : null;
    return DropdownButton<String?>(
      value: current,
      underline: const SizedBox.shrink(),
      hint: const Text('—'),
      onChanged: challenge.isActive
          ? (teamId) {
              if (teamId == current) return;
              _run(
                () => _organizer.assignTeam(challenge.id, r.uid, teamId),
                teamId == null
                    ? '${r.username} is on no team'
                    : '${r.username} is on ${_teamNames[teamId]}',
              );
            }
          : null,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('No team')),
        for (final MapEntry(key: id, value: name) in _teamNames.entries)
          DropdownMenuItem<String?>(value: id, child: Text(name)),
      ],
    );
  }

  Widget _actions(ParticipantReport r) {
    final active = challenge.isActive;
    final canReinstate = active &&
        r.isEliminated &&
        challenge.winCondition == WinCondition.lastStanding;
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz),
      enabled: active,
      onSelected: (action) => switch (action) {
        'correct' => _correct(r),
        'reinstate' => _reinstate(r),
        'remove' => _remove(r),
        _ => null,
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'correct',
          enabled: !r.isEliminated,
          child: const ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Correct progress…'),
          ),
        ),
        if (canReinstate)
          const PopupMenuItem(
            value: 'reinstate',
            child: ListTile(
              leading: Icon(Icons.restore),
              title: Text('Reinstate…'),
            ),
          ),
        const PopupMenuItem(
          value: 'remove',
          child: ListTile(
            leading: Icon(Icons.person_remove_outlined),
            title: Text('Remove from challenge…'),
          ),
        ),
      ],
    );
  }

  Future<void> _correct(ParticipantReport r) async {
    final result = await showDialog<_Correction>(
      context: context,
      builder: (_) => _CorrectProgressDialog(challenge: challenge, row: r),
    );
    if (result == null) return;
    await _run(
      () => _organizer.correctProgress(
        challenge.id,
        uid: r.uid,
        progress: result.progress,
        dayKey: result.dayKey,
        reason: result.reason,
      ),
      "${r.username}'s progress set to ${result.progress}",
    );
  }

  Future<void> _reinstate(ParticipantReport r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Reinstate ${r.username}?',
        body:
            'Overrules their elimination on ${r.eliminatedOnDay}. They can '
            "log again right away and are judged from the next day that "
            "hasn't been judged yet; past days stay as they are.",
        confirmLabel: 'Reinstate',
      ),
    );
    if (reason == null) return;
    await _run(
      () => _organizer.reinstateParticipant(
        challenge.id,
        uid: r.uid,
        reason: reason,
      ),
      '${r.username} is back in',
    );
  }

  Future<void> _remove(ParticipantReport r) async {
    final reason = await confirmIrreversible(
      context,
      what: 'Remove ${r.username} from ${challenge.title}?',
      consequences: [
        'Their progress (${r.progress}${challenge.unit.isEmpty ? '' : ' ${challenge.unit}'}) '
            'and place on the leaderboard are deleted.',
        "They can't rejoin, even with an invite link.",
      ],
      confirmLabel: 'Remove',
      reasonHint: 'Reason (optional, for the activity log)',
    );
    if (reason == null) return;
    await _run(
      () => _organizer.removeParticipant(
        challenge.id,
        uid: r.uid,
        reason: reason,
      ),
      '${r.username} removed',
    );
  }

  Future<void> _exportCsv(List<ParticipantReport> rows) async {
    final csv = participantsCsv(challenge, rows, teamNames: _teamNames);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final name = challenge.title
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final downloaded = await downloadBytes(
      bytes: utf8.encode(csv),
      filename: '${name.isEmpty ? 'challenge' : name}-participants-$today.csv',
      mimeType: 'text/csv;charset=utf-8',
    );
    if (downloaded) return;
    // No file downloads in the native app: hand it over as text instead.
    await Clipboard.setData(ClipboardData(text: csv));
    _toast('CSV copied to the clipboard');
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTheme.mono(fontSize: 22, fontWeight: FontWeight.w600)),
          Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool out;

  const _StatusChip({required this.status, required this.out});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = out
        ? scheme.error
        : (status == 'Winner' || status == 'Finished' || status == 'Safe today')
        ? scheme.tertiary
        : scheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

class _Correction {
  final int progress;
  final String dayKey;
  final String reason;

  const _Correction(this.progress, this.dayKey, this.reason);
}

/// New total, which day the difference lands on, and a required reason.
/// The server has the final say (it refuses judged Last One Standing days
/// and a day dropping below zero); this offers only plausible days.
class _CorrectProgressDialog extends StatefulWidget {
  final Challenge challenge;
  final ParticipantReport row;

  const _CorrectProgressDialog({required this.challenge, required this.row});

  @override
  State<_CorrectProgressDialog> createState() => _CorrectProgressDialogState();
}

class _CorrectProgressDialogState extends State<_CorrectProgressDialog> {
  late final _total = TextEditingController(text: '${widget.row.progress}');
  final _reason = TextEditingController();
  late final String _todayKey = widget.challenge.dayKey(DateTime.now());
  late String _dayKey = _todayKey;

  @override
  void dispose() {
    _total.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Today and up to 13 days back, from the challenge's start; in Last One
  /// Standing only days not judged yet.
  List<String> get _days {
    final challenge = widget.challenge;
    final startsAt = challenge.startsAt;
    final startKey = startsAt == null ? null : challenge.dayKey(startsAt);
    final judged = challenge.winCondition == WinCondition.lastStanding
        ? challenge.lastEvaluatedDay
        : null;
    return [
      for (var i = 0; i < 14; i++) addDaysToDayKey(_todayKey, -i),
    ].where((day) {
      if (startKey != null && day.compareTo(startKey) < 0) return false;
      if (judged != null && day.compareTo(judged) <= 0) return false;
      return true;
    }).toList();
  }

  int? get _newTotal {
    final value = int.tryParse(_total.text.trim());
    return value != null && value >= 0 ? value : null;
  }

  bool get _valid =>
      _newTotal != null &&
      _newTotal != widget.row.progress &&
      _reason.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final unit = widget.challenge.unit;
    final delta = (_newTotal ?? widget.row.progress) - widget.row.progress;

    return AlertDialog(
      title: Text("Correct ${widget.row.username}'s progress"),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Now ${widget.row.progress}${unit.isEmpty ? '' : ' $unit'}. '
              'The correction is logged with your name and reason.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _total,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'New total',
                suffixText: unit.isEmpty ? null : unit,
                helperText: delta == 0
                    ? null
                    : '${delta > 0 ? '+' : ''}$delta on the chosen day',
              ),
            ),
            const SizedBox(height: 16),
            if (days.isEmpty)
              const Text('No day is open for corrections.')
            else
              DropdownButtonFormField<String>(
                initialValue: days.contains(_dayKey) ? _dayKey : days.first,
                decoration: const InputDecoration(labelText: 'Apply to day'),
                items: [
                  for (final day in days)
                    DropdownMenuItem(
                      value: day,
                      child: Text(formatDayKey(day, _todayKey)),
                    ),
                ],
                onChanged: (day) => setState(() => _dayKey = day ?? _dayKey),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                hintText: 'e.g. GPS dropped 3 km of the run',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid && days.isNotEmpty
              ? () => Navigator.of(context).pop(
                  _Correction(
                    _newTotal!,
                    days.contains(_dayKey) ? _dayKey : days.first,
                    _reason.text.trim(),
                  ),
                )
              : null,
          child: const Text('Save correction'),
        ),
      ],
    );
  }
}

/// A confirm dialog with a required reason; resolves to the reason.
class _ReasonDialog extends StatefulWidget {
  final String title;
  final String body;
  final String confirmLabel;

  const _ReasonDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.body),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              autofocus: true,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
