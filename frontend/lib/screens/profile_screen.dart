import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
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

  String _nombre = '';
  String _email = '';
  List<dynamic> _reportes = [];
  Map<String, dynamic>? _stats;
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

      // Cargar reportes y estadísticas en paralelo
      final responses = await Future.wait([
        http.get(Uri.parse('${ApiConfig.baseUrl}/reportes'), headers: {'Authorization': 'Bearer $token'}),
        http.get(Uri.parse('${ApiConfig.baseUrl}/users/$userId/stats'), headers: {'Authorization': 'Bearer $token'}),
      ]);

      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body);
        setState(() => _reportes = data is List ? data : (data['reportes'] ?? []));
      }

      if (responses[1].statusCode == 200) {
        setState(() => _stats = jsonDecode(responses[1].body));
      }

      setState(() => _loading = false);
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

  Widget _statCard(String valor, String etiqueta, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              valor,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              etiqueta,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trustScore = _stats?['historial_confianza'] ?? 1.0;
    final nivelConfianza = _stats?['nivel_confianza'] ?? 'Alto';
    final colorTrust = nivelConfianza == 'Alto'
        ? AppColors.safe
        : nivelConfianza == 'Medio'
            ? AppColors.warning
            : AppColors.danger;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Avatar y datos
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

                // TrustScore personal
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorTrust.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorTrust.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: colorTrust,
                        child: const Icon(Icons.shield, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tu TrustScore',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Nivel de confianza: $nivelConfianza',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(trustScore * 10).toStringAsFixed(1)}/10',
                        style: TextStyle(
                          color: colorTrust,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Estadísticas
                if (_stats != null) ...[
                  const Text(
                    'Mis estadísticas',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statCard(
                        '${_stats!['total_reportes'] ?? 0}',
                        'Total\nreportes',
                        AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      _statCard(
                        '${_stats!['reportes_verificados'] ?? 0}',
                        'Verificados',
                        AppColors.safe,
                      ),
                      const SizedBox(width: 8),
                      _statCard(
                        '${_stats!['reportes_pendientes'] ?? 0}',
                        'Pendientes',
                        AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      _statCard(
                        '${_stats!['reportes_rechazados'] ?? 0}',
                        'Rechazados',
                        AppColors.danger,
                      ),
                    ],
                  ),
                  if (_stats!['categoria_mas_reportada'] != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bar_chart, color: AppColors.textSecondary, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            'Categoría más reportada: ${_stats!['categoria_mas_reportada']}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],

                // Mis reportes
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

                // Contactos de confianza
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

                // Cerrar sesión
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