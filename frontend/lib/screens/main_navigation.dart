import 'package:flutter/material.dart';
import '../widgets/bottom_nav.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'report_screen.dart';
import 'safe_route_screen.dart';
import 'chaty_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;
  bool _isGuest = false;

  final _screens = const [
    HomeScreen(),
    ReportScreen(),
    SafeRouteScreen(),
    ChatyScreen(),
    ProfileScreen(),
  ];

  final _nombresScreens = ['Mapa', 'Reportar', 'Ruta Segura', 'Chaty', 'Perfil'];

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  Future<void> _cargarEstado() async {
    final guest = await AuthService.isGuest();
    setState(() => _isGuest = guest);
  }

  Future<void> _onTap(int i) async {
    if (i == 0) {
      setState(() => _index = i);
      return;
    }
    if (_isGuest) {
      _mostrarDialogoLogin(_nombresScreens[i]);
      return;
    }
    setState(() => _index = i);
  }

  void _mostrarDialogoLogin(String pantalla) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2035),
        title: const Text(
          'Función no disponible',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '$pantalla requiere una cuenta. ¿Deseas iniciar sesión?',
          style: const TextStyle(color: Color(0xFF8BA4BC)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ahora no',
                style: TextStyle(color: Color(0xFF8BA4BC))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await AuthService.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Iniciar sesión'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Safe360BottomNav(
        currentIndex: _index,
        onTap: _onTap,
      ),
    );
  }
}