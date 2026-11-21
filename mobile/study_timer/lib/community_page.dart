import 'package:flutter/material.dart';

import 'api.dart';
import 'api_extras.dart';
import 'room_page.dart';
import 'util.dart';
import 'widgets.dart';

/// Communaute : amis (invitations, activite) et salles d'etude.
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTabController(
    length: 2,
    child: Column(
      children: [
        TabBar(tabs: [Tab(text: 'Amis'), Tab(text: 'Salles')]),
        Expanded(child: TabBarView(children: [_FriendsTab(), _RoomsTab()])),
      ],
    ),
  );
}

class _FriendsTab extends StatefulWidget {
  const _FriendsTab();
  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  final username = TextEditingController();
  List<Map<String, dynamic>> friends = [];
  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> feed = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    username.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final r = await Future.wait([
        Api.instance.friends(),
        Api.instance.friendRequests(),
        Api.instance.friendFeed(),
      ]);
      if (!mounted) return;
      setState(() {
        friends = r[0];
        requests = r[1];
        feed = r[2];
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

  Future<void> act(Future<void> Function() action, {String? ok}) async {
    try {
      await action();
      if (!mounted) return;
      if (ok != null) showMsg(context, ok);
      await reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> showStats(Map<String, dynamic> f) async {
    try {
      final s = await Api.instance.friendStats('${f['id']}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${f['username']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total : ${fmtShort((s['totalSeconds'] as num).toInt())}'),
              Text('Cette semaine : ${fmtShort((s['weekSeconds'] as num).toInt())}'),
              Text('S\u00e9ances : ${s['sessionsCount']}'),
              Text('Niveau : ${s['level']}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(
        context,
        e.status == 403 ? 'Les statistiques de cet ami ne sont pas visibles.' : e.message,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorView(message: error!, onRetry: reload);
    return RefreshIndicator(
      onRefresh: reload,
      child: Body(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Inviter un ami',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: username,
                      decoration: const InputDecoration(labelText: 'Pseudo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), 
                    onPressed: () {
                      final u = username.text.trim();
                      if (u.isEmpty) return;
                      username.clear();
                      act(() => Api.instance.inviteFriend(u), ok: 'Invitation envoy\u00e9e');
                    },
                    child: const Text('Inviter'),
                  ),
                ],
              ),
            ),
            if (requests.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionCard(
                title: 'Invitations re\u00e7ues',
                child: Column(
                  children: [
                    for (final r in requests)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${r['username']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Accepter',
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () => act(() => Api.instance.acceptFriend('${r['id']}')),
                            ),
                            IconButton(
                              tooltip: 'Refuser',
                              icon: const Icon(Icons.cancel_outlined),
                              onPressed: () => act(() => Api.instance.declineFriend('${r['id']}')),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SectionCard(
              title: 'Mes amis',
              child: friends.isEmpty
                  ? const Text('Aucun ami pour le moment.')
                  : Column(
                      children: [
                        for (final f in friends)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person_outline),
                            title: Text('${f['username']}'),
                            onTap: () => showStats(f),
                            trailing: IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: () => act(
                                () => Api.instance.removeFriend('${f['id']}'),
                                ok: 'Ami supprim\u00e9',
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Activit\u00e9 des amis',
              child: feed.isEmpty
                  ? const Text('Rien \u00e0 afficher pour le moment.')
                  : Column(
                      children: [
                        for (final s in feed)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${s['username']} \u00b7 ${fmtShort((s['seconds'] as num).toInt())}',
                            ),
                            subtitle: Text('${s['mode']}'),
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

class _RoomsTab extends StatefulWidget {
  const _RoomsTab();
  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<_RoomsTab> {
  final code = TextEditingController();
  List<Map<String, dynamic>> rooms = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final r = await Api.instance.rooms();
      if (!mounted) return;
      setState(() {
        rooms = r;
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

  void open(String id, String name) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => RoomPage(roomId: id, name: name)))
        .then((_) => reload());
  }

  Future<void> joinByCode() async {
    final c = code.text.trim();
    if (c.isEmpty) return;
    try {
      final r = await Api.instance.joinRoomByCode(c);
      code.clear();
      if (!mounted) return;
      open('${r['id']}', '${r['name']}');
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> openRoom(Map<String, dynamic> r) async {
    try {
      if (r['joined'] != true) await Api.instance.joinRoom('${r['id']}');
      if (!mounted) return;
      open('${r['id']}', '${r['name']}');
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> create() async {
    final name = TextEditingController();
    var isPublic = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nouvelle salle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom de la salle'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Salle publique'),
                value: isPublic,
                onChanged: (v) => setS(() => isPublic = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Cr\u00e9er')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final r = await Api.instance.createRoom(name.text.trim(), isPublic);
      if (!mounted) return;
      open('${r['id']}', name.text.trim());
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorView(message: error!, onRetry: reload);
    return RefreshIndicator(
      onRefresh: reload,
      child: Body(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Rejoindre par code',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Code de la salle'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: joinByCode, child: const Text('Rejoindre')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Salles',
              trailing: IconButton(
                tooltip: 'Cr\u00e9er une salle',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: create,
              ),
              child: rooms.isEmpty
                  ? const Text('Aucune salle. Cr\u00e9ez-en une !')
                  : Column(
                      children: [
                        for (final r in rooms)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(r['isPublic'] == true ? Icons.public : Icons.lock_outline),
                            title: Text('${r['name']}'),
                            subtitle: Text('${r['participants']} participant(s)'),
                            trailing: r['joined'] == true
                                ? const Icon(Icons.check_circle, size: 18)
                                : null,
                            onTap: () => openRoom(r),
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