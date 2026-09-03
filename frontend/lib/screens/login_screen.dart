import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';
import 'main_navigation.dart';

const _googleWebClientId =
    '27094083724-l4ubt86s3v72v9phjtol9nn04a0g2adt.apps.googleusercontent.com';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
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
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const MainNavigation()),
    (route) => false,
  );
}

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final resultado = await AuthService.login(
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

  Future<void> _loginConGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

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
        _error = 'Error al iniciar sesión con Google';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0B1620), Color(0xFF0E1113)],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 220,
            child: CustomPaint(painter: _SkylinePainter()),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.safe, width: 2.5),
                    ),
                    child: const Icon(Icons.location_on,
                        color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 18),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                      children: [
                        TextSpan(text: 'Safe', style: TextStyle(color: AppColors.textPrimary)),
                        TextSpan(text: '360', style: TextStyle(color: AppColors.safe)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Camina seguro, siempre acompañado',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 36),
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
                    obscureText: _obscure,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Contraseña',
                      prefixIcon:
                          const Icon(Icons.lock_outline, color: AppColors.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
                      child: const Text('¿Olvidaste tu contraseña?',
                          style: TextStyle(color: AppColors.safe)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Iniciar sesión'),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    const Expanded(child: Divider(color: AppColors.surfaceLight)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('o continúa con',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                    const Expanded(child: Divider(color: AppColors.surfaceLight)),
                  ]),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _loginConGoogle,
                    icon: const Icon(Icons.g_mobiledata,
                        color: AppColors.textPrimary, size: 26),
                    label: const Text('Continuar con Google'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.surfaceLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await AuthService.loginAsGuest();
                      _goHome();
                    },
                    icon: const Icon(Icons.people_outline, size: 18),
                    label: const Text('Continuar como invitado'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.surfaceLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('¿No tienes cuenta?',
                          style: TextStyle(color: AppColors.textSecondary)),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const RegisterScreen()),
                          );
                        },
                        child: const Text('Crear cuenta'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.35);
    final rects = [
      [0.0, 0.5, 0.12, 0.5],
      [0.12, 0.3, 0.10, 0.7],
      [0.24, 0.6, 0.08, 0.4],
      [0.35, 0.2, 0.14, 0.8],
      [0.55, 0.45, 0.10, 0.55],
      [0.68, 0.15, 0.16, 0.85],
      [0.86, 0.4, 0.14, 0.6],
    ];
    for (final r in rects) {
      canvas.drawRect(
        Rect.fromLTWH(r[0] * size.width, size.height * (1 - r[3]),
            r[2] * size.width, size.height * r[3]),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}