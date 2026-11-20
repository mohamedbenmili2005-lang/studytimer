import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'util.dart';

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});
  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  Map<String, dynamic>? session;
  int baseElapsed = 0;              // temps cumulé fourni par le serveur
  final Stopwatch sw = Stopwatch(); // temps local écoulé depuis la dernière synchro
  Timer? ticker;
  bool busy = false;
  bool loading = true;
  String? error;

  String mode = 'Focus';
  final minutes = TextEditingController(text: '25');

  bool get running => session?['status'] == 'Running';
  int get elapsed => session == null ? 0 : baseElapsed + (running ? sw.elapsed.inSeconds : 0);

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && running) setState(() {});
    });
    recover();
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  void sync(Map<String, dynamic>? s) {
    session = s;
    baseElapsed = (s?['elapsedSeconds'] ?? 0) as int;
    sw..reset()..start();
  }

  /// Récupère la séance après fermeture ou redémarrage de l'application.
  Future<void> recover() async {
    try {
      final s = await Api.instance.current();
      if (mounted) setState(() { sync(s); loading = false; error = null; });
    } on ApiException catch (e) {
      if (mounted) setState(() { loading = false; error = e.message; });
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() { busy = true; error = null; });
    try {
      await action();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> start() => run(() async {
        final m = int.tryParse(minutes.text);
        final target = mode == 'Stopwatch' || m == null || m <= 0 ? null : m * 60;
        final s = await Api.instance.start(mode, target);
        setState(() => sync(s));
      });

  Future<void> pauseResume() => run(() async {
        final s = running ? await Api.instance.pause() : await Api.instance.resume();
        setState(() => sync(s));
      });

  Future<void> stop() => run(() async {
        final r = await Api.instance.stop();
        setState(() => sync(null));
        if (!mounted) return;
        final ok = r['status'] == 'Completed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'Séance enregistrée : ${fmtShort(r['durationSeconds'])}'
              : 'Séance trop courte (moins de 60 s) : non comptée.'),
        ));
      });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final target = session?['targetSeconds'] as int?;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(fmt(elapsed),
                style: Theme.of(context).textTheme.displayLarge
                    ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 8),
            if (session != null)
              Text(
                '${session!['mode']} · ${running ? 'en cours' : 'en pause'}'
                '${target != null ? ' · objectif ${fmtShort(target)}' : ''}',
              ),
            const SizedBox(height: 32),
            if (session == null) ...[
              DropdownButtonFormField<String>(
                value: mode,
                decoration: const InputDecoration(labelText: 'Mode', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'Focus', child: Text('Focus (durée cible)')),
                  DropdownMenuItem(value: 'Pomodoro', child: Text('Pomodoro')),
                  DropdownMenuItem(value: 'Stopwatch', child: Text('Chronomètre libre')),
                ],
                onChanged: (v) => setState(() {
                  mode = v!;
                  if (mode == 'Pomodoro') minutes.text = '25';
                }),
              ),
              if (mode != 'Stopwatch') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Durée cible (minutes)', border: OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Démarrer'),
                ),
              ),
            ] else
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : pauseResume,
                    icon: Icon(running ? Icons.pause : Icons.play_arrow),
                    label: Text(running ? 'Pause' : 'Reprendre'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Terminer'),
                  ),
                ),
              ]),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
      ),
    );
  }
}
