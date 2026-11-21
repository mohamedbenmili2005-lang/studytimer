import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}

class Api {
  static final Api instance = Api._();
  late final Dio dio;
  String? token;
  String? refreshToken;

  Api._() {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (token != null) o.headers['Authorization'] = 'Bearer $token';
          h.next(o);
        },
      ),
    );
  }

  Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    refreshToken = p.getString('refreshToken');
  }

  Future<void> _saveTokens(dynamic d) async {
    token = d['token'];
    refreshToken = d['refreshToken'];
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token!);
    await p.setString('refreshToken', refreshToken!);
  }

  Future<void> logout() async {
    token = null;
    refreshToken = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('refreshToken');
  }

  /// Renouvelle le token d'accès avec le refresh token.
  Future<bool> _refresh() async {
    if (refreshToken == null) return false;
    try {
      final r = await Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 8),
          validateStatus: (s) => s != null && s < 500,
        ),
      ).post('/api/auth/refresh', data: {'refreshToken': refreshToken});
      if (r.statusCode == 200) {
        await _saveTokens(r.data);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<dynamic> _call(Future<Response> Function() request) async {
    try {
      var r = await request();
      if (r.statusCode == 401 && await _refresh()) {
        r = await request(); // 2e essai avec le nouveau token
      }
      final code = r.statusCode ?? 0;
      if (code >= 400) {
        final d = r.data;
        final msg = code == 401
            ? 'Session expirée ou identifiants invalides.'
            : (d is String && d.isNotEmpty
                  ? d
                  : (code == 409
                        ? 'Une séance est déjà en cours.'
                        : 'Erreur $code'));
        throw ApiException(msg, code);
      }
      return r.data;
    } on DioException {
      throw ApiException(
        'Serveur injoignable. Vérifiez que l\'API tourne et l\'adresse ($baseUrl).',
        0,
      );
    }
  }

  /// Appel authentifie reutilisable par les extensions (api_extras.dart).
  Future<dynamic> call(Future<Response> Function() request) => _call(request);

  Future<void> login(String email, String password) async {
    final d = await _call(
      () => dio.post(
        '/api/auth/login',
        data: {'email': email, 'password': password},
      ),
    );
    await _saveTokens(d);
  }

  Future<void> register(Map<String, dynamic> body) async {
    final d = await _call(() => dio.post('/api/auth/register', data: body));
    await _saveTokens(d);
  }

  Future<Map<String, dynamic>> profile() async => Map<String, dynamic>.from(
    await _call(() => dio.get('/api/users/profile')),
  );

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
        await _call(() => dio.put('/api/users/profile', data: body)),
      );

  Future<List<Map<String, dynamic>>> subjects() async {
    final d = await _call(() => dio.get('/api/subjects'));
    return (d as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createSubject(String name) async =>
      Map<String, dynamic>.from(
        await _call(() => dio.post('/api/subjects', data: {'name': name})),
      );

  Future<Map<String, dynamic>?> current() async {
    final d = await _call(() => dio.get('/api/sessions/current'));
    return d is Map<String, dynamic> ? d : null;
  }

  Future<Map<String, dynamic>> start(
    String mode,
    int? targetSeconds,
    String? subjectId,
  ) async => Map<String, dynamic>.from(
    await _call(
      () => dio.post(
        '/api/sessions/start',
        data: {
          'mode': mode,
          'targetSeconds': targetSeconds,
          'subjectId': subjectId,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> pause() async => Map<String, dynamic>.from(
    await _call(() => dio.post('/api/sessions/pause')),
  );

  Future<Map<String, dynamic>> resume() async => Map<String, dynamic>.from(
    await _call(() => dio.post('/api/sessions/resume')),
  );

  Future<Map<String, dynamic>> stop() async => Map<String, dynamic>.from(
    await _call(() => dio.post('/api/sessions/stop')),
  );

  Future<List<Map<String, dynamic>>> history({int page = 1}) async {
    final d = await _call(
      () => dio.get(
        '/api/sessions/history',
        queryParameters: {'page': page, 'size': 50},
      ),
    );
    return (d as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> dashboard() async => Map<String, dynamic>.from(
    await _call(() => dio.get('/api/statistics/dashboard')),
  );

  // ---- Phase 2 : XP, badges, défis, classements ----
  Future<Map<String, dynamic>> progress() async =>
      Map<String, dynamic>.from(await _call(() => dio.get('/api/progress')));

  Future<List<Map<String, dynamic>>> leaderboard(String period) async {
    final d = await _call(
      () => dio.get('/api/leaderboard', queryParameters: {'period': period}),
    );
    return (d as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> challenges() async {
    final d = await _call(() => dio.get('/api/challenges'));
    return (d as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> createChallenge(Map<String, dynamic> body) async {
    await _call(() => dio.post('/api/challenges', data: body));
  }

  Future<void> joinChallenge(String id) async {
    await _call(() => dio.post('/api/challenges/$id/join'));
  }

  Future<List<Map<String, dynamic>>> challengeLeaderboard(String id) async {
    final d = await _call(() => dio.get('/api/challenges/$id/leaderboard'));
    return (d as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
