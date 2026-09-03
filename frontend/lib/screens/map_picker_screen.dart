import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../theme.dart';

/// Selector de ubicación "marca en el mapa" estilo DiDi/Uber: para cuando
/// el destino/origen que buscas no aparece en las sugerencias de
/// geocoding. El pin queda fijo al centro de la pantalla y es el mapa el
/// que se mueve por debajo — así siempre sabes exactamente qué punto vas
/// a confirmar (arrastrar un marcador suelto es menos preciso).
class MapPickerScreen extends StatefulWidget {
  final String titulo;
  final double? centerLatInicial;
  final double? centerLonInicial;

  const MapPickerScreen({
    super.key,
    this.titulo = 'Marca la ubicación',
    this.centerLatInicial,
    this.centerLonInicial,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  MapboxMap? _mapboxMap;
  double? _lat;
  double? _lon;
  String? _direccion;
  bool _cargandoDireccion = false;
  bool _centrandoEnUsuario = false;
  Timer? _debounceDireccion;

  // Misma zona piloto que el resto de la app (safe360_map.dart /
  // geocoding_service.dart) — no tiene caso dejar marcar puntos fuera de
  // donde hay datos reales.
  static const double _defaultLat = 19.0414;
  static const double _defaultLon = -98.2063;
  static final _pueblaBounds = CoordinateBounds(
    southwest: Point(coordinates: Position(-98.35, 18.80)),
    northeast: Point(coordinates: Position(-98.00, 19.22)),
    infiniteBounds: false,
  );

  late final CameraOptions _camaraInicial = CameraOptions(
    center: Point(
      coordinates: Position(
        widget.centerLonInicial ?? _defaultLon,
        widget.centerLatInicial ?? _defaultLat,
      ),
    ),
    zoom: 15,
  );

  @override
  void dispose() {
    _debounceDireccion?.cancel();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    try {
      await mapboxMap.setBounds(
        CameraBoundsOptions(bounds: _pueblaBounds, minZoom: 10.0),
      );
    } catch (_) {}
    await _actualizarCentro();

    // Si no nos dieron un punto inicial, arrancamos centrados en el GPS
    // real del usuario en vez de en el centro fijo de Puebla — mismo
    // criterio que el resto del mapa.
    if (widget.centerLatInicial == null && widget.centerLonInicial == null) {
      _irAUbicacionActual(mostrarError: false);
    }
  }

  Future<void> _onMapIdle(MapIdleEventData _) => _actualizarCentro();

  Future<void> _actualizarCentro() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    try {
      final estado = await mapboxMap.getCameraState();
      final lat = estado.center.coordinates.lat.toDouble();
      final lon = estado.center.coordinates.lng.toDouble();
      if (!mounted) return;
      setState(() {
        _lat = lat;
        _lon = lon;
        _direccion = null;
      });
      _buscarDireccion(lat, lon);
    } catch (_) {}
  }

  void _buscarDireccion(double lat, double lon) {
    _debounceDireccion?.cancel();
    _debounceDireccion = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _cargandoDireccion = true);
      final direccion = await GeocodingService.direccionDesde(lat, lon);
      if (!mounted) return;
      // Puede que ya te hayas movido a otro punto mientras esto respondía
      // — no pisar la dirección de un punto distinto al actual.
      if (_lat != lat || _lon != lon) return;
      setState(() {
        _direccion = direccion;
        _cargandoDireccion = false;
      });
    });
  }

  Future<void> _irAUbicacionActual({bool mostrarError = true}) async {
    setState(() => _centrandoEnUsuario = true);
    final resultado = await LocationService.obtenerUbicacionActual();
    if (!mounted) return;
    setState(() => _centrandoEnUsuario = false);

    if (!resultado.exito) {
      if (mostrarError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resultado.mensajeError)),
        );
      }
      return;
    }

    final posicion = resultado.posicion!;
    await _mapboxMap?.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(posicion.longitude, posicion.latitude)),
        zoom: 16,
      ),
      MapAnimationOptions(duration: 800),
    );
  }

  void _confirmar() {
    if (_lat == null || _lon == null) return;
    Navigator.of(context).pop((
      lat: _lat!,
      lon: _lon!,
      nombre: _direccion ?? 'Punto marcado en el mapa',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.titulo)),
      body: Stack(
        children: [
          MapWidget(
            cameraOptions: _camaraInicial,
            styleUri: MapboxStyles.DARK,
            onMapCreated: _onMapCreated,
            onMapIdleListener: _onMapIdle,
          ),
          // Pin fijo al centro de la pantalla — el mapa se mueve por
          // debajo, el pin no.
          const IgnorePointer(
            child: Center(
              child: Padding(
                // Compensa que el pin apunta desde su punta, no su centro.
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(Icons.location_on, size: 44, color: AppColors.danger),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'ubicacion_actual',
              backgroundColor: AppColors.surface,
              onPressed: _centrandoEnUsuario ? null : () => _irAUbicacionActual(),
              child: _centrandoEnUsuario
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.safe),
                    )
                  : const Icon(Icons.my_location, color: AppColors.safe),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.place, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _cargandoDireccion
                              ? 'Buscando dirección...'
                              : (_direccion ?? 'Mueve el mapa para ubicar el punto'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _lat == null ? null : _confirmar,
                    child: const Text('Confirmar esta ubicación'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
