import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../theme.dart';
import '../services/location_service.dart';
import '../services/sms_fallback_service.dart';

/// Cada cuánto se manda una actualización de ubicación a los contactos
/// mientras la alerta sigue activa. Balance entre "de verdad es tiempo
/// real" y no saturarles el WhatsApp con un mensaje por minuto.
const _intervaloTracking = Duration(minutes: 2);

class SosScreen extends StatefulWidget {
  /// Cuando Chaty detecta una emergencia real (palabra clave, o el
  /// auto-SOS de modo transporte tras 30s sin respuesta), no basta con
  /// abrir esta pantalla y esperar a que la persona toque el botón —
  /// puede que no pueda. `autoActivar` hace que se active sola apenas
  /// carga, pasando por el mismo camino de siempre (WhatsApp + SMS +
  /// rastreo cada 2 min), en vez de duplicar esa lógica en otro lado.
  final bool autoActivar;

  const SosScreen({super.key, this.autoActivar = false});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with SingleTickerProviderStateMixin {
  // baseUrl centralizado en config.dart

  bool _activated = false;
  bool _silencioso = false; // modo escolta: mismo tracking, mensaje distinto, sin la pinta de "alerta"
  bool _loading = false;
  String? _mensaje;
  bool _mensajeEsAdvertencia = false;
  List<dynamic> _contactos = [];
  String _nombreUsuario = 'Usuario';

  // Centro de Puebla como último recurso si de plano no se pudo obtener el
  // GPS (permiso denegado, GPS apagado, sin señal). Mejor mandar una
  // ubicación aproximada que no mandar nada en una emergencia.
  double _latitud = 19.0414;
  double _longitud = -98.2063;
  bool _ubicacionEsReal = false;

  Timer? _trackingTimer;
  DateTime? _ultimaActualizacion;

  // Pulso del círculo mientras la alerta está activa — antes se quedaba
  // estático apenas cambiaba de color, y este es justo el momento más
  // importante de toda la app para que se sienta "viva" (como una luz de
  // grabación), no solo un botón que cambió de color y ya.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _pulseScale =
      Tween<double>(begin: 1.0, end: 1.07).animate(
    CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
  );

  @override
  void initState() {
    super.initState();
    _obtenerUbicacion();
    if (widget.autoActivar) {
      // Hace falta la lista de contactos cargada ANTES de activar (el SMS
      // de respaldo la usa apenas se confirma el SOS) — por eso aquí se
      // espera a _cargarContactos() en vez de solo dispararla como abajo.
      _cargarContactos().then((_) {
        if (mounted) _activarSOS();
      });
    } else {
      _cargarContactos();
    }
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _obtenerUbicacion() async {
    final resultado = await LocationService.obtenerUbicacionActual();
    if (!mounted || !resultado.exito) return;
    setState(() {
      _latitud = resultado.posicion!.latitude;
      _longitud = resultado.posicion!.longitude;
      _ubicacionEsReal = true;
    });
  }

  Future<void> _cargarContactos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final usuarioStr = prefs.getString('usuario');

      if (token == null || usuarioStr == null) return;

      final usuario = jsonDecode(usuarioStr);
      final userId = usuario['id'];
      _nombreUsuario = usuario['nombre'] ?? 'Usuario';

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

  Future<void> _activarSOS({bool silencioso = false}) async {
    setState(() {
      _loading = true;
      _mensaje = null;
      _mensajeEsAdvertencia = false;
      _silencioso = silencioso;
    });

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

      // Pedimos una posición fresca justo antes de activar (pudiste haberte
      // movido desde que abriste la pantalla). Si falla, seguimos con la
      // última ubicación que tengamos — en una emergencia es mejor mandar
      // algo aproximado que no mandar nada.
      final resultadoUbicacion = await LocationService.obtenerUbicacionActual();
      if (resultadoUbicacion.exito && mounted) {
        setState(() {
          _latitud = resultadoUbicacion.posicion!.latitude;
          _longitud = resultadoUbicacion.posicion!.longitude;
          _ubicacionEsReal = true;
        });
      }

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/sos'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'latitud': _latitud,
              'longitud': _longitud,
              'silencioso': silencioso,
            }),
          )
          .timeout(const Duration(seconds: 8));

      setState(() => _loading = false);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _activated = true;
          _mensaje = data['message'];
          _mensajeEsAdvertencia = false;
          _ultimaActualizacion = DateTime.now();
        });
        _pulseController.repeat(reverse: true);
        _iniciarTracking();

        // Además del WhatsApp automático que ya mandó el backend, abrimos
        // la app de SMS con el aviso pre-llenado — Android no deja mandar
        // SMS sin que el usuario toque "Enviar" (por diseño), así que esto
        // no es 100% automático, pero deja todo listo con un solo toque.
        // No bloquea ni sobreescribe el mensaje de éxito de arriba si algo
        // sale mal abriendo la app de mensajes.
        final smsAbierto = await _abrirAppSms();
        if (mounted && smsAbierto) {
          setState(() => _mensaje = '${_mensaje ?? ''} También se abrió tu '
              'app de mensajes con el SOS listo por SMS — solo falta que '
              'toques enviar.');
        }
      } else {
        setState(() {
          _mensaje = data['error'] ?? 'Error al activar SOS';
          _mensajeEsAdvertencia = false;
        });
      }
    } catch (e) {
      // Sin internet (o el backend no responde a tiempo): plan B, SMS
      // directo por la red celular en vez del WhatsApp automático.
      setState(() => _loading = false);
      await _activarPorSms();
    }
  }

  /// Abre la app de mensajes con el SOS pre-llenado, sin tocar `_mensaje`/
  /// `_mensajeEsAdvertencia` — quien llama decide qué mostrar según el
  /// contexto (éxito con WhatsApp + SMS, o SMS como único respaldo).
  Future<bool> _abrirAppSms() async {
    if (_contactos.isEmpty) return false;
    return SmsFallbackService.abrirSmsDeEmergencia(
      contactos: _contactos,
      latitud: _latitud,
      longitud: _longitud,
      nombreUsuario: _nombreUsuario,
      ubicacionEsReal: _ubicacionEsReal,
    );
  }

  Future<void> _activarPorSms() async {
    if (_contactos.isEmpty) {
      setState(() {
        _mensaje = 'Sin conexión y no tienes contactos de confianza configurados '
            'para mandar un SMS de emergencia.';
        _mensajeEsAdvertencia = true;
      });
      return;
    }

    final abierto = await _abrirAppSms();

    if (!mounted) return;
    setState(() {
      _mensajeEsAdvertencia = !abierto;
      _mensaje = abierto
          ? 'Sin internet: se abrió tu app de mensajes con el SOS listo. '
              'Revisa y toca enviar para que les llegue por SMS.'
          : 'Sin internet y no se pudo abrir la app de mensajes. '
              'Llama directo al 911 o a tus contactos.';
    });
  }

  void _iniciarTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(_intervaloTracking, (_) => _enviarActualizacionUbicacion());
  }

  void _detenerTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  /// Se llama cada [_intervaloTracking] mientras la alerta sigue activa:
  /// pide GPS fresco y lo manda a /sos/ubicacion, que persiste la posición
  /// y reenvía un WhatsApp corto con el link actualizado a los contactos.
  Future<void> _enviarActualizacionUbicacion() async {
    if (!mounted || !_activated) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    final resultado = await LocationService.obtenerUbicacionActual();
    if (!resultado.exito) return; // seguimos intentando en el siguiente tick

    if (!mounted || !_activated) return;
    setState(() {
      _latitud = resultado.posicion!.latitude;
      _longitud = resultado.posicion!.longitude;
      _ubicacionEsReal = true;
    });

    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/sos/ubicacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'latitud': _latitud, 'longitud': _longitud}),
      );

      if (response.statusCode == 200 && mounted && _activated) {
        setState(() => _ultimaActualizacion = DateTime.now());
      }
    } catch (_) {
      // Sin conexión momentánea: no interrumpimos la alerta, se
      // reintenta solo en el siguiente tick del timer.
    }
  }

  /// Abre el marcador nativo con el 911 ya puesto — Android no deja que
  /// una app marque sola sin que la persona confirme, así que el toque
  /// final siempre es tuyo, pero no tienes que buscar el teclado ni
  /// escribir el número tú misma en medio de una emergencia.
  Future<void> _llamar911() async {
    await launchUrl(Uri(scheme: 'tel', path: '911'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergencia'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _llamar911,
              icon: const Icon(Icons.call, color: AppColors.danger, size: 18),
              label: const Text('911', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            GestureDetector(
              onLongPress: _loading ? null : _activarSOS,
              child: ScaleTransition(
                // Pulso constante mientras la alerta sigue activa — sin
                // esto, el círculo cambiaba de color una vez y ya se
                // quedaba quieto, como si no siguiera pasando nada.
                scale: _activated ? _pulseScale : const AlwaysStoppedAnimation(1.0),
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _activated
                        ? (_silencioso ? AppColors.warning : AppColors.danger)
                        : AppColors.surface,
                    border: Border.all(color: AppColors.danger, width: 3),
                    boxShadow: _activated
                        ? [
                            BoxShadow(
                              color: (_silencioso ? AppColors.warning : AppColors.danger)
                                  .withOpacity(0.5),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: _loading
                        ? const CircularProgressIndicator(color: AppColors.danger)
                        : Text(
                            _activated
                                ? (_silencioso ? 'ESCOLTA\nACTIVA' : 'ALERTA\nACTIVA')
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
            ),
            if (!_activated) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _activarSOS(silencioso: true),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Activar modo escolta silenciosa'),
              ),
            ],
            const SizedBox(height: 20),
            if (_mensaje != null)
              Text(
                _mensaje!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _activated
                      ? AppColors.safe
                      : (_mensajeEsAdvertencia ? AppColors.warning : AppColors.danger),
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (_activated)
              Column(
                children: [
                  const SizedBox(height: 8),
                  Text(
                    _ubicacionEsReal
                        ? 'Compartiendo tu ubicación cada ${_intervaloTracking.inMinutes} min'
                            '${_silencioso ? ' (modo escolta)' : ''}'
                        : 'No se pudo obtener tu GPS real — se mandó una ubicación aproximada',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _ubicacionEsReal
                            ? (_silencioso ? AppColors.warning : AppColors.danger)
                            : AppColors.warning),
                  ),
                  if (_ultimaActualizacion != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Última actualización: '
                      '${_ultimaActualizacion!.hour.toString().padLeft(2, '0')}:'
                      '${_ultimaActualizacion!.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      _detenerTracking();
                      _pulseController.stop();
                      setState(() {
                        _activated = false;
                        _silencioso = false;
                        _mensaje = null;
                        _ultimaActualizacion = null;
                      });
                    },
                    child: Text(_silencioso ? 'Desactivar modo escolta' : 'Cancelar alerta'),
                  ),
                ],
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Al activar, se notificará tu ubicación por WhatsApp a tus contactos de confianza. '
                  'El modo escolta hace lo mismo, discretamente y sin marcar "emergencia".',
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