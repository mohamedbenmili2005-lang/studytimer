import 'package:flutter/material.dart';

import 'api.dart';
import 'util.dart';
import 'widgets.dart';

const _badgeIcons = <String, IconData>{
  'flag': Icons.flag_rounded,
  'repeat': Icons.repeat_rounded,
  'schedule': Icons.schedule_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
  'local_fire_department': Icons.local_fire_department_rounded,
  'whatshot': Icons.whatshot_rounded,
  'military_tech': Icons.military_tech_rounded,
  'directions_run': Icons.directions_run_rounded,
};

const _typeLabels = <String, String>{
  'TotalTime': 'Temps total',
  'SessionCount': 'Nombre de séances',
  'DailyStreak': 'Série de jours',
  'LongestSession': 'Séance la plus longue',
};

String _targetLabel(String type, int target) => switch (type) {
  'TotalTime' || 'LongestSession' => fmtShort(target),
  'SessionCount' => '$target séance${target > 1 ? 's' : ''}',
  _ => '$target jour${target > 1 ? 's' : ''}',
};

class ChallengesPage extends StatelessWidget {
  const ChallengesPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      children: const [
        TabBar(
          tabs: [
            Tab(text: 'Défis'),
            Tab(text: 'Classement'),
            Tab(text: 'Badges'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [_ChallengesTab(), _LeaderboardTab(), _BadgesTab()],
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- Défis
class _ChallengesTab extends StatefulWidget {
  const _ChallengesTab();
  @override
  State<_ChallengesTab> createState() => _ChallengesTabState();
}

class _ChallengesTabState extends State<_ChallengesTab> {
  late Future<List<Map<String, dynamic>>> future = Api.instance.challenges();

  Future<void> reload() async {
    setState(() => future = Api.instance.challenges());
    await future.catchError((_) => <Map<String, dynamic>>[]);
  }

  Future<void> join(String id) async {
    try {
      await Api.instance.joinChallenge(id);
      await reload();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> create() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateDialog(),
    );
    if (ok == true) await reload();
  }

  Future<void> showBoard(Map<String, dynamic> c) => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _BoardSheet(challenge: c),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'newChallenge',
        onPressed: create,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau défi'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ErrorView(message: '${snap.error}', onRetry: reload);
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.emoji_events_outlined,
              message: 'Aucun défi pour le moment. Créez le premier !',
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: Body(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final c = items[i];
                  final target = c['target'] as int;
                  final progress = c['progress'] as int;
                  final joined = c['joined'] == true;
                  final finished = c['finished'] == true;
                  final ratio = (progress / target).clamp(0.0, 1.0);
                  final end = parseUtc(c['endsAtUtc']);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c['title'],
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (finished)
                                const Chip(label: Text('Terminé'))
                              else if (ratio >= 1 && joined)
                                Icon(Icons.verified_rounded, color: cs.primary),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_typeLabels[c['type']]} · objectif ${_targetLabel(c['type'], target)}',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          Text(
                            '${c['participants']} participant(s) · fin le ${fmtDateTime(end)}',
                            style: TextStyle(color: cs.outline, fontSize: 12),
                          ),
                          const SizedBox(height: 14),
                          if (joined) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 10,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_targetLabel(c['type'], progress)} / ${_targetLabel(c['type'], target)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => showBoard(c),
                                icon: const Icon(Icons.leaderboard_rounded),
                                label: const Text('Classement'),
                              ),
                            ),
                          ] else if (!finished)
                            FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                              ),
                              onPressed: () => join(c['id']),
                              child: const Text('Rejoindre'),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog();
  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final title = TextEditingController();
  final target = TextEditingController(text: '10');
  final days = TextEditingController(text: '7');
  String type = 'TotalTime';
  String? error;
  bool busy = false;

  String get unit => switch (type) {
    'TotalTime' || 'LongestSession' => 'minutes',
    'SessionCount' => 'séances',
    _ => 'jours',
  };

  Future<void> submit() async {
    final t = int.tryParse(target.text.trim());
    final d = int.tryParse(days.text.trim());
    if (title.text.trim().isEmpty || t == null || t <= 0 || d == null) {
      setState(() => error = 'Renseignez un titre, un objectif et une durée.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Api.instance.createChallenge({
        'title': title.text.trim(),
        'type': type,
        'target': unit == 'minutes' ? t * 60 : t,
        'durationDays': d,
        'isPublic': true,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        busy = false;
        error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouveau défi'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Titre'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Type de défi'),
            items: [
              for (final e in _typeLabels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => type = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: target,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Objectif ($unit)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Durée (jours, 1 à 90)',
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context, false),
        child: const Text('Annuler'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
        onPressed: busy ? null : submit,
        child: const Text('Créer'),
      ),
    ],
  );
}

class _BoardSheet extends StatelessWidget {
  final Map<String, dynamic> challenge;
  const _BoardSheet({required this.challenge});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            challenge['title'],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Api.instance.challengeLeaderboard(challenge['id']),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                );
              }
              if (snap.hasError) return Text('${snap.error}');
              final type = challenge['type'] as String;
              return Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in snap.data!)
                      ListTile(
                        leading: CircleAvatar(child: Text('${r['rank']}')),
                        title: Text(
                          r['username'],
                          style: TextStyle(
                            fontWeight: r['isMe'] == true
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: Text(
                          _targetLabel(type, r['progress'] as int),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

// ----------------------------------------------------------- Classement
class _LeaderboardTab extends StatefulWidget {
  const _LeaderboardTab();
  @override
  State<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<_LeaderboardTab> {
  String period = 'week';
  late Future<List<Map<String, dynamic>>> future = Api.instance.leaderboard(
    period,
  );

  void change(String p) => setState(() {
    period = p;
    future = Api.instance.leaderboard(p);
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Body(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'week', label: Text('Semaine')),
                ButtonSegment(value: 'month', label: Text('Mois')),
                ButtonSegment(value: 'all', label: Text('Total')),
              ],
              selected: {period},
              onSelectionChanged: (s) => change(s.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return ErrorView(
                    message: '${snap.error}',
                    onRetry: () => change(period),
                  );
                }
                final rows = snap.data!;
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.leaderboard_outlined,
                    message: 'Personne n\'a encore étudié sur cette période.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final me = r['isMe'] == true;
                    final medal = switch (r['rank']) {
                      1 => const Color(0xFFFBBF24),
                      2 => const Color(0xFF9CA3AF),
                      3 => const Color(0xFFD97706),
                      _ => null,
                    };
                    return Card(
                      color: me ? cs.primaryContainer : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: medal ?? cs.surfaceContainerHighest,
                          foregroundColor: medal != null
                              ? Colors.white
                              : cs.onSurface,
                          child: Text('${r['rank']}'),
                        ),
                        title: Text(
                          r['username'],
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('${r['xp']} XP'),
                        trailing: Text(
                          fmtShort(r['seconds'] as int),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Badges
class _BadgesTab extends StatefulWidget {
  const _BadgesTab();
  @override
  State<_BadgesTab> createState() => _BadgesTabState();
}

class _BadgesTabState extends State<_BadgesTab> {
  late Future<Map<String, dynamic>> future = Api.instance.progress();

  Future<void> reload() async {
    setState(() => future = Api.instance.progress());
    await future.catchError((_) => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(message: '${snap.error}', onRetry: reload);
        }
        final p = snap.data!;
        final badges = (p['badges'] as List).cast<Map<String, dynamic>>();
        final into = p['xpIntoLevel'] as int;
        final forNext = p['xpForNextLevel'] as int;
        return RefreshIndicator(
          onRefresh: reload,
          child: Body(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: 'Niveau ${p['level']}',
                  trailing: Text(
                    '${p['xp']} XP',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (into / forNext).clamp(0.0, 1.0),
                          minHeight: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${forNext - into} XP avant le niveau ${(p['level'] as int) + 1}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width > 600
                      ? 4
                      : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                  children: [
                    for (final b in badges)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Opacity(
                            opacity: b['earned'] == true ? 1 : 0.4,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _badgeIcons[b['icon']] ?? Icons.star_rounded,
                                  size: 40,
                                  color: b['earned'] == true
                                      ? const Color(0xFFFBBF24)
                                      : cs.outline,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  b['name'],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  b['description'],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
