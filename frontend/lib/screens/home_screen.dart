import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../theme.dart';
import '../widgets/safe360_map.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import 'sos_screen.dart';
import 'report_screen.dart';
import 'safe_route_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // baseUrl centralizado en config.dart

  // `_reportes`: TODOS los que caben en la página (para pintar el mapa —
  // pines y mancha de calor de Puebla completa, no solo tu alrededor).
  // `_reportesCerca`: filtrados de verdad por distancia real a tu GPS —
  // esto es lo que alimenta "X reportes cerca", "Tu zona" y los chips de
  // "Incidentes cerca de ti". Antes las tres cosas usaban `_reportes` sin
  // ningún filtro de ubicación — decían "cerca" pero en realidad eran
  // nada más los primeros 20 reportes de toda la base de datos (el límite
  // por defecto del backend), viniera de donde viniera el usuario.
  List<dynamic> _reportes = [];
  List<dynamic> _reportesCerca = [];
  static const double _radioCercaMetros = 1500;

  String _nivelZona = 'Cargando...';
  Color _colorZona = AppColors.textSecondary;
  double _scoreZona = 0.0;

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  Future<void> _cargarReportes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final ubicacion = await LocationService.obtenerUbicacionActual();

      final peticiones = <Future<http.Response>>[
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/reportes?limite=100'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ];
      if (ubicacion.exito) {
        peticiones.add(http.get(
          Uri.parse('${ApiConfig.baseUrl}/reportes').replace(queryParameters: {
            'latitud': '${ubicacion.posicion!.latitude}',
            'longitud': '${ubicacion.posicion!.longitude}',
            'radio': '$_radioCercaMetros',
            'limite': '100',
          }),
          headers: {'Authorization': 'Bearer $token'},
        ));
      }

      final respuestas = await Future.wait(peticiones);

      List<dynamic> reportes = [];
      if (respuestas[0].statusCode == 200) {
        final data = jsonDecode(respuestas[0].body);
        reportes = data is List ? data : (data['reportes'] ?? []);
      }

      // Si no se pudo obtener el GPS, mejor no fingir un "cerca" que en
      // realidad no lo es — se queda vacío (la UI ya oculta esas
      // secciones cuando la lista está vacía) en vez de mostrar de nuevo
      // reportes de cualquier parte de la ciudad como si fueran locales.
      List<dynamic> reportesCerca = [];
      if (ubicacion.exito && respuestas.length > 1 && respuestas[1].statusCode == 200) {
        final data = jsonDecode(respuestas[1].body);
        reportesCerca = data is List ? data : (data['reportes'] ?? []);
      }

      // Calcular nivel de zona según los reportes DE VERDAD cerca de ti.
      final verificados = reportesCerca.where((r) => r['estado'] == 'verificado').length;
      final total = reportesCerca.length;
      final score = total == 0 ? 10.0 : ((total - verificados) / total * 10).clamp(0.0, 10.0);

      setState(() {
        _reportes = reportes;
        _reportesCerca = reportesCerca;
        _scoreZona = score;
        if (!ubicacion.exito) {
          _nivelZona = 'Activa el GPS para ver tu zona';
          _colorZona = AppColors.textSecondary;
        } else if (score >= 7) {
          _nivelZona = 'Zona segura ahora';
          _colorZona = AppColors.safe;
        } else if (score >= 4) {
          _nivelZona = 'Zona de riesgo medio';
          _colorZona = AppColors.warning;
        } else {
          _nivelZona = 'Zona de alto riesgo';
          _colorZona = AppColors.danger;
        }
      });
    } catch (e) {
      setState(() {
        _nivelZona = 'Sin conexión';
        _colorZona = AppColors.textSecondary;
      });
    }
  }

  Color _colorCategoria(String categoria) {
    switch (categoria.toLowerCase()) {
      case 'robo':
      case 'acoso':
        return AppColors.danger;
      case 'poca iluminación':
      case 'accidente vial':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  Map<String, int> get _conteoPorCategoria {
    final Map<String, int> conteo = {};
    for (final r in _reportesCerca) {
      final cat = (r['categoria'] ?? 'Otro').toString();
      conteo[cat] = (conteo[cat] ?? 0) + 1;
    }
    return conteo;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Barra superior
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.shield, color: AppColors.safe, size: 22),
                const SizedBox(width: 8),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(text: 'Safe', style: TextStyle(color: AppColors.textPrimary)),
                      TextSpan(text: '360', style: TextStyle(color: AppColors.safe)),
                    ],
                  ),
                ),
                const Spacer(),
                // Antes había una campanita de notificaciones decorativa
                // sin ninguna función real detrás (no hay sistema de
                // notificaciones push todavía — sería una función aparte,
                // bastante más grande). La quitamos para no confundir con
                // un botón muerto; este menú sí hace algo de verdad.
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
                  color: AppColors.surface,
                  onSelected: (valor) async {
                    if (valor == 'perfil') {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    } else if (valor == 'cerrar_sesion') {
                      await AuthService.logout();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'perfil',
                      child: Text('Mi perfil', style: TextStyle(color: AppColors.textPrimary)),
                    ),
                    PopupMenuItem(
                      value: 'cerrar_sesion',
                      child: Text('Cerrar sesión', style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Mapa real + overlays
          Expanded(
            child: Stack(
              children: [
                Safe360Map(reportes: _reportes, showHeatmap: true),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 90,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: _colorZona, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _nivelZona,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('Score: ${_scoreZona.toStringAsFixed(1)}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SosScreen()),
                      );
                    },
                    child: Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.danger.withOpacity(0.5),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone, color: Colors.white, size: 18),
                          Text('SOS',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_reportesCerca.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 96,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_reportesCerca.length} reporte${_reportesCerca.length != 1 ? 's' : ''} '
                              'a menos de ${(_radioCercaMetros / 1000).toStringAsFixed(1)} km',
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Panel inferior
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _colorZona.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.shield, color: _colorZona),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tu zona',
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          Text(_nivelZona,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _quickAction(context, Icons.warning_amber_rounded, 'Reportar',
                          'Un incidente', () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ReportScreen()));
                      }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _quickAction(context, Icons.alt_route, 'Crear ruta',
                          'Planifica tu camino', () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SafeRouteScreen()));
                      }),
                    ),
                  ],
                ),
                if (_conteoPorCategoria.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Incidentes cerca de ti',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _conteoPorCategoria.entries
                          .map((e) => _chip(e.key, e.value, _colorCategoria(e.key)))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(BuildContext context, IconData icon, String title, String subtitle,
      VoidCallback onTap, {Color color = AppColors.safe}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  Text(subtitle,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, int count, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
              width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
          const SizedBox(width: 6),
          Text('$count', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
