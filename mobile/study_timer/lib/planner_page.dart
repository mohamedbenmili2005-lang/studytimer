import 'package:flutter/material.dart';

import 'api.dart';
import 'api_extras.dart';
import 'util.dart';
import 'widgets.dart';

/// Planificateur d'etude : taches, echeances, priorites, taches en retard.
class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  static const filters = <(String, String)>[
    ('all', 'Toutes'),
    ('open', '\u00c0 faire'),
    ('overdue', 'En retard'),
    ('done', 'Termin\u00e9es'),
  ];

  String filter = 'open';
  List<Map<String, dynamic>> tasks = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final t = await Api.instance.tasks(status: filter);
      if (!mounted) return;
      setState(() {
        tasks = t;
        error = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> act(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      await reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> add() async {
    final title = TextEditingController();
    final minutes = TextEditingController(text: '30');
    var priority = 'Medium';
    DateTime? due;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nouvelle t\u00e2che'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Titre'),
                ),
                TextField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dur\u00e9e estim\u00e9e (min)'),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: priority,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'Low', child: Text('Priorit\u00e9 basse')),
                    DropdownMenuItem(value: 'Medium', child: Text('Priorit\u00e9 moyenne')),
                    DropdownMenuItem(value: 'High', child: Text('Priorit\u00e9 haute')),
                  ],
                  onChanged: (v) => setS(() => priority = v ?? 'Medium'),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(due == null ? '\u00c9ch\u00e9ance (facultatif)' : fmtDateTime(due!)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (d == null || !ctx.mounted) return;
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: const TimeOfDay(hour: 18, minute: 0),
                    );
                    if (t == null) return;
                    setS(() => due = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    await act(
      () => Api.instance.createTask({
        'title': title.text.trim(),
        'estimatedMinutes': int.tryParse(minutes.text.trim()),
        'priority': priority,
        'dueAtUtc': due?.toUtc().toIso8601String(),
      }),
    );
  }

  String subtitle(Map<String, dynamic> t) {
    final parts = <String>[];
    final d = t['dueAtUtc'];
    if (d is String) parts.add(fmtDateTime(parseUtc(d)));
    if (t['estimatedMinutes'] != null) parts.add('${t['estimatedMinutes']} min');
    parts.add(switch ('${t['priority']}') {
      'High' => 'haute',
      'Low' => 'basse',
      _ => 'moyenne',
    });
    return parts.join(' \u00b7 ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Body(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final f in filters)
                      ChoiceChip(
                        label: Text(f.$2),
                        selected: filter == f.$1,
                        onSelected: (_) {
                          setState(() => filter = f.$1);
                          reload();
                        },
                      ),
                  ],
                ),
              ),
              FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), 
                onPressed: add,
                icon: const Icon(Icons.add),
                label: const Text('T\u00e2che'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (error != null)
            ErrorView(message: error!, onRetry: reload)
          else if (tasks.isEmpty)
            const EmptyState(icon: Icons.event_available, message: 'Aucune t\u00e2che ici.')
          else
            for (final t in tasks)
              Card(
                child: ListTile(
                  leading: Checkbox(
                    value: t['isDone'] == true,
                    onChanged: t['isDone'] == true
                        ? null
                        : (_) => act(() => Api.instance.completeTask('${t['id']}')),
                  ),
                  title: Text(
                    '${t['title']}',
                    style: TextStyle(
                      decoration: t['isDone'] == true ? TextDecoration.lineThrough : null,
                      color: t['overdue'] == true ? cs.error : null,
                    ),
                  ),
                  subtitle: Text(subtitle(t)),
                  trailing: IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => act(() => Api.instance.deleteTask('${t['id']}')),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}