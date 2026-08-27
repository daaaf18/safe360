import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../theme.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  // baseUrl centralizado en config.dart

  bool _activated = false;
  bool _loading = false;
  String? _mensaje;
  List<dynamic> _contactos = [];

  // Coordenadas de prueba — centro de Puebla
  // Se reemplazarán con geolocator cuando se integre
  final double _latitud = 19.0414;
  final double _longitud = -98.2063;

  @override
  void initState() {
    super.initState();
    _cargarContactos();
  }

  Future<void> _cargarContactos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final usuarioStr = prefs.getString('usuario');

      if (token == null || usuarioStr == null) return;

      final usuario = jsonDecode(usuarioStr);
      final userId = usuario['id'];

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/users/$userId/contactos'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        setState(() => _contactos = jsonDecode(response.body));
      }
    } catch (e) {
      // Error silencioso
    }
  }

  Future<void> _activarSOS() async {
    setState(() { _loading = true; _mensaje = null; });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() {
          _loading = false;
          _mensaje = 'Debes iniciar sesión para usar el SOS';
        });
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/sos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitud': _latitud,
          'longitud': _longitud,
        }),
      );

      setState(() => _loading = false);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _activated = true;
          _mensaje = data['message'];
        });
      } else {
        setState(() => _mensaje = data['error'] ?? 'Error al activar SOS');
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _mensaje = 'Error de conexión con el servidor';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergencia')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            GestureDetector(
              onLongPress: _loading ? null : _activarSOS,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _activated ? AppColors.danger : AppColors.surface,
                  border: Border.all(color: AppColors.danger, width: 3),
                ),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator(color: AppColors.danger)
                      : Text(
                          _activated
                              ? 'ALERTA\nACTIVA'
                              : 'Mantén\npresionado\npara activar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _activated
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_mensaje != null)
              Text(
                _mensaje!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _activated ? AppColors.safe : AppColors.danger,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (_activated)
              Column(
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'Compartiendo tu ubicación en tiempo real',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() {
                      _activated = false;
                      _mensaje = null;
                    }),
                    child: const Text('Cancelar alerta'),
                  ),
                ],
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Al activar, se notificará tu ubicación por WhatsApp a tus contactos de confianza',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            const SizedBox(height: 28),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Se notificará a:',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            _contactos.isEmpty
                ? const Text(
                    'No tienes contactos de confianza configurados.\nAgrégalos en tu perfil.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                : Column(
                    children: _contactos
                        .map((c) => Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(
                                  c['nombre'] ?? '',
                                  style: const TextStyle(
                                      color: AppColors.textPrimary),
                                ),
                                subtitle: Text(
                                  c['telefono'] ?? '',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                                trailing: const Icon(Icons.chat, color: AppColors.safe, size: 20),
                          ),
                        ))
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }
}