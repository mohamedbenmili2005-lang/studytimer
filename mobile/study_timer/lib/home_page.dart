import 'package:flutter/material.dart';

import 'challenges_page.dart';
import 'community_page.dart';
import 'planner_page.dart';
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
  int tick =
      0; // change apres une action de la barre : recharge la page affichee

  static const dests = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Accueil'),
    (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Stats'),
    (Icons.timer_outlined, Icons.timer, 'Timer'),
    (Icons.history, Icons.history, 'Historique'),
    (Icons.person_outline, Icons.person, 'Profil'),
    (Icons.emoji_events_outlined, Icons.emoji_events, 'D\u00E9fis'),
    (Icons.group_outlined, Icons.group, 'Communaut\u00e9'),
    (Icons.event_note_outlined, Icons.event_note, 'Planificateur'),
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
    6 => const CommunityPage(),
    7 => const PlannerPage(),
    _ => const ProfilePage(),
  };

  /// Barre du chrono (sauf sur la page Timer) + page courante.
  Widget content() => Column(
    children: [
      index == 2
          ? const SizedBox.shrink()
          : SessionBar(
              onOpen: () => go(2),
              onChanged: () => setState(() => tick++),
            ),
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
            navItem(6),
            const SizedBox(width: 72),
            navItem(7),
            navItem(3),
            navItem(4),
          ],
        ),
      ),
    );
  }
}
