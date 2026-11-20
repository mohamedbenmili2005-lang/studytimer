import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Adresse de l'API.
/// - Émulateur Android : 10.0.2.2 désigne le PC.
/// - Vrai téléphone : remplacez par l'IP du PC (ex. http://192.168.1.20:5293).
String get baseUrl {
  if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:5293';
  return 'http://localhost:5293';
}


