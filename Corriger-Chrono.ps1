# Corriger-Chrono.ps1
# Compatible Windows PowerShell 5.1 (fichier volontairement en ASCII pur).
#
# Probleme corrige : quand le chrono est lance et qu'on change de page, la seance
# continue de tourner (elle vit sur le serveur) mais aucun bouton ne permet de l'arreter.
#
# Correctif : une barre "chrono en cours" (temps en direct + Pause/Reprendre + Terminer)
# est affichee en haut de toutes les pages sauf la page Timer.
#
# Utilisation (depuis C:\dev\studytimer) :
#   .\Corriger-Chrono.ps1             -> applique le correctif
#   .\Corriger-Chrono.ps1 -Verifier   -> applique puis lance dart format, flutter analyze, flutter test
#
# Pour annuler : remettre lib\home_page.dart.bak-chrono a la place de lib\home_page.dart
# et supprimer lib\session_bar.dart.

param(
    [string]$Chemin = ".",
    [switch]$Verifier
)

$Racine       = (Resolve-Path $Chemin).Path
$App          = Join-Path $Racine "mobile\study_timer"
$Lib          = Join-Path $App "lib"
$FichierHome  = Join-Path $Lib "home_page.dart"
$FichierBarre = Join-Path $Lib "session_bar.dart"

if (-not (Test-Path $FichierHome)) {
    Write-Host ("Fichier introuvable : " + $FichierHome) -ForegroundColor Red
    Write-Host "Lance le script depuis C:\dev\studytimer (ou utilise -Chemin)."
    return
}

$contenuActuel = Get-Content -LiteralPath $FichierHome -Raw -Encoding UTF8
if ($contenuActuel -match 'SessionBar') {
    Write-Host "Correctif deja applique : rien a faire." -ForegroundColor Green
    return
}
if ($contenuActuel -notmatch 'onGoTimer: \(\) => go\(2\)') {
    Write-Host "home_page.dart ne ressemble pas a la version attendue : aucune modification." -ForegroundColor Yellow
    Write-Host "Envoie-moi le fichier et je l'adapte."
    return
}

# --- Sauvegarde
$sauvegarde = $FichierHome + ".bak-chrono"
if (-not (Test-Path $sauvegarde)) {
    Copy-Item -LiteralPath $FichierHome -Destination $sauvegarde
    Write-Host ("Sauvegarde : " + $sauvegarde)
}

# --- Nouveau fichier : session_bar.dart
$barre = @'
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
'@

# --- Nouvelle version de home_page.dart (la barre est ajoutee au-dessus de la page affichee)
$codeHome = @'
import 'package:flutter/material.dart';

import 'challenges_page.dart';
import 'dashboard_page.dart';
import 'history_page.dart';
import 'logo.dart';
import 'profile_page.dart';
import 'session_bar.dart';
import 'stats_page.dart';
import 'timer_page.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onLogout;
  const HomePage({super.key, required this.onLogout});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0; // 0 Accueil, 1 Stats, 2 Timer, 3 Historique, 4 Profil, 5 Defis
  int tick = 0; // change apres une action de la barre : recharge la page affichee

  static const dests = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Accueil'),
    (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Stats'),
    (Icons.timer_outlined, Icons.timer, 'Timer'),
    (Icons.history, Icons.history, 'Historique'),
    (Icons.person_outline, Icons.person, 'Profil'),
    (Icons.emoji_events_outlined, Icons.emoji_events, 'D\u00E9fis'),
  ];

  void go(int i) => setState(() => index = i);

  Widget page() => switch (index) {
    0 => DashboardPage(
      onGoTimer: () => go(2),
      onGoStats: () => go(1),
      onLogout: widget.onLogout,
    ),
    1 => const StatsPage(),
    2 => const TimerPage(),
    3 => const HistoryPage(),
    5 => const ChallengesPage(),
    _ => const ProfilePage(),
  };

  /// Barre du chrono (sauf sur la page Timer) + page courante.
  Widget content() => Column(
    children: [
      index == 2
          ? const SizedBox.shrink()
          : SessionBar(onOpen: () => go(2), onChanged: () => setState(() => tick++)),
      Expanded(
        child: KeyedSubtree(key: ValueKey(tick), child: page()),
      ),
    ],
  );

  PreferredSizeWidget? appBar() => index == 0
      ? null
      : AppBar(
          title: Text(dests[index].$3),
          actions: [
            IconButton(
              tooltip: 'D\u00E9connexion',
              icon: const Icon(Icons.logout),
              onPressed: widget.onLogout,
            ),
            const SizedBox(width: 8),
          ],
        );

  Widget navItem(int i) {
    final cs = Theme.of(context).colorScheme;
    final sel = index == i;
    return Expanded(
      child: InkWell(
        onTap: () => go(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Icon(
            sel ? dests[i].$2 : dests[i].$1,
            size: 28,
            color: sel ? cs.primary : cs.outline,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final cs = Theme.of(context).colorScheme;

    if (wide) {
      return Scaffold(
        appBar: appBar(),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: go,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: AppLogo(size: 44),
              ),
              destinations: [
                for (final d in dests)
                  NavigationRailDestination(
                    icon: Icon(d.$1),
                    selectedIcon: Icon(d.$2),
                    label: Text(d.$3),
                  ),
              ],
            ),
            Expanded(child: content()),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar(),
      body: content(),
      floatingActionButton: SizedBox(
        width: 64,
        height: 64,
        child: FloatingActionButton(
          elevation: 2,
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          onPressed: () => go(2),
          child: const Icon(Icons.play_arrow_rounded, size: 36),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        height: 64,
        child: Row(
          children: [
            navItem(0),
            navItem(5),
            const SizedBox(width: 72),
            navItem(3),
            navItem(4),
          ],
        ),
      ),
    );
  }
}
'@

# --- Ecriture (UTF-8 sans BOM)
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($FichierBarre, $barre, $utf8)
[System.IO.File]::WriteAllText($FichierHome, $codeHome, $utf8)
Write-Host ("Cree     : " + $FichierBarre) -ForegroundColor Green
Write-Host ("Modifie  : " + $FichierHome) -ForegroundColor Green

# --- Verification (optionnelle)
if ($Verifier) {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Write-Host "flutter introuvable : verification ignoree." -ForegroundColor Yellow
        return
    }
    Push-Location $App
    Write-Host ""
    Write-Host "=== dart format ===" -ForegroundColor Cyan
    & dart format lib
    Write-Host ""
    Write-Host "=== flutter analyze ===" -ForegroundColor Cyan
    & flutter analyze
    Write-Host ""
    Write-Host "=== flutter test ===" -ForegroundColor Cyan
    & flutter test
    Pop-Location
}

Write-Host ""
Write-Host "Termine. Relance l'application (flutter run) et teste :" -ForegroundColor Cyan
Write-Host "  1. Demarre le chrono, va sur une autre page."
Write-Host "  2. La barre 'Chrono en cours' doit apparaitre en haut avec Pause et Terminer."
