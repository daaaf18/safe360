import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _category = 'Robo';
  final _descController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  final _categories = const [
    ('Robo', Icons.warning_amber_rounded, AppColors.danger),
    ('Acoso', Icons.report_problem_outlined, AppColors.danger),
    ('Poca iluminación', Icons.lightbulb_outline, AppColors.warning),
    ('Accidente vial', Icons.car_crash_outlined, Colors.purpleAccent),
    ('Otro', Icons.more_horiz, AppColors.textSecondary),
  ];

  // Coordenadas de prueba — centro de Puebla
  // Cuando se integre geolocator, estas serán dinámicas
  final double _latitud = 19.0414;
  final double _longitud = -98.2063;

  Future<void> _enviarReporte() async {
    if (_descController.text.trim().isEmpty) {
      setState(() => _error = 'Agrega una descripción al reporte');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() {
          _loading = false;
          _error = 'Debes iniciar sesión para reportar';
        });
        return;
      }

      final response = await http.post(
        Uri.parse('http://localhost:3000/reportes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'categoria': _category,
          'descripcion': _descController.text.trim(),
          'latitud': _latitud,
          'longitud': _longitud,
        }),
      );

      setState(() => _loading = false);

      if (response.statusCode == 201) {
        setState(() {
          _success = '¡Reporte enviado correctamente!';
          _descController.clear();
          _category = 'Robo';
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() => _error = data['error'] ?? 'Error al enviar el reporte');
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('Reportar incidente'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Center(
            child: Text('Tu reporte nos ayuda a mantener la comunidad segura',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          const SizedBox(height: 20),
          const Text('1. Categoría del incidente',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: _categories.map((c) {
              final selected = _category == c.$1;
              return GestureDetector(
                onTap: () => setState(() => _category = c.$1),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? c.$3.withOpacity(0.12) : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: selected ? c.$3 : Colors.transparent, width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(c.$2, color: c.$3, size: 22),
                      const SizedBox(height: 6),
                      Text(c.$1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),
          const Text('2. Describe lo que pasó',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _descController,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Describe brevemente lo que pasó, cuándo ocurrió, si hay involucrados, etc.',
              counterStyle: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 18),
          const Text('3. Agrega evidencia (opcional)',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Adjuntar foto o video'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.surfaceLight),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: const [
            Icon(Icons.lock_outline, size: 13, color: AppColors.textSecondary),
            SizedBox(width: 6),
            Text('Tu identidad se mantendrá anónima',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ]),
          const SizedBox(height: 22),
          const Text('4. Ubicación del incidente',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 150,
              color: const Color(0xFF1A2A2E),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.location_on, color: AppColors.danger.withOpacity(0.9), size: 30),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Text(
                      'Vista previa de ubicación',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            Text(
              _success!,
              style: const TextStyle(color: AppColors.safe, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 26),
          ElevatedButton(
            onPressed: _loading ? null : _enviarReporte,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Enviar reporte'),
          ),
        ],
      ),
    );
  }
}