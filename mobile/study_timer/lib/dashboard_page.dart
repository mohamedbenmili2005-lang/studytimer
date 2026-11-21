import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

class DashboardPage extends StatefulWidget {
  final VoidCallback onGoTimer;
  final VoidCallback onGoStats;
  final VoidCallback onLogout;
  const DashboardPage({
    super.key,
    required this.onGoTimer,
    required this.onGoStats,
    required this.onLogout,
  });
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const dailyGoal = 2 * 3600;
  late Future<List<Object?>> future = load();

  Future<List<Object?>> load() => Future.wait<Object?>([
    Api.instance.dashboard(),
    Api.instance.current(),
    Api.instance.profile(),
  ]);

  Future<void> reload() async {
    setState(() => future = load());
    await future.catchError((_) => <Object?>[]);
  }

  Widget header(String firstName) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      color: kHeader,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
    ),
    child: SafeArea(
      bottom: false,
      child: Body(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Salut, $firstName !',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: widget.onLogout,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.logout, color: kHeader),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              InkWell(
                onTap: widget.onGoTimer,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search, color: Colors.black45),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Que voulez-vous étudier ?',
                          style: TextStyle(color: Colors.black45, fontSize: 16),
                        ),
                      ),
                      Icon(Icons.play_circle_fill, color: kPrimary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget modeTile(String label, IconData icon, bool active) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: widget.onGoTimer,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active
              ? kCoral
              : cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(
              icon,
              size: 38,
              color: active ? Colors.white : cs.onSurfaceVariant,
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget subjectCard(Map<String, dynamic> s, List<Color> colors) => Container(
    height: 170,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s['name'],
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const Spacer(),
        Align(
          alignment: Alignment.bottomRight,
          child: Icon(
            Icons.menu_book_rounded,
            size: 54,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        Text(
          fmtShort(s['seconds']),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Object?>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(message: '${snap.error}', onRetry: reload);
        }

        final d = snap.data![0] as Map<String, dynamic>;
        final cur = snap.data![1] as Map<String, dynamic>?;
        final p = snap.data![2] as Map<String, dynamic>;
        final today = d['todaySeconds'] as int;
        final subjects = (d['bySubject'] as List).cast<Map<String, dynamic>>();
        final left = (dailyGoal - today).clamp(0, dailyGoal);
        final palettes = [
          [kIndigo, const Color(0xFF7C80D6)],
          [kPeach, const Color(0xFFF7C2A5)],
        ];

        return Column(
          children: [
            header('${p['firstName']}'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: reload,
                child: Body(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
                    children: [
                      if (cur != null) ...[
                        Card(
                          color: cs.primaryContainer,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 6,
                            ),
                            leading: Icon(Icons.timer, color: cs.primary),
                            title: Text(
                              'Séance ${cur['status'] == 'Running' ? 'en cours' : 'en pause'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${cur['mode']} · ${fmt(cur['elapsedSeconds'])}',
                            ),
                            trailing: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(90, 40),
                              ),
                              onPressed: widget.onGoTimer,
                              child: const Text('Ouvrir'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      SizedBox(
                        height: 124,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            modeTile('Focus', Icons.center_focus_strong, true),
                            const SizedBox(width: 12),
                            modeTile(
                              'Pomodoro',
                              Icons.local_pizza_outlined,
                              false,
                            ),
                            const SizedBox(width: 12),
                            modeTile(
                              'Chrono libre',
                              Icons.timer_outlined,
                              false,
                            ),
                            const SizedBox(width: 12),
                            modeTile('Statistiques', Icons.bar_chart, false),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Mes matières',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: widget.onGoStats,
                            child: const Text('Voir tout'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (subjects.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'Ajoutez une matière dans le Timer pour la voir ici.',
                            ),
                          ),
                        )
                      else
                        Row(
                          children: [
                            for (
                              var i = 0;
                              i < subjects.take(2).length;
                              i++
                            ) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(
                                child: subjectCard(subjects[i], palettes[i]),
                              ),
                            ],
                            if (subjects.length == 1) const Spacer(),
                          ],
                        ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: kDark,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_fire_department,
                                  color: kYellow,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${d['currentStreakDays']} jour(s) de série',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              left == 0
                                  ? 'Objectif du jour atteint, bravo !'
                                  : 'Encore ${fmtShort(left)} pour atteindre votre objectif du jour.',
                              style: const TextStyle(
                                color: Colors.white70,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: (today / dailyGoal).clamp(0.0, 1.0),
                                minHeight: 10,
                                color: kYellow,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${fmtShort(today)} sur ${fmtShort(dailyGoal)} · record ${d['bestStreakDays']} j',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
