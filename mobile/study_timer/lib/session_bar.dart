import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'util.dart';

/// Barre "chrono en cours" affichee en haut de toutes les pages sauf la page
/// Timer. Elle permet de mettre en pause, reprendre ou terminer la seance
/// depuis n'importe quel ecran.
class SessionBar extends StatefulWidget {
  /// Ouvre la page Timer.
  final VoidCallback onOpen;

  /// Appele apres une action (pause, reprise, fin) pour rafraichir les pages.
  final VoidCallback onChanged;

  const SessionBar({super.key, required this.onOpen, required this.onChanged});

  @override
  State<SessionBar> createState() => _SessionBarState();
}

class _SessionBarState extends State<SessionBar> {
  Map<String, dynamic>? session;
  int baseElapsed = 0;
  final Stopwatch sw = Stopwatch();
  Timer? ticker;
  bool busy = false;

  bool get running => session?['status'] == 'Running';
  int get elapsed =>
      session == null ? 0 : baseElapsed + (running ? sw.elapsed.inSeconds : 0);

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && running) setState(() {});
    });
    refresh();
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  void sync(Map<String, dynamic>? s) {
    session = s;
    baseElapsed = (s?['elapsedSeconds'] ?? 0) as int;
    sw
      ..reset()
      ..start();
  }

  Future<void> refresh() async {
    try {
      final s = await Api.instance.current();
      if (mounted) setState(() => sync(s));
    } on ApiException {
      if (mounted) setState(() => sync(null));
    }
  }

  Future<void> act(
    Future<Map<String, dynamic>> Function() call, {
    bool end = false,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await call();
      if (!mounted) return;
      setState(() => sync(end ? null : r));
      widget.onChanged();
      if (end) {
        final ok = r['status'] == 'Completed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              ok
                  ? 'S\u00E9ance enregistr\u00E9e : ${fmtShort(r['durationSeconds'])}'
                  : 'S\u00E9ance trop courte (moins de 60 s) : non compt\u00E9e.',
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    if (s == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final target = s['targetSeconds'] as int?;
    final reached =
        s['mode'] == 'Pomodoro' && target != null && elapsed >= target;
    final label = reached
        ? 'Objectif atteint : termine la s\u00E9ance'
        : running
        ? 'Chrono en cours'
        : 'Chrono en pause';

    return Material(
      color: cs.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(Icons.timer, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fmt(elapsed),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: running ? 'Pause' : 'Reprendre',
                  onPressed: busy
                      ? null
                      : () => act(
                          running ? Api.instance.pause : Api.instance.resume,
                        ),
                  icon: Icon(
                    running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Terminer',
                  onPressed: busy
                      ? null
                      : () => act(Api.instance.stop, end: true),
                  icon: const Icon(Icons.stop_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
