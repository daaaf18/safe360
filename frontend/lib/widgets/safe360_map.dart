import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme.dart';

/// Mapa real de Mapbox.
///
/// Reemplaza a `MapPlaceholder` manteniendo la misma firma (`showRoute`,
/// `reportes`) para que el swap en las pantallas (Home, Reportar, Ruta
/// segura) sea directo, sin tocar el resto de cada pantalla.
class Safe360Map extends StatefulWidget {
  final bool showRoute;
  final List<dynamic> reportes;

  /// Centro inicial del mapa. Si es null, usa el centro de Puebla y además
  /// intenta centrar en la ubicación real del usuario (cuando da el
  /// permiso). Si se especifica, el mapa se queda fijo ahí (por ejemplo,
  /// la mini-preview de "Reportar incidente" que muestra el punto exacto
  /// del incidente).
  final double? centerLat;
  final double? centerLon;

  /// Puntos de origen/destino para dibujar la línea de ruta cuando
  /// [showRoute] es true.
  final double? routeOriginLat;
  final double? routeOriginLon;
  final double? routeDestLat;
  final double? routeDestLon;

  const Safe360Map({
    super.key,
    this.showRoute = false,
    this.reportes = const [],
    this.centerLat,
    this.centerLon,
    this.routeOriginLat,
    this.routeOriginLon,
    this.routeDestLat,
    this.routeDestLon,
  });

  @override
  State<Safe360Map> createState() => _Safe360MapState();
}

class _Safe360MapState extends State<Safe360Map> {
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _circleManager;
  PolylineAnnotationManager? _routeManager;

  // Centro por defecto: Puebla, México (zona piloto del dataset de reportes
  // y luminarias).
  static const double _defaultLat = 19.0414;
  static const double _defaultLon = -98.2063;

  late final CameraOptions _initialCamera = CameraOptions(
    center: Point(
      coordinates: Position(
        widget.centerLon ?? _defaultLon,
        widget.centerLat ?? _defaultLat,
      ),
    ),
    zoom: 14,
  );

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    if (widget.reportes.isNotEmpty) {
      _circleManager =
          await mapboxMap.annotations.createCircleAnnotationManager();
      await _pintarReportes();
    }

    if (widget.showRoute) {
      _routeManager =
          await mapboxMap.annotations.createPolylineAnnotationManager();
      await _dibujarRuta();
    }

    // Solo perseguimos el GPS del usuario cuando la pantalla no pidió un
    // centro explícito (Home sí quiere seguir al usuario; el preview de
    // "Reportar" o el mapa de "Ruta segura" quieren quedarse fijos).
    if (widget.centerLat == null && widget.centerLon == null) {
      await _centrarEnUsuario();
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
        return AppColors.warning;
    }
  }

  Future<void> _pintarReportes() async {
    for (final reporte in widget.reportes) {
      final lat = double.tryParse('${reporte['latitud']}');
      final lon = double.tryParse('${reporte['longitud']}');
      if (lat == null || lon == null) continue;

      await _circleManager?.create(
        CircleAnnotationOptions(
          geometry: Point(coordinates: Position(lon, lat)),
          circleColor: _colorCategoria(reporte['categoria'] ?? '').value,
          circleRadius: reporte['estado'] == 'verificado' ? 10.0 : 7.0,
          circleOpacity: 0.85,
          circleStrokeColor: Colors.white.value,
          circleStrokeWidth: 1.5,
        ),
      );
    }
  }

  // TODO(Jorge): esto dibuja una línea recta entre origen y destino.
  // El endpoint POST /rutas/segura hoy solo devuelve trust_score_promedio,
  // no geometría de ruta real. Cuando el backend la exponga, reemplazar
  // este LineString por esos puntos.
  Future<void> _dibujarRuta() async {
    final origenLat = widget.routeOriginLat ?? 19.0434;
    final origenLon = widget.routeOriginLon ?? -98.1983;
    final destLat = widget.routeDestLat ?? 19.0432;
    final destLon = widget.routeDestLon ?? -98.1982;

    await _routeManager?.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: [
          Position(origenLon, origenLat),
          Position(destLon, destLat),
        ]),
        lineColor: AppColors.safe.value,
        lineWidth: 4.0,
      ),
    );
  }

  Future<void> _centrarEnUsuario() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) return;

    await _mapboxMap?.location.updateSettings(
      LocationComponentSettings(enabled: true, pulsingEnabled: true),
    );

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      await _mapboxMap?.flyTo(
        CameraOptions(
          center: Point(
              coordinates: Position(position.longitude, position.latitude)),
          zoom: 15,
        ),
        MapAnimationOptions(duration: 1200),
      );
    } catch (_) {
      // Sin GPS disponible (emulador sin ubicación simulada, permiso
      // denegado, etc.): el mapa se queda en el centro por defecto.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MapWidget(
      cameraOptions: _initialCamera,
      styleUri: MapboxStyles.DARK,
      onMapCreated: _onMapCreated,
    );
  }
}
