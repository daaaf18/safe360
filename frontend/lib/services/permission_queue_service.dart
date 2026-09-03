import 'dart:async';
import 'package:permission_handler/permission_handler.dart';

/// permission_handler solo deja UNA llamada a `.request()` en vuelo a la
/// vez en TODO el proceso — sin importar de qué permiso se trate. Ya nos
/// pasó dos veces con distintos permisos (ubicación vs. ubicación, y
/// ubicación vs. micrófono) porque MainNavigation monta las 5 pestañas de
/// un jalón (IndexedStack) y varias piden permisos casi al mismo tiempo:
/// la segunda solicitud truena con
/// PlatformException("A request for permissions is already running").
///
/// Cualquier pantalla que pida un permiso debe pasar por aquí (en vez de
/// llamar `Permission.x.request()` directo) para que todas esperen la
/// MISMA solicitud en vez de lanzar la suya y chocar.
class PermissionQueueService {
  // OJO: antes esto guardaba un solo Completer y, si llegaba una segunda
  // solicitud mientras la primera seguía en vuelo, le regresaba el MISMO
  // future — sin importar que fuera un permiso distinto. Ejemplo real: se
  // pedía ubicación al montar Home y, si el usuario tocaba el micrófono de
  // Chaty en ese instante, `solicitar(Permission.microphone)` regresaba el
  // resultado de la solicitud de UBICACIÓN, no la de micrófono — el botón
  // "no hacía nada" (ni pedía permiso ni tronaba, solo resolvía con un
  // status que no correspondía). Ahora se encadena: cada solicitud espera
  // a que la anterior termine y HASTA ENTONCES lanza la suya propia, así
  // siempre se pide el permiso correcto aunque se sigan sin traslapar
  // (que es la restricción real de permission_handler).
  static Future<void> _cola = Future.value();

  static Future<PermissionStatus> solicitar(Permission permiso) {
    final espera = _cola;
    final completer = Completer<PermissionStatus>();

    // `_cola` es Future<void> a propósito: solo nos importa CUÁNDO termina
    // esta solicitud (para que la siguiente en la fila pueda arrancar), no
    // su resultado — así el tipo no se enreda con catchError teniendo que
    // devolver un PermissionStatus.
    _cola = completer.future.then((_) {}, onError: (_) {});

    espera.then((_) async {
      try {
        final status = await permiso.request();
        if (!completer.isCompleted) completer.complete(status);
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });

    return completer.future;
  }
}
