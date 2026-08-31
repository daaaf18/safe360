import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';
import '../config.dart';

class SafeRouteScreen extends StatefulWidget {
  const SafeRouteScreen({super.key});

  @override
  State<SafeRouteScreen> createState() => _SafeRouteScreenState();
}

class _SafeRouteScreenState extends State<SafeRouteScreen> {
  String get baseUrl => ApiConfig.baseUrl;

  final _origenCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _ruta;
  bool _modoOffline = false;

  // Coordenadas de prueba en Puebla
  // Origen: BUAP, Destino: Zócalo de Puebla
  final _origenLat = 19.0434;
  final _origenLon = -98.1983;
  final _destinoLat = 19.0432;
  final _destinoLon = -98.1982;

  Future<void> _guardarRutaEnCache(Map<String, dynamic> ruta) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('ultima_ruta', jsonEncode(ruta));
}

  Future<Map<String, dynamic>?> _cargarRutaDeCache() async {
  final prefs = await SharedPreferences.getInstance();
  final rutaJson = prefs.getString('ultima_ruta');
  if (rutaJson == null) return null;
  return jsonDecode(rutaJson) as Map<String, dynamic>;
}

  Future<void> _calcularRuta() async {
    if (_origenCtrl.text.trim().isEmpty || _destinoCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa origen y destino');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _ruta = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() {
          _loading = false;
          _error = 'Debes iniciar sesión';
        });
        return;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/rutas/segura'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'origen_lat': _origenLat,
          'origen_lon': _origenLon,
          'destino_lat': _destinoLat,
          'destino_lon': _destinoLon,
        }),
      );

      setState(() => _loading = false);

      if (response.statusCode == 200) {
          final rutaData = jsonDecode(response.body) as Map<String, dynamic>;
        await _guardarRutaEnCache(rutaData);
        setState(() {
        _ruta = rutaData;
        _modoOffline = false;
      });
      } else {
        final data = jsonDecode(response.body);
        setState(() => _error = data['error'] ?? 'Error al calcular la ruta');
      }
    } catch (e) {
  final rutaCache = await _cargarRutaDeCache();
  setState(() {
    _loading = false;
    if (rutaCache != null) {
      _ruta = rutaCache;
      _modoOffline = true;
      _error = null;
    } else {
      _modoOffline = false;
      _error = 'Sin conexión y no hay ruta guardada';
      }
    });
  }
}
  @override
  Widget build(BuildContext context) {
    final trustScore = (_ruta?['trust_score_promedio'] as num?)?.toDouble();
    final nivelRiesgo = _ruta?['nivel_riesgo'] as String? ??
        (trustScore == null
            ? null
            : trustScore >= 7
                ? 'Riesgo bajo'
                : trustScore >= 4
                    ? 'Riesgo medio'
                    : 'Riesgo alto');
    final colorScore = trustScore == null
        ? AppColors.textSecondary
        : trustScore >= 7
            ? AppColors.safe
            : trustScore >= 4
                ? AppColors.warning
                : AppColors.danger;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.alt_route, color: AppColors.safe, size: 20),
            SizedBox(width: 8),
            Text('Ruta segura'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Center(
            child: Text('Planifica tu camino más seguro',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _origenCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Origen',
              prefixIcon: Icon(Icons.trip_origin, color: AppColors.safe),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _destinoCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Destino',
              prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.danger),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading ? null : _calcularRuta,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Calcular ruta segura'),
          ),
          if (_modoOffline) ...[
  const SizedBox(height: 8),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.warning.withOpacity(0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.warning.withOpacity(0.4)),
    ),
    child: Row(
      children: const [
        Icon(Icons.wifi_off, size: 14, color: AppColors.warning),
        SizedBox(width: 8),
        Expanded(
          child: Text('Sin conexión — mostrando última ruta guardada',
              style: TextStyle(color: AppColors.warning, fontSize: 11)),
        ),
      ],
    ),
  ),
],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 230,
              color: const Color(0xFF1A2A2E),
              child: Stack(
                children: [
                  const Center(
                    child: Icon(Icons.alt_route, color: Colors.white38, size: 40),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Riesgo en la ruta',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 10)),
                          SizedBox(height: 4),
                          _LegendDot(color: AppColors.safe, label: 'Bajo'),
                          _LegendDot(color: AppColors.warning, label: 'Moderado'),
                          _LegendDot(color: AppColors.danger, label: 'Alto'),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Text(
                      'Ver mapa completo en la pestaña Mapa',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_ruta != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: colorScore.withOpacity(0.15),
                          child: Icon(Icons.shield, color: colorScore),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('TrustScore de la ruta',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              Text(nivelRiesgo ?? '—',
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(
                          trustScore != null ? '${trustScore.toStringAsFixed(1)}/10' : '—',
                          style: TextStyle(
                              color: colorScore, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                    const Divider(height: 28, color: AppColors.surfaceLight),
                    _stat('Reportes en la zona', _ruta?['reportes_en_zona']),
                    _stat('Reportes graves', _ruta?['reportes_graves']),
                    _stat('Luminarias fundidas', _ruta?['luminarias_fundidas']),
                    _stat('Distancia', _ruta?['distancia_metros'] != null
                        ? '${((_ruta!['distancia_metros'] as num) / 1000).toStringAsFixed(1)} km'
                        : null),
                  ],
                ),
              ),
            ),
            if (_ruta?['mensaje'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_ruta!['mensaje'],
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.surfaceLight),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Ver ruta alternativa'),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text('Ingresa origen y destino, luego calcula tu ruta segura',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text(value?.toString() ?? '—',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Container(
              width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
        ],
      ),
    );
  }
}