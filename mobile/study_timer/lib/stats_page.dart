import 'package:flutter/material.dart';
import 'api.dart';
import 'util.dart';

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

  Widget tile(String label, String value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${snap.error}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: reload, child: const Text('Réessayer')),
            ]),
          );
        }
        final d = snap.data!;
        final days = (d['last7Days'] as List).cast<Map<String, dynamic>>();
        final subjects = (d['bySubject'] as List).cast<Map<String, dynamic>>();
        final maxSec = days.fold<int>(1, (m, x) => (x['seconds'] as int) > m ? x['seconds'] as int : m);

        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                tile('Aujourd\'hui', fmtShort(d['todaySeconds']), Icons.today),
                tile('Cette semaine', fmtShort(d['weekSeconds']), Icons.date_range),
                tile('Ce mois', fmtShort(d['monthSeconds']), Icons.calendar_month),
                tile('Total', fmtShort(d['totalSeconds']), Icons.hourglass_bottom),
                tile('Séances (moy. ${fmtShort(d['averageSessionSeconds'])})',
                    '${d['sessionsCount']}', Icons.checklist),
                tile('Série (record ${d['bestStreakDays']} j)',
                    '${d['currentStreakDays']} jour(s)', Icons.local_fire_department),
              ],
            ),
            const SizedBox(height: 20),
            Text('7 derniers jours', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final x in days)
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(fmtShort(x['seconds']), style: const TextStyle(fontSize: 10)),
                        const SizedBox(height: 4),
                        Container(
                          height: 4 + 90.0 * (x['seconds'] as int) / maxSec,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text((x['date'] as String).substring(8), style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Par matière', style: Theme.of(context).textTheme.titleMedium),
            if (subjects.isEmpty) const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Aucune séance enregistrée pour le moment.'),
            ),
            for (final s in subjects)
              ListTile(
                dense: true,
                title: Text(s['name']),
                trailing: Text(fmtShort(s['seconds'])),
              ),
          ]),
        );
      },
    );
  }
}
