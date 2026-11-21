import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ring.dart';
import 'util.dart';

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});
  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  Map<String, dynamic>? session;
  int baseElapsed = 0;
  final Stopwatch sw = Stopwatch();
  Timer? ticker;
  bool busy = false;
  bool loading = true;
  String? error;

  String mode = 'Focus';
  final minutes = TextEditingController(text: '25');
  final breakMinutes = TextEditingController(text: '5');
  List<Map<String, dynamic>> subjects = [];
  String? subjectId;
  int breakLeft = 0;
  int breakTotal = 0;

  bool get running => session?['status'] == 'Running';
  int get elapsed =>
      session == null ? 0 : baseElapsed + (running ? sw.elapsed.inSeconds : 0);
  int? get target => session?['targetSeconds'] as int?;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    recover();
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  void tick() {
    if (!mounted) return;
    if (breakLeft > 0) {
      setState(() => breakLeft--);
      if (breakLeft == 0) {
        alert('Pause terminée', 'C\'est reparti pour un nouveau Pomodoro !');
      }
      return;
    }
    if (running) {
      setState(() {});
      if (session?['mode'] == 'Pomodoro' &&
          target != null &&
          elapsed >= target! &&
          !busy) {
        finishPomodoro();
      }
    }
  }

  void sync(Map<String, dynamic>? s) {
    session = s;
    baseElapsed = (s?['elapsedSeconds'] ?? 0) as int;
    sw
      ..reset()
      ..start();
  }

  Future<void> recover() async {
    try {
      final s = await Api.instance.current();
      final subs = await Api.instance.subjects();
      if (mounted) {
        setState(() {
          sync(s);
          subjects = subs;
          loading = false;
          error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.message;
        });
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void alert(String title, String body) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> addSubject() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouvelle matière'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await run(() async {
      final s = await Api.instance.createSubject(name);
      setState(() {
        subjects = [...subjects, s];
        subjectId = s['id'];
      });
    });
  }

  Future<void> start() => run(() async {
    final m = int.tryParse(minutes.text);
    final t = mode == 'Stopwatch' || m == null || m <= 0 ? null : m * 60;
    final s = await Api.instance.start(mode, t, subjectId);
    setState(() {
      sync(s);
      breakLeft = 0;
    });
  });

  Future<void> pauseResume() => run(() async {
    final s = running
        ? await Api.instance.pause()
        : await Api.instance.resume();
    setState(() => sync(s));
  });

  Future<void> stop() => run(() async {
    final r = await Api.instance.stop();
    setState(() => sync(null));
    if (!mounted) return;
    final ok = r['status'] == 'Completed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          ok
              ? 'Séance enregistrée : ${fmtShort(r['durationSeconds'])}'
              : 'Séance trop courte (moins de 60 s) : non comptée.',
        ),
      ),
    );
  });

  Future<void> finishPomodoro() => run(() async {
    final r = await Api.instance.stop();
    final b = int.tryParse(breakMinutes.text) ?? 5;
    setState(() {
      sync(null);
      breakLeft = b * 60;
      breakTotal = b * 60;
    });
    alert(
      'Pomodoro terminé !',
      'Séance enregistrée : ${fmtShort(r['durationSeconds'])}. Pause de $b min.',
    );
  });

  double get progress {
    if (breakLeft > 0 && breakTotal > 0) return breakLeft / breakTotal;
    if (session == null) return 0;
    if (target != null && target! > 0) return elapsed / target!;
    return (elapsed % 3600) / 3600;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final cs = Theme.of(context).colorScheme;
    final onBreak = breakLeft > 0;
    final subjectName = subjects
        .where((s) => s['id'] == session?['subjectId'])
        .map((s) => s['name'] as String)
        .firstOrNull;

    final label = onBreak
        ? 'Pause Pomodoro'
        : session == null
        ? 'Prêt à étudier ?'
        : '${running ? 'En cours' : 'En pause'}'
              '${subjectName != null ? ' · $subjectName' : ''}';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ----- Anneau + temps -----
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 28,
                    horizontal: 20,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 260,
                        height: 260,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(260, 260),
                              painter: RingPainter(
                                progress,
                                onBreak ? Colors.teal : cs.primary,
                                cs.primary.withValues(alpha: 0.12),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  onBreak ? fmt(breakLeft) : fmt(elapsed),
                                  style: TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  label,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                                if (session != null && target != null)
                                  Text(
                                    'objectif ${fmtShort(target!)}',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (onBreak)
                        TextButton(
                          onPressed: () => setState(() => breakLeft = 0),
                          child: const Text('Passer la pause'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ----- Réglages (avant le départ) -----
              if (session == null && !onBreak)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: 'Focus',
                                label: Text('Focus'),
                                icon: Icon(Icons.center_focus_strong),
                              ),
                              ButtonSegment(
                                value: 'Pomodoro',
                                label: Text('Pomodoro'),
                                icon: Icon(Icons.local_pizza_outlined),
                              ),
                              ButtonSegment(
                                value: 'Stopwatch',
                                label: Text('Libre'),
                                icon: Icon(Icons.timer_outlined),
                              ),
                            ],
                            selected: {mode},
                            onSelectionChanged: (v) => setState(() {
                              mode = v.first;
                              if (mode == 'Pomodoro') minutes.text = '25';
                            }),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: subjectId,
                                decoration: InputDecoration(
                                  labelText: 'Matière',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Sans matière'),
                                  ),
                                  for (final s in subjects)
                                    DropdownMenuItem<String?>(
                                      value: s['id'],
                                      child: Text(s['name']),
                                    ),
                                ],
                                onChanged: (v) => setState(() => subjectId = v),
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Nouvelle matière',
                              onPressed: busy ? null : addSubject,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        if (mode != 'Stopwatch') ...[
                          const SizedBox(height: 16),
                          Text(
                            mode == 'Pomodoro'
                                ? 'Durée de travail'
                                : 'Durée cible',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final m in [15, 25, 45, 60, 90])
                                ChoiceChip(
                                  label: Text('$m min'),
                                  selected: minutes.text == '$m',
                                  onSelected: (_) =>
                                      setState(() => minutes.text = '$m'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: minutes,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Minutes',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                        if (mode == 'Pomodoro') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: breakMinutes,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Pause (minutes)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: busy ? null : start,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Démarrer'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (session != null)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                        onPressed: busy ? null : pauseResume,
                        icon: Icon(
                          running
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(running ? 'Pause' : 'Reprendre'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : stop,
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('Terminer'),
                      ),
                    ),
                  ],
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(error!, style: TextStyle(color: cs.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
