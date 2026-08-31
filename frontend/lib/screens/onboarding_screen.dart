import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _pagina = 0;

  final List<_OnboardingPage> _paginas = [
    _OnboardingPage(
      imagen: 'assets/chaty/chaty_neutral.png',
      titulo: '¡Hola! Soy Chaty 💚',
      descripcion: 'Tu asistente personal de seguridad. Estoy aquí para ayudarte a moverte por la ciudad de forma segura.',
    ),
    _OnboardingPage(
      imagen: 'assets/chaty/chaty_escuchando.png',
      titulo: 'Háblame por voz',
      descripcion: 'Solo dime a dónde vas y calcularé la ruta más segura para ti. Sin tocar la pantalla.',
    ),
    _OnboardingPage(
      imagen: 'assets/chaty/chaty_emergencia.png',
      titulo: 'Tu seguridad primero',
      descripcion: 'Si dices "auxilio" o "ayuda", activo el SOS al instante y alerto a tus contactos de confianza.',
    ),
    _OnboardingPage(
      imagen: 'assets/chaty/chaty_feliz.png',
      titulo: '¡Empecemos!',
      descripcion: 'Safe360 cruza datos reales de iluminación, reportes ciudadanos e IA para que siempre llegues segura.',
    ),
  ];

  void _siguiente() async {
    if (_pagina < _paginas.length - 1) {
      setState(() => _pagina++);
    } else {
      await AuthService.setFirstTimeDone();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _paginas[_pagina];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              // Indicadores de página
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_paginas.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _pagina ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _pagina ? AppColors.safe : AppColors.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
              const SizedBox(height: 48),

              // Avatar de Chaty
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Image.asset(
                  p.imagen,
                  key: ValueKey(p.imagen),
                  height: 220,
                ),
              ),
              const SizedBox(height: 48),

              // Título
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  p.titulo,
                  key: ValueKey(p.titulo),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),

              // Descripción
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  p.descripcion,
                  key: ValueKey(p.descripcion),
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const Spacer(),

              // Botón siguiente
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _siguiente,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.safe,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _pagina < _paginas.length - 1 ? 'Siguiente' : '¡Empecemos!',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              if (_pagina < _paginas.length - 1) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _siguiente,
                  child: const Text(
                    'Saltar',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final String imagen;
  final String titulo;
  final String descripcion;

  const _OnboardingPage({
    required this.imagen,
    required this.titulo,
    required this.descripcion,
  });
}