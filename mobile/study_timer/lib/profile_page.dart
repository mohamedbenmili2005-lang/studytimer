import 'package:flutter/material.dart';

import 'api.dart';
import 'widgets.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const zones = [
    'Africa/Tunis',
    'Africa/Algiers',
    'Africa/Casablanca',
    'Africa/Lagos',
    'Africa/Cairo',
    'Europe/Paris',
    'UTC',
  ];

  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final country = TextEditingController();
  String zone = 'UTC';
  String username = '';
  String email = '';
  String initials = '?';
  bool loading = true;
  bool saving = false;
  String? error;
  String? info;

  @override
  void initState() {
    super.initState();
    load();
  }

  String makeInitials() {
    final a = firstName.text.trim();
    final b = lastName.text.trim();
    final s = '${a.isNotEmpty ? a[0] : ''}${b.isNotEmpty ? b[0] : ''}'
        .toUpperCase();
    return s.isEmpty ? '?' : s;
  }

  Future<void> load() async {
    try {
      final p = await Api.instance.profile();
      if (!mounted) return;
      setState(() {
        firstName.text = p['firstName'] ?? '';
        lastName.text = p['lastName'] ?? '';
        country.text = p['country'] ?? '';
        zone = p['timeZone'] ?? 'UTC';
        username = p['username'] ?? '';
        email = p['email'] ?? '';
        initials = makeInitials();
        loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.message;
        });
      }
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
      info = null;
    });
    try {
      await Api.instance.updateProfile({
        'firstName': firstName.text.trim(),
        'lastName': lastName.text.trim(),
        'country': country.text.trim().isEmpty ? null : country.text.trim(),
        'timeZone': zone,
      });
      setState(() {
        initials = makeInitials();
        info = 'Profil enregistré.';
      });
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final cs = Theme.of(context).colorScheme;
    final items = zones.contains(zone) ? zones : [zone, ...zones];
    return Body(
      maxWidth: 520,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '@$username',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(email, style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Informations personnelles',
            child: Column(
              children: [
                TextField(
                  controller: firstName,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastName,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: country,
                  decoration: const InputDecoration(
                    labelText: 'Pays (code, ex. TN)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: zone,
                  decoration: const InputDecoration(
                    labelText: 'Fuseau horaire',
                  ),
                  items: [
                    for (final z in items)
                      DropdownMenuItem(value: z, child: Text(z)),
                  ],
                  onChanged: (v) => setState(() => zone = v!),
                ),
                const SizedBox(height: 16),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(error!, style: TextStyle(color: cs.error)),
                  ),
                if (info != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(info!, style: TextStyle(color: cs.primary)),
                  ),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? '...' : 'Enregistrer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
