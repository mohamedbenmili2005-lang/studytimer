import 'package:flutter/material.dart';
import 'api.dart';
import 'home_page.dart';
import 'login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.instance.loadToken();
  runApp(const StudyApp());
}

class StudyApp extends StatefulWidget {
  const StudyApp({super.key});
  @override
  State<StudyApp> createState() => _StudyAppState();
}

class _StudyAppState extends State<StudyApp> {
  bool loggedIn = Api.instance.token != null;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Study Timer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5), useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF4F46E5),
          brightness: Brightness.dark,
          useMaterial3: true),
      home: loggedIn
          ? HomePage(onLogout: () async {
              await Api.instance.logout();
              setState(() => loggedIn = false);
            })
          : LoginPage(onLoggedIn: () => setState(() => loggedIn = true)),
    );
  }
}
