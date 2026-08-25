import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';
import '../widgets/safe360_map.dart';
import 'sos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String baseUrl = 'http://localhost:3000';

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
        Uri.parse('$baseUrl/reportes'),
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Safe360Map(reportes: _reportes),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                    decoration: BoxDecoration(
                      color: _colorZona,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _nivelZona,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    'Score: ${_scoreZona.toStringAsFixed(1)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 20,
          bottom: 24,
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SosScreen()),
              );
            },
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}