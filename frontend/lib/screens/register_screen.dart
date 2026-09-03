import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import 'main_navigation.dart';

const _googleWebClientId =
    '27094083724-l4ubt86s3v72v9phjtol9nn04a0g2adt.apps.googleusercontent.com';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _acceptTerms = false;
  bool _loading = false;
  String? _error;

  // En Web, google_sign_in_web EXIGE que serverClientId sea null (hace un
  // assert). En Android, `clientId` se ignora y el idToken sale null si no
  // se manda `serverClientId`. Por eso el parámetro cambia según plataforma;
  // el valor es el mismo en ambos casos (GOOGLE_WEB_CLIENT_ID en backend/.env).
  final GoogleSignIn _googleSignIn = kIsWeb
      ? GoogleSignIn(clientId: _googleWebClientId)
      : GoogleSignIn(serverClientId: _googleWebClientId);

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigation()),
    );
  }

  Future<void> _register() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final resultado = await AuthService.register(
      _nombreController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text,
    );

    setState(() => _loading = false);

    if (resultado['success']) {
      _goHome();
    } else {
      setState(() => _error = resultado['error']);
    }
  }

  Future<void> _registrarConGoogle() async {
    setState(() { _loading = true; _error = null; });

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() => _loading = false);
        return;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        setState(() {
          _loading = false;
          _error = 'Google no devolvió credenciales válidas. Intenta de nuevo.';
        });
        return;
      }

      final resultado = await AuthService.loginConGoogle(idToken);

      setState(() => _loading = false);

      if (resultado['success']) {
        _goHome();
      } else {
        setState(() => _error = resultado['error']);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error al registrarse con Google';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ListView(
            children: [
              const SizedBox(height: 12),
              TextField(
                controller: _nombreController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person_outline, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Contraseña',
                  prefixIcon: Icon(Icons.lock_outline, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Confirmar contraseña',
                  prefixIcon: Icon(Icons.lock_outline, color: AppColors.textSecondary),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _acceptTerms,
                    activeColor: AppColors.safe,
                    onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      'Acepto los términos y condiciones y el aviso de privacidad',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: (_acceptTerms && !_loading) ? _register : null,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Registrarme'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: (_acceptTerms && !_loading) ? _registrarConGoogle : null,
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Registrarme con Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.surfaceLight),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}