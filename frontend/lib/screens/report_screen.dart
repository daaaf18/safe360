import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../theme.dart';
import '../widgets/map_placeholder.dart';

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
    ('Robo', Icons.warning_amber_outlined),
    ('Acoso', Icons.report_problem_outlined),
    ('Poca iluminación', Icons.lightbulb_outline),
    ('Accidente vial', Icons.car_crash_outlined),
    ('Otro', Icons.more_horiz),
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

    setState(() { _loading = true; _error = null; _success = null; });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() { _loading = false; _error = 'Debes iniciar sesión para reportar'; });
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/reportes'),
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
      appBar: AppBar(title: const Text('Reportar incidente')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Categoría', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _category,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                style: const TextStyle(color: AppColors.textPrimary),
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c.$1,
                          child: Row(children: [
                            Icon(c.$2, size: 18, color: AppColors.warning),
                            const SizedBox(width: 10),
                            Text(c.$1),
                          ]),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Descripción', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            maxLines: 4,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Describe brevemente lo que pasó...',
            ),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 20),
          const Text('Ubicación detectada', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: const SizedBox(height: 140, child: MapPlaceholder()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            Text(
              _success!,
              style: const TextStyle(color: Colors.green, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 28),
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