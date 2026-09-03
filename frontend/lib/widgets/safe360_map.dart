import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../services/location_service.dart';
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
  /// [showRoute] es true. Se usan como fallback si [routePoints] no viene.
  final double? routeOriginLat;
  final double? routeOriginLon;
  final double? routeDestLat;
  final double? routeDestLon;

  /// Geometría completa de la ruta (el campo `puntos` que ya regresa
  /// POST /rutas/segura — lista de `{lat, lon}` en orden). Si viene, se
  /// dibuja esa polilínea completa en vez de solo una línea recta entre
  /// origen y destino.
  final List<dynamic>? routePoints;

  /// Capa de calor por densidad/gravedad de reportes, además de los pines
  /// individuales. Pensado para la vista general (Home) — el preview
  /// chiquito de "Reportar" o el mapa de "Ruta segura" no la necesitan.
  final bool showHeatmap;

  /// Puntos de interés seguros a lo largo de la ruta (farmacias, tiendas
  /// de conveniencia, gasolineras) — el campo `puntos_interes` que ya
  /// regresa POST /rutas/segura. Cada uno: {tipo, nombre, lat, lon}.
  final List<dynamic>? puntosInteres;

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
    this.routePoints,
    this.showHeatmap = false,
    this.puntosInteres,
  });

  @override
  State<Safe360Map> createState() => _Safe360MapState();
}

class _Safe360MapState extends State<Safe360Map> {
  MapboxMap? _mapboxMap;
  CircleAnnotationManager? _circleManager;
  CircleAnnotationManager? _poiManager;
  PolylineAnnotationManager? _routeManager;
  GeoJsonSource? _heatmapSource;
  static const _heatmapSourceId = 'safe360-reportes-heat-source';
  static const _heatmapLayerId = 'safe360-reportes-heat-layer';

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

  // Zona piloto: Puebla capital, con margen. Todos los datos que tiene la
  // app hoy (125K luminarias, reportes) son de aquí — dejar el mapa
  // navegable a todo México no ayuda mientras no haya datos de otras
  // ciudades. Rango calculado del dataset real de luminarias
  // (lon -98.28 a -98.05, lat 18.85 a 19.17) + margen.
  // Para volver a todo México: SW(-118,14) / NE(-86,33).
  static final _pueblaBounds = CoordinateBounds(
    southwest: Point(coordinates: Position(-98.35, 18.80)),
    northeast: Point(coordinates: Position(-98.00, 19.22)),
    infiniteBounds: false,
  );

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    debugPrint('[Safe360Map] _onMapCreated arrancó');
    _mapboxMap = mapboxMap;

    try {
      await mapboxMap.setBounds(
        CameraBoundsOptions(bounds: _pueblaBounds, minZoom: 10.0),
      );
    } catch (e) {
      debugPrint('[Safe360Map] error en setBounds: $e');
    }

    // Cada paso va en su propio try/catch: antes, si pintar reportes, el
    // heatmap o la ruta tronaban, la excepción salía de todo el método y
    // _centrarEnUsuario() (al final) nunca se llegaba a ejecutar — el mapa
    // se quedaba pegado en el centro por defecto de Puebla y parecía que
    // "no mostraba la ubicación real" en Home/Reportar/Ruta segura por
    // igual, aunque el permiso y el GPS sí estuvieran bien.
    if (widget.reportes.isNotEmpty) {
      try {
        _circleManager =
            await mapboxMap.annotations.createCircleAnnotationManager();
        await _pintarReportes();
      } catch (e) {
        debugPrint('[Safe360Map] error pintando reportes: $e');
      }
    }

    if (widget.showHeatmap && widget.reportes.isNotEmpty) {
      try {
        // _actualizarHeatmap (no _agregarHeatmap directo) porque puede que
        // didUpdateWidget ya haya alcanzado a agregar la fuente primero —
        // HomeScreen actualiza `reportes` casi al mismo tiempo que el mapa
        // termina de crearse, y _agregarHeatmap sin este chequeo tronaba con
        // "Source already exists" cuando las dos rutas corrían las dos.
        await _actualizarHeatmap();
      } catch (e) {
        debugPrint('[Safe360Map] error en heatmap: $e');
      }
    }

    if (widget.showRoute) {
      try {
        _routeManager =
            await mapboxMap.annotations.createPolylineAnnotationManager();
        await _dibujarRuta();
      } catch (e) {
        debugPrint('[Safe360Map] error dibujando ruta: $e');
      }
    }

    if (widget.puntosInteres != null && widget.puntosInteres!.isNotEmpty) {
      try {
        _poiManager = await mapboxMap.annotations.createCircleAnnotationManager();
        await _pintarPuntosInteres();
      } catch (e) {
        debugPrint('[Safe360Map] error pintando puntos de interés: $e');
      }
    }

    // Solo perseguimos el GPS del usuario cuando la pantalla no pidió un
    // centro explícito (Home sí quiere seguir al usuario; el preview de
    // "Reportar" o el mapa de "Ruta segura" quieren quedarse fijos).
    if (widget.centerLat == null && widget.centerLon == null) {
      try {
        await _centrarEnUsuario();
      } catch (e) {
        debugPrint('[Safe360Map] error centrando en usuario: $e');
      }
    }
  }

  /// `_onMapCreated` solo corre una vez, así que si `reportes` llega vacío
  /// en el primer build (típico: la pantalla pide los reportes por HTTP en
  /// `initState` y aún no responden) y luego llega con datos, el mapa se
  /// quedaba sin pintar nada. Esto repinta los círculos cuando la lista
  /// cambia después de que el mapa ya está creado.
  @override
  void didUpdateWidget(covariant Safe360Map oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reportes, widget.reportes)) {
      _actualizarReportes();
      if (widget.showHeatmap) _actualizarHeatmap();
    }
    if (widget.showRoute &&
        (!oldWidget.showRoute ||
            oldWidget.routeOriginLat != widget.routeOriginLat ||
            oldWidget.routeOriginLon != widget.routeOriginLon ||
            oldWidget.routeDestLat != widget.routeDestLat ||
            oldWidget.routeDestLon != widget.routeDestLon ||
            !identical(oldWidget.routePoints, widget.routePoints))) {
      _actualizarRuta();
    }
    if (!identical(oldWidget.puntosInteres, widget.puntosInteres) &&
        widget.puntosInteres != null &&
        widget.puntosInteres!.isNotEmpty) {
      _actualizarPuntosInteres();
    }
    // La cámara inicial (`_initialCamera`) solo se calcula una vez al crear
    // el State. Si `centerLat`/`centerLon` llegan después (típico: la
    // pantalla pide el GPS real de forma async y al inicio solo tiene un
    // valor de respaldo), hay que recentrar el mapa a mano.
    if (widget.centerLat != null &&
        widget.centerLon != null &&
        (oldWidget.centerLat != widget.centerLat ||
            oldWidget.centerLon != widget.centerLon)) {
      _recentrar(widget.centerLat!, widget.centerLon!);
    }
  }

  Future<void> _recentrar(double lat, double lon) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    await mapboxMap.flyTo(
      CameraOptions(center: Point(coordinates: Position(lon, lat))),
      MapAnimationOptions(duration: 800),
    );
  }

  Future<void> _actualizarRuta() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    _routeManager ??= await mapboxMap.annotations.createPolylineAnnotationManager();
    await _routeManager!.deleteAll();
    await _dibujarRuta();
  }

  Future<void> _actualizarPuntosInteres() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    _poiManager ??= await mapboxMap.annotations.createCircleAnnotationManager();
    await _poiManager!.deleteAll();
    await _pintarPuntosInteres();
  }

  Future<void> _actualizarReportes() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    if (widget.reportes.isEmpty) {
      await _circleManager?.deleteAll();
      return;
    }

    _circleManager ??= await mapboxMap.annotations.createCircleAnnotationManager();
    await _circleManager!.deleteAll();
    await _pintarReportes();
  }

  /// Qué tanto pesa cada categoría en la intensidad del heatmap — mismo
  /// criterio de gravedad que ya usa `_colorCategoria` para los pines.
  double _pesoCategoria(String categoria) {
    switch (categoria.toLowerCase()) {
      case 'robo':
      case 'acoso':
        return 1.0;
      case 'poca iluminación':
      case 'accidente vial':
        return 0.6;
      default:
        return 0.4;
    }
  }

  String _reportesAGeoJson() {
    final features = widget.reportes
        .map((r) {
          final lat = double.tryParse('${r['latitud']}');
          final lon = double.tryParse('${r['longitud']}');
          if (lat == null || lon == null) return null;
          return {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [lon, lat],
            },
            'properties': {'peso': _pesoCategoria(r['categoria'] ?? '')},
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
    return jsonEncode({'type': 'FeatureCollection', 'features': features});
  }

  Future<void> _agregarHeatmap(MapboxMap mapboxMap) async {
    _heatmapSource = GeoJsonSource(id: _heatmapSourceId, data: _reportesAGeoJson());
    await mapboxMap.style.addSource(_heatmapSource!);
    await mapboxMap.style.addLayer(
      HeatmapLayer(
        id: _heatmapLayerId,
        sourceId: _heatmapSourceId,
        heatmapWeightExpression: [
          'interpolate', ['linear'], ['get', 'peso'],
          0, 0,
          1, 1,
        ],
        heatmapIntensity: 1.0,
        heatmapRadius: 45.0,
        heatmapOpacity: 0.7,
      ),
    );
  }

  Future<void> _actualizarHeatmap() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    if (widget.reportes.isEmpty) {
      if (_heatmapSource != null) {
        await mapboxMap.style.removeStyleLayer(_heatmapLayerId);
        await mapboxMap.style.removeStyleSource(_heatmapSourceId);
        _heatmapSource = null;
      }
      return;
    }

    if (_heatmapSource == null) {
      await _agregarHeatmap(mapboxMap);
    } else {
      await _heatmapSource!.updateGeoJSON(_reportesAGeoJson());
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

  /// Un color distinto por tipo de punto de interés (farmacia, tienda de
  /// conveniencia, gasolinera) — no hay íconos personalizados cargados
  /// todavía (harían falta assets nuevos + registrarlos en el estilo del
  /// mapa), así que por ahora se distinguen por color y por ser más
  /// chicos que los pines de reportes.
  Color _colorPuntoInteres(String tipo) {
    switch (tipo) {
      case 'farmacia':
        return const Color(0xFF7C4DFF); // morado
      case 'tienda_conveniencia':
        return const Color(0xFFFF9800); // naranja
      case 'gasolinera':
        return const Color(0xFF29B6F6); // celeste
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _pintarPuntosInteres() async {
    final puntos = widget.puntosInteres;
    if (_poiManager == null || puntos == null) return;
    for (final p in puntos) {
      final lat = double.tryParse('${p['lat']}');
      final lon = double.tryParse('${p['lon']}');
      if (lat == null || lon == null) continue;

      await _poiManager!.create(
        CircleAnnotationOptions(
          geometry: Point(coordinates: Position(lon, lat)),
          circleColor: _colorPuntoInteres('${p['tipo']}').value,
          circleRadius: 5.5,
          circleOpacity: 0.95,
          circleStrokeColor: Colors.white.value,
          circleStrokeWidth: 1.5,
        ),
      );
    }
  }

  Future<void> _dibujarRuta() async {
    final puntos = widget.routePoints;

    // `puntos` trae la geometría real de la ruta a pie (Mapbox Directions,
    // ver rutas.controller.js) cuando el backend la pudo calcular. Si no
    // vino (Mapbox no respondió, sin token, etc.), cae a una línea recta
    // de 2 puntos entre origen y destino como último recurso.
    final List<Position> coordenadas;
    if (puntos != null && puntos.isNotEmpty) {
      coordenadas = puntos
          .map((p) => Position(
                (p['lon'] as num).toDouble(),
                (p['lat'] as num).toDouble(),
              ))
          .toList();
    } else {
      final origenLat = widget.routeOriginLat ?? 19.0434;
      final origenLon = widget.routeOriginLon ?? -98.1983;
      final destLat = widget.routeDestLat ?? 19.0432;
      final destLon = widget.routeDestLon ?? -98.1982;
      coordenadas = [
        Position(origenLon, origenLat),
        Position(destLon, destLat),
      ];
    }

    await _routeManager?.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: coordenadas),
        lineColor: AppColors.safe.value,
        lineWidth: 4.0,
      ),
    );
  }

  Future<void> _centrarEnUsuario() async {
    // Usa LocationService en vez de pedir el permiso por su cuenta: así
    // queda protegido contra la carrera de MainNavigation montando las 5
    // pestañas de un jalón (IndexedStack) y varias pidiendo ubicación casi
    // al mismo tiempo — antes esto tronaba con
    // PlatformException("A request for permissions is already running")
    // sin capturar, y el mapa se quedaba pegado en el centro por defecto.
    final resultado = await LocationService.obtenerUbicacionActual();
    debugPrint('[Safe360Map] resultado ubicación: exito=${resultado.exito} '
        'error=${resultado.error} pos=${resultado.posicion}');
    if (!resultado.exito) return;

    // Confirmado en vivo: `updateSettings` (activar el puntito azul) puede
    // fallar con un error de canal nativo de Mapbox ("channel-error") sin
    // que tenga nada que ver con el GPS — y como antes iba ANTES de
    // `flyTo`, si tronaba, la cámara nunca llegaba a moverse aunque la
    // ubicación real sí se hubiera conseguido bien. Separado en su propio
    // try/catch para que un fallo puramente cosmético (el puntito) nunca
    // bloquee lo que de verdad importa: centrar el mapa en tu posición.
    try {
      await _mapboxMap?.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          // El puntito se mueve por sí solo cuando el GPS tiene mala señal
          // (interiores, entre edificios) — es ruido real del GPS, no un
          // bug del mapa. El círculo de precisión hace visible por qué:
          // entre más grande el círculo, menos exacta la posición, así que
          // el "rebote" del punto tiene sentido en vez de verse como un
          // error random.
          showAccuracyRing: true,
        ),
      );
    } catch (e) {
      debugPrint('[Safe360Map] error activando el puntito de ubicación (no crítico): $e');
    }

    final posicion = resultado.posicion!;
    debugPrint('[Safe360Map] centrando en lat=${posicion.latitude} lon=${posicion.longitude}');
    await _mapboxMap?.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(posicion.longitude, posicion.latitude)),
        zoom: 15,
      ),
      MapAnimationOptions(duration: 1200),
    );
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
