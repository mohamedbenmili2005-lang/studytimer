import 'package:flutter/material.dart';
import 'stats_page.dart';
import 'timer_page.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onLogout;
  const HomePage({super.key, required this.onLogout});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(index == 0 ? 'Chronomètre' : 'Statistiques'),
        actions: [
          IconButton(
              tooltip: 'Déconnexion',
              icon: const Icon(Icons.logout),
              onPressed: widget.onLogout),
        ],
      ),
      body: index == 0 ? const TimerPage() : const StatsPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Timer'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
        ],
      ),
    );
  }
}
