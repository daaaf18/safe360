import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';
import '../config.dart';
import '../widgets/safe360_map.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import 'mapa_completo_screen.dart';
import 'map_picker_screen.dart';

class SafeRouteScreen extends StatefulWidget {
  // Para reactivar una ruta frecuente desde Perfil con un toque, sin
  // tener que volver a escribir origen/destino — ver
  // _SafeRouteScreenState.initState().
  final double? initialOrigenLat;
  final double? initialOrigenLon;
  final double? initialDestinoLat;
  final double? initialDestinoLon;

  const SafeRouteScreen({
    super.key,
    this.initialOrigenLat,
    this.initialOrigenLon,
    this.initialDestinoLat,
    this.initialDestinoLon,
  });

  @override
  State<SafeRouteScreen> createState() => _SafeRouteScreenState();
}

class _SafeRouteScreenState extends State<SafeRouteScreen> {
  String get baseUrl => ApiConfig.baseUrl;

  final _origenCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  bool _loading = false;
  bool _cargandoAlternativa = false;
  String? _error;
  Map<String, dynamic>? _ruta;
  bool _modoOffline = false;

  // Coordenadas ya geocodificadas de lo que el usuario escribió (o de su
  // GPS, si dejó "Origen" vacío). Null hasta que se calcule una ruta.
  double? _origenLat;
  double? _origenLon;
  double? _destinoLat;
  double? _destinoLon;

  // ── Autocompletado de direcciones (estilo DiDi) ──────────────────────
  List<({String nombre, double lat, double lon})> _sugerenciasOrigen = [];
  List<({String nombre, double lat, double lon})> _sugerenciasDestino = [];
  Timer? _debounceOrigen;
  Timer? _debounceDestino;

  // Coordenadas ya resueltas cuando el usuario toca una sugerencia — así
  // _calcularRuta no vuelve a pegarle a la API de geocoding si no hace
  // falta. Se invalidan (vuelven a null) en cuanto se edita el texto.
  ({double lat, double lon})? _origenElegido;
  ({double lat, double lon})? _destinoElegido;

  @override
  void initState() {
    super.initState();
    final destLat = widget.initialDestinoLat;
    final destLon = widget.initialDestinoLon;
    if (destLat != null && destLon != null) {
      _reactivarRutaGuardada(
        origenLat: widget.initialOrigenLat,
        origenLon: widget.initialOrigenLon,
        destinoLat: destLat,
        destinoLon: destLon,
      );
    }
  }

  /// Rellena los campos con una ruta que ya se había calculado antes (ver
  /// "Rutas frecuentes" en Perfil) y dispara el cálculo — evita que el
  /// usuario tenga que volver a escribir/elegir origen y destino a mano.
  /// El geocoding inverso es solo para que los campos de texto se vean
  /// bien; si falla, cae a una etiqueta genérica y de todos modos calcula
  /// la ruta (las coordenadas ya están resueltas, no dependen de esto).
  Future<void> _reactivarRutaGuardada({
    double? origenLat,
    double? origenLon,
    required double destinoLat,
    required double destinoLon,
  }) async {
    if (origenLat != null && origenLon != null) {
      final nombre = await GeocodingService.direccionDesde(origenLat, origenLon);
      _origenCtrl.text = nombre ?? 'Origen guardado';
      _origenElegido = (lat: origenLat, lon: origenLon);
    }

    final nombreDestino = await GeocodingService.direccionDesde(destinoLat, destinoLon);
    _destinoCtrl.text = nombreDestino ?? 'Destino guardado';
    _destinoElegido = (lat: destinoLat, lon: destinoLon);

    if (mounted) await _calcularRuta();
  }

  @override
  void dispose() {
    _debounceOrigen?.cancel();
    _debounceDestino?.cancel();
    _origenCtrl.dispose();
    _destinoCtrl.dispose();
    super.dispose();
  }

  void _onOrigenChanged(String texto) {
    _origenElegido = null;
    _debounceOrigen?.cancel();
    _debounceOrigen = Timer(const Duration(milliseconds: 350), () async {
      final resultados = await GeocodingService.sugerencias(texto);
      if (mounted) setState(() => _sugerenciasOrigen = resultados);
    });
  }

  void _onDestinoChanged(String texto) {
    _destinoElegido = null;
    _debounceDestino?.cancel();
    _debounceDestino = Timer(const Duration(milliseconds: 350), () async {
      final resultados = await GeocodingService.sugerencias(texto);
      if (mounted) setState(() => _sugerenciasDestino = resultados);
    });
  }

  void _elegirOrigen(({String nombre, double lat, double lon}) s) {
    _origenCtrl.text = s.nombre;
    _origenElegido = (lat: s.lat, lon: s.lon);
    setState(() => _sugerenciasOrigen = []);
    FocusScope.of(context).unfocus();
  }

  void _elegirDestino(({String nombre, double lat, double lon}) s) {
    _destinoCtrl.text = s.nombre;
    _destinoElegido = (lat: s.lat, lon: s.lon);
    setState(() => _sugerenciasDestino = []);
    FocusScope.of(context).unfocus();
  }

  /// Abre el selector "marca en el mapa" (estilo DiDi) — para cuando el
  /// lugar que buscas no sale en las sugerencias de geocoding. Arranca
  /// centrado en lo que ya se haya elegido/escrito para ese campo, si hay
  /// algo, para no perder el contexto de dónde andabas buscando.
  Future<void> _elegirEnMapa({required bool esOrigen}) async {
    FocusScope.of(context).unfocus();
    final previo = esOrigen ? _origenElegido : _destinoElegido;
    final resultado = await Navigator.of(context).push<({double lat, double lon, String nombre})>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          titulo: esOrigen ? 'Marca el origen' : 'Marca el destino',
          centerLatInicial: previo?.lat,
          centerLonInicial: previo?.lon,
        ),
      ),
    );
    if (resultado == null) return;

    setState(() {
      if (esOrigen) {
        _origenCtrl.text = resultado.nombre;
        _origenElegido = (lat: resultado.lat, lon: resultado.lon);
        _sugerenciasOrigen = [];
      } else {
        _destinoCtrl.text = resultado.nombre;
        _destinoElegido = (lat: resultado.lat, lon: resultado.lon);
        _sugerenciasDestino = [];
      }
    });
  }

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
    if (_destinoCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa un destino');
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

      // Origen vacío = usar el GPS actual. Si tocaste una sugerencia ya
      // tenemos las coordenadas (nos ahorramos otro viaje a la API); si
      // solo escribiste texto sin elegir sugerencia, lo geocodificamos.
      final origenTexto = _origenCtrl.text.trim();
      double? origenLat;
      double? origenLon;
      if (origenTexto.isEmpty) {
        final resultadoUbicacion = await LocationService.obtenerUbicacionActual();
        if (resultadoUbicacion.exito) {
          origenLat = resultadoUbicacion.posicion!.latitude;
          origenLon = resultadoUbicacion.posicion!.longitude;
        } else {
          setState(() {
            _loading = false;
            _error = resultadoUbicacion.mensajeError;
          });
          return;
        }
      } else if (_origenElegido != null) {
        origenLat = _origenElegido!.lat;
        origenLon = _origenElegido!.lon;
      } else {
        final resultado = await GeocodingService.buscar(origenTexto);
        if (resultado != null) {
          origenLat = resultado.lat;
          origenLon = resultado.lon;
        } else {
          setState(() {
            _loading = false;
            _error = 'No encontramos "$origenTexto". Intenta ser más específico.';
          });
          return;
        }
      }

      final destinoTexto = _destinoCtrl.text.trim();
      double? destinoLat;
      double? destinoLon;
      if (_destinoElegido != null) {
        destinoLat = _destinoElegido!.lat;
        destinoLon = _destinoElegido!.lon;
      } else {
        final destinoResuelto = await GeocodingService.buscar(destinoTexto);
        if (destinoResuelto == null) {
          setState(() {
            _loading = false;
            _error = 'No encontramos "$destinoTexto". Intenta ser más específico.';
          });
          return;
        }
        destinoLat = destinoResuelto.lat;
        destinoLon = destinoResuelto.lon;
      }

      setState(() {
        _origenLat = origenLat;
        _origenLon = origenLon;
        _destinoLat = destinoLat;
        _destinoLon = destinoLon;
      });

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

  /// Vuelve a pedir la misma ruta pero con `usar_alternativa: true` — ya
  /// tenemos origen/destino resueltos de _calcularRuta, así que no hace
  /// falta geocodificar de nuevo.
  Future<void> _verRutaAlternativa() async {
    if (_origenLat == null || _destinoLat == null || _cargandoAlternativa) return;

    setState(() {
      _cargandoAlternativa = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        setState(() {
          _cargandoAlternativa = false;
          _error = 'Debes iniciar sesión';
        });
        return;
      }

      final response = await http
          .post(
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
              'usar_alternativa': true,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final rutaData = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _cargandoAlternativa = false;
          _ruta = rutaData;
          _modoOffline = false;
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _cargandoAlternativa = false;
          _error = data['error'] ?? 'No se pudo calcular la ruta alternativa';
        });
      }
    } catch (e) {
      setState(() {
        _cargandoAlternativa = false;
        _error = 'Error de conexión buscando la ruta alternativa';
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
          _campoDireccion(
            controller: _origenCtrl,
            hint: 'Origen (vacío = tu ubicación actual)',
            icono: Icons.trip_origin,
            colorIcono: AppColors.safe,
            onChanged: _onOrigenChanged,
            sugerencias: _sugerenciasOrigen,
            onElegir: _elegirOrigen,
            onElegirEnMapa: () => _elegirEnMapa(esOrigen: true),
          ),
          const SizedBox(height: 10),
          _campoDireccion(
            controller: _destinoCtrl,
            hint: 'Destino',
            icono: Icons.location_on_outlined,
            colorIcono: AppColors.danger,
            onChanged: _onDestinoChanged,
            sugerencias: _sugerenciasDestino,
            onElegir: _elegirDestino,
            onElegirEnMapa: () => _elegirEnMapa(esOrigen: false),
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
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MapaCompletoScreen(
                titulo: 'Ruta segura',
                showRoute: _ruta != null,
                routeOriginLat: _origenLat,
                routeOriginLon: _origenLon,
                routeDestLat: _destinoLat,
                routeDestLon: _destinoLon,
                routePoints: _ruta?['puntos'] as List<dynamic>?,
                puntosInteres: _ruta?['puntos_interes'] as List<dynamic>?,
                // Sin esto el mapa completo abre centrado en el GPS actual
                // del usuario en vez de la ruta que se acaba de calcular.
                centerLat: _origenLat,
                centerLon: _origenLon,
              ),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 230,
                child: Stack(
                  children: [
                  // Solo se dibuja la línea recta origen-destino cuando ya
                  // hay una ruta calculada (ver TODO en safe360_map.dart:
                  // el backend aún no regresa geometría de ruta real).
                  Safe360Map(
                    showRoute: _ruta != null,
                    routeOriginLat: _origenLat,
                    routeOriginLon: _origenLon,
                    routeDestLat: _destinoLat,
                    routeDestLon: _destinoLon,
                    routePoints: _ruta?['puntos'] as List<dynamic>?,
                    puntosInteres: _ruta?['puntos_interes'] as List<dynamic>?,
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fullscreen, size: 14, color: AppColors.textPrimary),
                          SizedBox(width: 4),
                          Text('Ver completo',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
            // Score temporal: riesgo de este tramo según la hora actual —
            // K-Means si hay suficiente historial, fórmula fija si no
            // (ver ml.service.js). Solo se muestra si hay algo que decir
            // (el backend manda `mensaje: null` cuando el riesgo ya es bajo).
            if (_ruta?['score_temporal']?['mensaje'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.schedule, size: 16, color: AppColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_ruta!['score_temporal']['mensaje'],
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            if ((_ruta?['puntos_interes'] as List<dynamic>?)?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Puntos seguros en tu camino '
                      '(${(_ruta!['puntos_interes'] as List).length})',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: (_ruta!['puntos_interes'] as List<dynamic>).map((p) {
                        final tipo = '${p['tipo']}';
                        final icono = tipo == 'farmacia'
                            ? Icons.local_pharmacy
                            : tipo == 'gasolinera'
                                ? Icons.local_gas_station
                                : Icons.storefront;
                        return Chip(
                          avatar: Icon(icono, size: 14, color: AppColors.textPrimary),
                          label: Text('${p['nombre']}', style: const TextStyle(fontSize: 11)),
                          backgroundColor: AppColors.surfaceLight,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: (_ruta?['hay_alternativa'] == true && !_cargandoAlternativa)
                  ? _verRutaAlternativa
                  : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.surfaceLight),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _cargandoAlternativa
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_ruta?['hay_alternativa'] == true
                      ? 'Ver ruta alternativa'
                      : 'No hay ruta alternativa para este trayecto'),
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

  /// Campo de texto + lista de sugerencias tipo DiDi/Uber que aparece
  /// debajo mientras tecleas (con debounce, ver _onOrigenChanged /
  /// _onDestinoChanged).
  Widget _campoDireccion({
    required TextEditingController controller,
    required String hint,
    required IconData icono,
    required Color colorIcono,
    required ValueChanged<String> onChanged,
    required List<({String nombre, double lat, double lon})> sugerencias,
    required ValueChanged<({String nombre, double lat, double lon})> onElegir,
    required VoidCallback onElegirEnMapa,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icono, color: colorIcono),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onElegirEnMapa,
            icon: const Icon(Icons.map_outlined, size: 16),
            label: const Text('No aparece — marcar en el mapa', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        if (sugerencias.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceLight),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: sugerencias.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.surfaceLight),
              itemBuilder: (_, i) {
                final s = sugerencias[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on_outlined,
                      size: 18, color: AppColors.textSecondary),
                  title: Text(
                    s.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  ),
                  onTap: () => onElegir(s),
                );
              },
            ),
          ),
      ],
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