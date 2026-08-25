import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';
import '../widgets/safe360_map.dart';

class SafeRouteScreen extends StatefulWidget {
  const SafeRouteScreen({super.key});

  @override
  State<SafeRouteScreen> createState() => _SafeRouteScreenState();
}

class _SafeRouteScreenState extends State<SafeRouteScreen> {
  static const String baseUrl = 'http://localhost:3000';

  final _origenCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _ruta;

  // Coordenadas de prueba en Puebla
  // Origen: BUAP, Destino: Zócalo de Puebla
  final _origenLat = 19.0434;
  final _origenLon = -98.1983;
  final _destinoLat = 19.0432;
  final _destinoLon = -98.1982;

  Future<void> _calcularRuta() async {
    if (_origenCtrl.text.trim().isEmpty || _destinoCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa origen y destino');
      return;
    }

    setState(() { _loading = true; _error = null; _ruta = null; });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() { _loading = false; _error = 'Debes iniciar sesión'; });
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
        setState(() => _ruta = jsonDecode(response.body));
      } else {
        final data = jsonDecode(response.body);
        setState(() => _error = data['error'] ?? 'Error al calcular la ruta');
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error de conexión con el servidor';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trustScore = _ruta?['trust_score_promedio'] ?? 8.2;
    final nivelRiesgo = trustScore >= 7 ? 'Riesgo bajo' : trustScore >= 4 ? 'Riesgo medio' : 'Riesgo alto';
    final colorScore = trustScore >= 7 ? AppColors.safe : trustScore >= 4 ? AppColors.warning : AppColors.danger;

    return Scaffold(
      appBar: AppBar(title: const Text('Ruta segura')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 260,
              child: Safe360Map(
                showRoute: true,
                centerLat: (_origenLat + _destinoLat) / 2,
                centerLon: (_origenLon + _destinoLon) / 2,
                routeOriginLat: _origenLat,
                routeOriginLon: _origenLon,
                routeDestLat: _destinoLat,
                routeDestLon: _destinoLon,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScore,
                    child: const Icon(Icons.shield, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TrustScore de la ruta',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$nivelRiesgo en horario actual',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${trustScore.toStringAsFixed(1)}/10',
                    style: TextStyle(color: colorScore, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
        ],
      ),
    );
  }
}