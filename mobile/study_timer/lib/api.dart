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

  Api._() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (s) => s != null && s < 500,
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (token != null) o.headers['Authorization'] = 'Bearer $token';
      h.next(o);
    }));
  }

  Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
  }

  Future<void> _saveToken(String t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', t);
  }

  Future<void> logout() async {
    token = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
  }

  Future<dynamic> _call(Future<Response> Function() request) async {
    try {
      final r = await request();
      final code = r.statusCode ?? 0;
      if (code >= 400) {
        final d = r.data;
        final msg = code == 401
            ? 'Session expirée ou identifiants invalides.'
            : (d is String && d.isNotEmpty ? d : 'Erreur $code');
        throw ApiException(msg, code);
      }
      return r.data;
    } on DioException {
      throw ApiException(
          'Serveur injoignable. Vérifiez que l\'API tourne et l\'adresse ($baseUrl).', 0);
    }
  }

  Future<void> login(String email, String password) async {
    final d = await _call(() =>
        dio.post('/api/auth/login', data: {'email': email, 'password': password}));
    await _saveToken(d['token']);
  }

  Future<void> register(Map<String, dynamic> body) async {
    final d = await _call(() => dio.post('/api/auth/register', data: body));
    await _saveToken(d['token']);
  }

  /// Séance active, ou null s'il n'y en a pas.
  Future<Map<String, dynamic>?> current() async {
    final d = await _call(() => dio.get('/api/sessions/current'));
    return d is Map<String, dynamic> ? d : null;
  }

  Future<Map<String, dynamic>> start(String mode, int? targetSeconds) async =>
      Map<String, dynamic>.from(await _call(() => dio.post('/api/sessions/start',
          data: {'mode': mode, 'targetSeconds': targetSeconds})));

  Future<Map<String, dynamic>> pause() async =>
      Map<String, dynamic>.from(await _call(() => dio.post('/api/sessions/pause')));

  Future<Map<String, dynamic>> resume() async =>
      Map<String, dynamic>.from(await _call(() => dio.post('/api/sessions/resume')));

  Future<Map<String, dynamic>> stop() async =>
      Map<String, dynamic>.from(await _call(() => dio.post('/api/sessions/stop')));

  Future<Map<String, dynamic>> dashboard() async =>
      Map<String, dynamic>.from(await _call(() => dio.get('/api/statistics/dashboard')));
}
