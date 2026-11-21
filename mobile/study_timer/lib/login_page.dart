import 'package:flutter/material.dart';

import 'api.dart';
import 'logo.dart';
import 'theme.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginPage({super.key, required this.onLoggedIn});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final username = TextEditingController();
  bool welcome = true;
  bool register = false;
  bool loading = false;
  bool hide = true;
  String? error;

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (register) {
        await Api.instance.register({
          'firstName': firstName.text.trim(),
          'lastName': lastName.text.trim(),
          'username': username.text.trim(),
          'email': email.text.trim(),
          'password': password.text,
          'country': 'TN',
          'timeZone': 'Africa/Tunis',
        });
      } else {
        await Api.instance.login(email.text.trim(), password.text);
      }
      widget.onLoggedIn();
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget input(
    TextEditingController c,
    String hint,
    IconData icon, {
    bool pwd = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      obscureText: pwd && hide,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: pwd
            ? IconButton(
                icon: Icon(
                  hide
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => hide = !hide),
              )
            : null,
      ),
    ),
  );

  Widget buildWelcome() => Scaffold(
    backgroundColor: kDark,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                const AppLogo(size: 120),
                const SizedBox(height: 20),
                const Text(
                  'Study Timer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Mesurez votre temps d\'étude, gardez votre série et relevez des défis avec vos amis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kYellow,
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: () => setState(() => welcome = false),
                  child: const Text('Commencer'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget buildAuth() => Scaffold(
    backgroundColor: kDark,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              color: Colors.white,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                welcome = true;
                error = null;
              }),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          register ? 'Créer un compte' : 'Connexion',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bienvenue sur Study Timer',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (register) ...[
                          input(firstName, 'Prénom', Icons.person_outline),
                          input(lastName, 'Nom', Icons.person_outline),
                          input(username, 'Pseudonyme', Icons.alternate_email),
                        ],
                        input(email, 'Adresse email', Icons.mail_outline),
                        input(
                          password,
                          'Mot de passe (8 caractères min.)',
                          Icons.lock_outline,
                          pwd: true,
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        FilledButton(
                          onPressed: loading ? null : submit,
                          child: Text(
                            loading
                                ? '...'
                                : (register
                                      ? 'Créer le compte'
                                      : 'Se connecter'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: () => setState(() {
                              register = !register;
                              error = null;
                            }),
                            child: Text(
                              register
                                  ? 'J\'ai déjà un compte · Connexion'
                                  : 'Pas de compte ? Inscription',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => welcome ? buildWelcome() : buildAuth();
}
