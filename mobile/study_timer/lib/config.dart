/// Adresse de l'API. En production (même domaine derrière Nginx) :
///   flutter build web --release --dart-define=API_URL=
/// En développement : http://localhost:5293 (valeur par défaut).
const String _apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:5293',
);

String get baseUrl => _apiUrl;
