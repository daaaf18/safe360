import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'contacts_screen.dart';
import 'safe_route_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  String _nombre = '';
  String _email = '';
  List<dynamic> _reportes = [];
  List<dynamic> _rutas = [];
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

      // Cargar reportes y estadísticas en paralelo.
      // usuario_id=$userId: antes esto pedía TODOS los reportes de todos
      // los usuarios (el endpoint no filtraba), así que "Mis reportes"
      // mostraba reportes ajenos.
      final responses = await Future.wait([
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/reportes?usuario_id=$userId&limite=100'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        http.get(Uri.parse('${ApiConfig.baseUrl}/users/$userId/stats'), headers: {'Authorization': 'Bearer $token'}),
        http.get(Uri.parse('${ApiConfig.baseUrl}/users/$userId/rutas'), headers: {'Authorization': 'Bearer $token'}),
      ]);

      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body);
        setState(() => _reportes = data is List ? data : (data['reportes'] ?? []));
      }

      if (responses[1].statusCode == 200) {
        setState(() => _stats = jsonDecode(responses[1].body));
      }

      if (responses[2].statusCode == 200) {
        final data = jsonDecode(responses[2].body);
        setState(() => _rutas = data is List ? data : []);
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

  /// Reportes agrupados por categoría — más recientes primero dentro de
  /// cada grupo, y grupos ordenados por cantidad de reportes (el más
  /// frecuente arriba).
  String _nombreCategoria(String categoria) {
    if (categoria == 'SOS_Automatico') return 'SOS automático';
    return categoria;
  }

  Map<String, List<dynamic>> get _reportesPorCategoria {
    final Map<String, List<dynamic>> grupos = {};
    for (final r in _reportes) {
      final categoriaCruda = (r['categoria'] as String?)?.trim();
      final clave = (categoriaCruda == null || categoriaCruda.isEmpty)
          ? 'Otro'
          : _nombreCategoria(categoriaCruda);
      grupos.putIfAbsent(clave, () => []).add(r);
    }
    final entradas = grupos.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Map.fromEntries(entradas);
  }

  IconData _iconCategoria(String categoria) {
    switch (categoria.toLowerCase()) {
      case 'robo':
      case 'acoso':
        return Icons.warning_amber_rounded;
      case 'poca iluminación':
        return Icons.lightbulb_outline;
      case 'accidente vial':
        return Icons.car_crash_outlined;
      case 'sos_automatico':
      case 'sos automático':
        return Icons.emergency;
      default:
        return Icons.more_horiz;
    }
  }

  void _abrirCategoria(String categoria, List<dynamic> reportes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(_iconCategoria(categoria), color: AppColors.safe, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '$categoria (${reportes.length})',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: reportes.length,
                itemBuilder: (_, i) {
                  final r = reportes[i];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        _iconEstado(r['estado'] ?? 'pendiente'),
                        color: _colorEstado(r['estado'] ?? 'pendiente'),
                      ),
                      title: Text(
                        (r['descripcion'] as String?)?.isNotEmpty == true
                            ? r['descripcion']
                            : categoria,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        r['created_at']?.toString().substring(0, 10) ?? '',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _rutaCard(Map<String, dynamic> r) {
    final origen = r['origen'] as Map<String, dynamic>?;
    final destino = r['destino'] as Map<String, dynamic>?;
    final esFrecuente = r['es_frecuente'] == true;
    final vecesUsada = r['veces_usada'] ?? 1;
    final distanciaKm = r['distancia_metros'] != null
        ? ((r['distancia_metros'] as num) / 1000).toStringAsFixed(1)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: (origen == null || destino == null)
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SafeRouteScreen(
                      initialOrigenLat: (origen['lat'] as num).toDouble(),
                      initialOrigenLon: (origen['lon'] as num).toDouble(),
                      initialDestinoLat: (destino['lat'] as num).toDouble(),
                      initialDestinoLon: (destino['lon'] as num).toDouble(),
                    ),
                  )),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      (esFrecuente ? AppColors.safe : AppColors.textSecondary).withOpacity(0.15),
                  child: Icon(Icons.alt_route,
                      color: esFrecuente ? AppColors.safe : AppColors.textSecondary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        esFrecuente ? 'Ruta frecuente · $vecesUsada veces' : 'Ruta reciente',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (distanciaKm != null || r['nivel_riesgo'] != null)
                        Text(
                          [
                            if (distanciaKm != null) '$distanciaKm km',
                            if (r['nivel_riesgo'] != null) 'riesgo ${r['nivel_riesgo']}',
                          ].join(' · '),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
              ],
            ),
          ),
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

                // Rutas frecuentes — reactivar con un toque en vez de
                // volver a escribir origen/destino en Ruta segura.
                if (_rutas.isNotEmpty) ...[
                  const Text(
                    'Rutas frecuentes',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ..._rutas.map((r) => _rutaCard(r)),
                  const SizedBox(height: 20),
                ],

                // Mis reportes — cajas por categoría (incluye
                // SOS_Automatico); tocar una caja abre la lista de esa
                // categoría en vez de mezclar todo en una sola lista.
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
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.5,
                    children: _reportesPorCategoria.entries.map((grupo) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _abrirCategoria(grupo.key, grupo.value),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.surfaceLight),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(_iconCategoria(grupo.key), color: AppColors.safe, size: 22),
                              Text(
                                grupo.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${grupo.value.length} reporte${grupo.value.length != 1 ? 's' : ''}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
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