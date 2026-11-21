import 'package:flutter/material.dart';

import 'api.dart';
import 'util.dart';
import 'widgets.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<List<Map<String, dynamic>>>> future = load();

  Future<List<List<Map<String, dynamic>>>> load() async => [
    await Api.instance.history(),
    await Api.instance.subjects(),
  ];

  Future<void> reload() async {
    setState(() => future = load());
    await future.catchError((_) => <List<Map<String, dynamic>>>[]);
  }

  static String two(int n) => n.toString().padLeft(2, '0');
  static String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

  String dayLabel(DateTime d) {
    final now = DateTime.now();
    if (dayKey(d) == dayKey(now)) return 'Aujourd\'hui';
    if (dayKey(d) == dayKey(now.subtract(const Duration(days: 1)))) {
      return 'Hier';
    }
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String modeLabel(String m) => m == 'Stopwatch' ? 'Libre' : m;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(message: '${snap.error}', onRetry: reload);
        }

        final items = snap.data![0];
        final names = {
          for (final s in snap.data![1]) s['id'] as String: s['name'] as String,
        };
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            message: 'Aucune séance pour le moment.',
          );
        }

        final totals = <String, int>{};
        for (final s in items) {
          if (s['status'] == 'Completed') {
            final k = dayKey(parseUtc(s['startedAtUtc']));
            totals[k] = (totals[k] ?? 0) + (s['durationSeconds'] as int);
          }
        }

        final children = <Widget>[];
        String? last;
        for (final s in items) {
          final start = parseUtc(s['startedAtUtc']);
          final k = dayKey(start);
          if (k != last) {
            last = k;
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dayLabel(start),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      fmtShort(totals[k] ?? 0),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final ok = s['status'] == 'Completed';
          final subject = names[s['subjectId']] ?? 'Sans matière';
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: ok
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                    child: Icon(
                      ok ? Icons.check_rounded : Icons.close_rounded,
                      color: ok ? cs.primary : cs.outline,
                    ),
                  ),
                  title: Text(
                    subject,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${modeLabel(s['mode'])} · ${two(start.hour)}:${two(start.minute)}',
                  ),
                  trailing: Text(
                    ok ? fmtShort(s['durationSeconds']) : 'non comptée',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ok ? cs.onSurface : cs.outline,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: reload,
          child: Body(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: children,
            ),
          ),
        );
      },
    );
  }
}
