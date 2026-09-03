import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'permission_queue_service.dart';

/// Por qué no se pudo obtener la ubicación, para poder mostrar un mensaje
/// que de verdad diga qué pasó (antes todo se reportaba como "permiso
/// denegado o GPS apagado" sin importar la causa real, incluyendo cuando
/// el permiso SÍ estaba dado pero el GPS tardó más del timeout en
/// conseguir señal — muy común probando en interiores).
enum LocationFailure {
  permisoDenegado,
  permisoDenegadoPermanente,
  gpsApagado,
  timeout,
  desconocido,
}

class LocationResult {
  final geo.Position? posicion;
  final LocationFailure? error;
  const LocationResult.ok(geo.Position this.posicion) : error = null;
  const LocationResult.fallo(LocationFailure this.error) : posicion = null;

  bool get exito => posicion != null;

  String get mensajeError => switch (error) {
        LocationFailure.permisoDenegado =>
          'Necesitamos permiso de ubicación. Vuelve a intentar y acepta el permiso.',
        LocationFailure.permisoDenegadoPermanente =>
          'El permiso de ubicación está bloqueado. Actívalo en Ajustes > Apps > Safe360 > Permisos.',
        LocationFailure.gpsApagado => 'Activa el GPS de tu celular e intenta de nuevo.',
        LocationFailure.timeout =>
          'No se pudo conseguir señal GPS a tiempo (¿estás en interiores?). Intenta de nuevo al aire libre.',
        _ => 'No se pudo obtener tu ubicación.',
      };
}

/// Ubicación real del dispositivo, con permiso y manejo de errores
/// centralizados para no repetir la misma lógica en cada pantalla que la
/// necesita (Reportar, SOS, Ruta segura, y el propio Safe360Map).
class LocationService {
  static Future<LocationResult> obtenerUbicacionActual() async {
    PermissionStatus status;
    try {
      // PermissionQueueService (no Permission.request() directo): el
      // cupo de "una solicitud de permiso a la vez" es global en
      // permission_handler, compartido entre TODOS los tipos de permiso
      // (ubicación, micrófono, etc.), no solo entre solicitudes de
      // ubicación repetidas.
      status = await PermissionQueueService.solicitar(Permission.locationWhenInUse);
    } catch (e) {
      debugPrint('[LocationService] error pidiendo permiso: $e');
      return const LocationResult.fallo(LocationFailure.desconocido);
    }
    debugPrint('[LocationService] status permiso: $status');

    if (status.isPermanentlyDenied || status.isRestricted) {
      return const LocationResult.fallo(LocationFailure.permisoDenegadoPermanente);
    }
    if (!status.isGranted && !status.isLimited) {
      return const LocationResult.fallo(LocationFailure.permisoDenegado);
    }

    final gpsEncendido = await geo.Geolocator.isLocationServiceEnabled();
    debugPrint('[LocationService] GPS encendido: $gpsEncendido');
    if (!gpsEncendido) {
      return const LocationResult.fallo(LocationFailure.gpsApagado);
    }

    try {
      // `medium` en vez de `high`: consigue señal mucho más rápido (`high`
      // espera un fix GPS puro, que en interiores o con mala vista al
      // cielo puede tardar minutos o nunca llegar dentro del timeout).
      final posicion = await geo.Geolocator.getCurrentPosition(
        locationSettings:
            const geo.LocationSettings(accuracy: geo.LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 15));
      debugPrint('[LocationService] posición obtenida: $posicion');
      return LocationResult.ok(posicion);
    } on TimeoutException {
      debugPrint('[LocationService] timeout esperando GPS');
      return const LocationResult.fallo(LocationFailure.timeout);
    } catch (e) {
      debugPrint('[LocationService] error obteniendo posición: $e');
      return const LocationResult.fallo(LocationFailure.desconocido);
    }
  }
}
