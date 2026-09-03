import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/safe360_map.dart';

/// Vista de pantalla completa del mapa. Reportar y Ruta segura solo
/// muestran un preview chiquito (150-230px) dentro del formulario; al
/// tocarlo se abre esto para poder verlo grande y moverse con más espacio,
/// con los mismos datos (pin del incidente, o ruta dibujada).
class MapaCompletoScreen extends StatelessWidget {
  final String titulo;
  final bool showRoute;
  final List<dynamic> reportes;
  final double? centerLat;
  final double? centerLon;
  final double? routeOriginLat;
  final double? routeOriginLon;
  final double? routeDestLat;
  final double? routeDestLon;
  final List<dynamic>? routePoints;
  final List<dynamic>? puntosInteres;

  const MapaCompletoScreen({
    super.key,
    this.titulo = 'Mapa',
    this.showRoute = false,
    this.reportes = const [],
    this.centerLat,
    this.centerLon,
    this.routeOriginLat,
    this.routeOriginLon,
    this.routeDestLat,
    this.routeDestLon,
    this.routePoints,
    this.puntosInteres,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(titulo),
        backgroundColor: AppColors.surface,
      ),
      body: Safe360Map(
        showRoute: showRoute,
        reportes: reportes,
        centerLat: centerLat,
        centerLon: centerLon,
        routeOriginLat: routeOriginLat,
        routeOriginLon: routeOriginLon,
        routeDestLat: routeDestLat,
        routeDestLon: routeDestLon,
        routePoints: routePoints,
        puntosInteres: puntosInteres,
      ),
    );
  }
}
