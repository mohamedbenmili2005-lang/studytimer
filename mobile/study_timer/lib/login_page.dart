import 'package:flutter/material.dart';
import 'api.dart';

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
  bool register = false;
  bool loading = false;
  String? error;

  Future<void> submit() async {
    setState(() { loading = true; error = null; });
    try {
      if (register) {
        await Api.instance.register({
          'firstName': firstName.text.trim(),
          'lastName': lastName.text.trim(),
          'username': username.text.trim(),
          'email': email.text.trim(),
          'password': password.text,
          'country': 'TN',
          'timeZone': 'Africa/Tunis', // à rendre configurable plus tard
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

  Widget field(TextEditingController c, String label, {bool obscure = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: obscure,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(children: [
              Text('Study Timer', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              if (register) ...[
                field(firstName, 'Prénom'),
                field(lastName, 'Nom'),
                field(username, 'Pseudonyme'),
              ],
              field(email, 'Email'),
              field(password, 'Mot de passe (8 caractères min.)', obscure: true),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: loading ? null : submit,
                  child: Text(loading ? '...' : (register ? 'Créer le compte' : 'Se connecter')),
                ),
              ),
              TextButton(
                onPressed: () => setState(() { register = !register; error = null; }),
                child: Text(register ? 'J\'ai déjà un compte' : 'Créer un compte'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
