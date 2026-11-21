import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'api.dart';

/// Petit message en bas d'ecran.
void showMsg(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Appels API des modules Communaute, Salles, Planificateur et Notifications.
extension ApiExtras on Api {
  Future<List<Map<String, dynamic>>> _list(Future<Response> Function() request) async {
    final d = await call(request);
    return d is List ? List<Map<String, dynamic>>.from(d) : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> _map(Future<Response> Function() request) async =>
      Map<String, dynamic>.from(await call(request));

  // --- Amis
  Future<List<Map<String, dynamic>>> friends() => _list(() => dio.get('/api/friends'));
  Future<List<Map<String, dynamic>>> friendRequests() =>
      _list(() => dio.get('/api/friends/requests'));
  Future<List<Map<String, dynamic>>> friendFeed() => _list(() => dio.get('/api/friends/feed'));
  Future<List<Map<String, dynamic>>> friendsLeaderboard([String period = 'week']) =>
      _list(() => dio.get('/api/friends/leaderboard', queryParameters: {'period': period}));
  Future<Map<String, dynamic>> friendStats(String userId) =>
      _map(() => dio.get('/api/friends/$userId/stats'));
  Future<void> inviteFriend(String username) async {
    await call(() => dio.post('/api/friends/invite', data: {'username': username}));
  }

  Future<void> acceptFriend(String id) async {
    await call(() => dio.post('/api/friends/$id/accept'));
  }

  Future<void> declineFriend(String id) async {
    await call(() => dio.post('/api/friends/$id/decline'));
  }

  Future<void> removeFriend(String userId) async {
    await call(() => dio.delete('/api/friends/$userId'));
  }

  // --- Confidentialite (RG07)
  Future<Map<String, dynamic>> privacy() => _map(() => dio.get('/api/users/privacy'));
  Future<void> setPrivacy(bool showStats, bool showActivity) async {
    await call(() => dio.put('/api/users/privacy',
        data: {'showStats': showStats, 'showActivity': showActivity}));
  }

  // --- Taches
  Future<List<Map<String, dynamic>>> tasks({String status = 'all'}) =>
      _list(() => dio.get('/api/tasks', queryParameters: {'status': status}));
  Future<void> createTask(Map<String, dynamic> body) async {
    await call(() => dio.post('/api/tasks', data: body));
  }

  Future<void> completeTask(String id) async {
    await call(() => dio.post('/api/tasks/$id/complete'));
  }

  Future<void> deleteTask(String id) async {
    await call(() => dio.delete('/api/tasks/$id'));
  }

  // --- Salles
  Future<List<Map<String, dynamic>>> rooms() => _list(() => dio.get('/api/rooms'));
  Future<Map<String, dynamic>> room(String id) => _map(() => dio.get('/api/rooms/$id'));
  Future<Map<String, dynamic>> createRoom(String name, bool isPublic) =>
      _map(() => dio.post('/api/rooms', data: {'name': name, 'isPublic': isPublic}));
  Future<Map<String, dynamic>> joinRoomByCode(String code) =>
      _map(() => dio.post('/api/rooms/join', data: {'code': code}));
  Future<void> joinRoom(String id) async {
    await call(() => dio.post('/api/rooms/$id/join'));
  }

  Future<void> leaveRoom(String id) async {
    await call(() => dio.post('/api/rooms/$id/leave'));
  }

  Future<List<Map<String, dynamic>>> roomMessages(String id) =>
      _list(() => dio.get('/api/rooms/$id/messages'));
  Future<void> sendRoomMessage(String id, String text) async {
    await call(() => dio.post('/api/rooms/$id/messages', data: {'text': text}));
  }

  // --- Notifications
  Future<Map<String, dynamic>> notifications() => _map(() => dio.get('/api/notifications'));
  Future<void> readAllNotifications() async {
    await call(() => dio.post('/api/notifications/read-all'));
  }

  // --- Calendrier d'activite
  Future<List<Map<String, dynamic>>> heatmap({int days = 365}) =>
      _list(() => dio.get('/api/statistics/heatmap', queryParameters: {'days': days}));
}