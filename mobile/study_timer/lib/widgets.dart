import 'package:flutter/material.dart';

/// Centre le contenu et limite sa largeur sur grand écran.
class Body extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const Body({super.key, required this.child, this.maxWidth = 760});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Carte avec titre.
class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

/// Indicateur chiffré (icône + valeur + libellé).
class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  if (hint != null)
                    Text(
                      hint!,
                      style: TextStyle(color: cs.outline, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// État d'erreur avec bouton « Réessayer ».
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
            onPressed: onRetry,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    ),
  );
}

/// État vide.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(message),
      ],
    ),
  );
}

String fmtCompact(int s) {
  if (s <= 0) return '';
  if (s >= 3600) return '${(s / 3600).toStringAsFixed(1)}h';
  return '${s ~/ 60}m';
}

/// Histogramme des 7 derniers jours (le dernier = aujourd'hui).
class WeekBars extends StatelessWidget {
  final List<Map<String, dynamic>> days;
  const WeekBars({super.key, required this.days});
  static const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxSec = days.fold<int>(
      1,
      (m, x) => (x['seconds'] as int) > m ? x['seconds'] as int : m,
    );
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    fmtCompact(days[i]['seconds'] as int),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 6 + 90.0 * (days[i]['seconds'] as int) / maxSec,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: i == days.length - 1
                          ? cs.primary
                          : cs.primary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    letters[DateTime.parse(days[i]['date'] as String).weekday -
                        1],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == days.length - 1
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
