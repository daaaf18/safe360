import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../theme.dart';
import '../widgets/safe360_map.dart';
import 'sos_screen.dart';
import 'report_screen.dart';
import 'safe_route_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // baseUrl centralizado en config.dart

  List<dynamic> _reportes = [];
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

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/reportes'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reportes = data is List ? data : (data['reportes'] ?? []);

        // Calcular nivel de zona según reportes activos
        final verificados = reportes.where((r) => r['estado'] == 'verificado').length;
        final total = reportes.length;
        final score = total == 0 ? 10.0 : ((total - verificados) / total * 10).clamp(0.0, 10.0);

        setState(() {
          _reportes = reportes;
          _scoreZona = score;
          if (score >= 7) {
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
      }
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
    for (final r in _reportes) {
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
                const Icon(Icons.notifications_none, color: AppColors.textPrimary),
                const SizedBox(width: 16),
                const Icon(Icons.more_vert, color: AppColors.textPrimary),
              ],
            ),
          ),
          // Mapa real + overlays
          Expanded(
            child: Stack(
              children: [
                Safe360Map(reportes: _reportes),
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
                if (_reportes.isNotEmpty)
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
                              '${_reportes.length} reporte${_reportes.length != 1 ? 's' : ''} cerca',
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
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.safe, size: 20),
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
