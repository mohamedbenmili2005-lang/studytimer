import 'package:flutter/material.dart';

import 'api.dart';
import 'util.dart';
import 'widgets.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<Map<String, dynamic>> future = Api.instance.dashboard();

  Future<void> reload() async {
    setState(() => future = Api.instance.dashboard());
    await future.catchError((_) => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(message: '${snap.error}', onRetry: reload);
        }

        final d = snap.data!;
        final days = (d['last7Days'] as List).cast<Map<String, dynamic>>();
        final subjects = (d['bySubject'] as List).cast<Map<String, dynamic>>();
        final total = (d['totalSeconds'] as int) == 0
            ? 1
            : d['totalSeconds'] as int;

        return RefreshIndicator(
          onRefresh: reload,
          child: Body(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: 92,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  children: [
                    StatTile(
                      icon: Icons.today,
                      label: 'Aujourd\'hui',
                      value: fmtShort(d['todaySeconds']),
                    ),
                    StatTile(
                      icon: Icons.date_range,
                      label: 'Cette semaine',
                      value: fmtShort(d['weekSeconds']),
                    ),
                    StatTile(
                      icon: Icons.calendar_month,
                      label: 'Ce mois',
                      value: fmtShort(d['monthSeconds']),
                    ),
                    StatTile(
                      icon: Icons.hourglass_bottom,
                      label: 'Total',
                      value: fmtShort(d['totalSeconds']),
                    ),
                    StatTile(
                      icon: Icons.checklist,
                      label: 'Séances',
                      value: '${d['sessionsCount']}',
                      hint: 'moy. ${fmtShort(d['averageSessionSeconds'])}',
                    ),
                    StatTile(
                      icon: Icons.local_fire_department,
                      label: 'Série en cours',
                      value: '${d['currentStreakDays']} j',
                      hint: 'record ${d['bestStreakDays']} j',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '7 derniers jours',
                  child: WeekBars(days: days),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Répartition par matière',
                  child: subjects.isEmpty
                      ? const Text('Aucune séance enregistrée pour le moment.')
                      : Column(
                          children: [
                            for (final s in subjects)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: Text(s['name'])),
                                        Text(
                                          '${fmtShort(s['seconds'])} · ${((s['seconds'] as int) * 100 / total).round()} %',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    LinearProgressIndicator(
                                      value: (s['seconds'] as int) / total,
                                      minHeight: 8,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
