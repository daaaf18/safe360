import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'contacts_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const String baseUrl = 'http://localhost:3000';

  String _nombre = '';
  String _email = '';
  List<dynamic> _reportes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final usuarioStr = prefs.getString('usuario');

      if (token == null || usuarioStr == null) {
        setState(() => _loading = false);
        return;
      }

      final usuario = jsonDecode(usuarioStr);
      final userId = usuario['id'];

      setState(() {
        _nombre = usuario['nombre'] ?? '';
        _email = usuario['email'] ?? '';
      });

      // Cargar reportes del usuario
      final response = await http.get(
        Uri.parse('$baseUrl/reportes'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _reportes = data is List ? data : (data['reportes'] ?? []);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _cerrarSesion() async {
    await AuthService.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  IconData _iconEstado(String estado) {
    switch (estado) {
      case 'verificado': return Icons.check_circle;
      case 'rechazado': return Icons.cancel;
      case 'en_revision': return Icons.hourglass_bottom;
      default: return Icons.hourglass_bottom;
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'verificado': return AppColors.safe;
      case 'rechazado': return AppColors.danger;
      default: return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.surface,
                  child: Icon(Icons.person, size: 42, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _nombre.isNotEmpty ? _nombre : 'Usuario',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    _email,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Mis reportes',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (_reportes.isEmpty)
                  const Text(
                    'Aún no has hecho ningún reporte.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ..._reportes.map((r) => Card(
                        child: ListTile(
                          leading: Icon(
                            _iconEstado(r['estado'] ?? 'pendiente'),
                            color: _colorEstado(r['estado'] ?? 'pendiente'),
                          ),
                          title: Text(
                            r['categoria'] ?? '',
                            style: const TextStyle(color: AppColors.textPrimary),
                          ),
                          subtitle: Text(
                            r['created_at']?.toString().substring(0, 10) ?? '',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.people_outline, color: AppColors.textPrimary),
                  title: const Text(
                    'Contactos de confianza',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ContactsScreen()),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: _cerrarSesion,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
    );
  }
}