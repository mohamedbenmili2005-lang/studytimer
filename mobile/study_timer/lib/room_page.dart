import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'api_extras.dart';
import 'util.dart';

/// Salle d'etude : participants (statut, temps du jour) et chat.
/// Les messages sont rafraichis toutes les 4 s (le hub SignalR /hubs/study est pret cote serveur).
class RoomPage extends StatefulWidget {
  final String roomId;
  final String name;
  const RoomPage({super.key, required this.roomId, required this.name});
  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final input = TextEditingController();
  Timer? poll;
  Map<String, dynamic>? room;
  List<Map<String, dynamic>> messages = [];
  String? error;

  @override
  void initState() {
    super.initState();
    refresh();
    poll = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
  }

  @override
  void dispose() {
    poll?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final r = await Api.instance.room(widget.roomId);
      final m = await Api.instance.roomMessages(widget.roomId);
      if (!mounted) return;
      setState(() {
        room = r;
        messages = m;
        error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    }
  }

  Future<void> send() async {
    final t = input.text.trim();
    if (t.isEmpty) return;
    input.clear();
    try {
      await Api.instance.sendRoomMessage(widget.roomId, t);
      await refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> leave() async {
    try {
      await Api.instance.leaveRoom(widget.roomId);
      if (!mounted) return;
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  String statusLabel(String s) => switch (s) {
    'Studying' => 'En \u00e9tude',
    'Paused' => 'En pause',
    _ => 'Hors ligne',
  };

  IconData statusIcon(String s) => switch (s) {
    'Studying' => Icons.local_fire_department,
    'Paused' => Icons.pause_circle_outline,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final parts = (room?['participants'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          if (room != null)
            IconButton(
              tooltip: 'Code de la salle',
              icon: const Icon(Icons.vpn_key_outlined),
              onPressed: () => showMsg(context, 'Code : ${room!['code']}'),
            ),
          IconButton(
            tooltip: 'Quitter la salle',
            icon: const Icon(Icons.exit_to_app),
            onPressed: leave,
          ),
        ],
      ),
      body: Column(
        children: [
          if (error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final p in parts)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: Icon(statusIcon('${p['status']}'), size: 18),
                      label: Text(
                        '${p['username']} \u00b7 ${statusLabel('${p['status']}')}'
                        ' \u00b7 ${fmtShort((p['todaySeconds'] as num).toInt())}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final m = messages[messages.length - 1 - i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${m['username']} : ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: '${m['text']}'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      maxLength: 500,
                      decoration: const InputDecoration(hintText: 'Votre message', counterText: ''),
                      onSubmitted: (_) => send(),
                    ),
                  ),
                  IconButton(onPressed: send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}