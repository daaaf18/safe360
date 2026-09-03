/// -----------------------------------------------------------------------
/// URL única del backend — TODAS las pantallas deben importar esta
/// constante en vez de escribir su propia copia de 'http://localhost:3000'
/// o 'http://10.0.2.2:3000'. Antes había 3 versiones distintas regadas
/// en el proyecto (home, sos/contactos/ruta con IPs diferentes), lo cual
/// hace que la app funcione en un dispositivo y falle en otro sin razón
/// aparente.
///
/// Cambia SOLO esta línea según dónde estés probando:
///   - Windows / Edge / Chrome (misma compu que el backend):
///       'http://localhost:3000'
///   - Emulador de Android:
///       'http://10.0.2.2:3000'
///   - Celular físico en la misma red WiFi que tu compu:
///       'http://<IP-de-tu-compu>:3000'   (ej. http://192.168.1.50:3000)
///     Si tu router tiene "aislamiento de clientes"/AP isolation activado,
///     esto NUNCA va a funcionar sin importar la IP — los dispositivos en
///     el WiFi no se pueden ver entre sí aunque compartan red. Se detecta
///     con `ping <IP-del-celular>` desde la PC: si dice "host de destino
///     inaccesible", es esto. Mientras se arregla en el router (o si no
///     tienes acceso a él), usa el siguiente modo:
///   - Celular físico conectado por USB (bypassa el WiFi por completo):
///       1. `adb reverse tcp:3000 tcp:3000`  (reenvía localhost:3000 del
///          celular al puerto 3000 de la PC, vía el cable)
///       2. 'http://localhost:3000' aquí abajo
///       Hay que repetir el `adb reverse` cada vez que se reconecta el
///       cable/se reinicia adb — no es persistente.
/// -----------------------------------------------------------------------
class ApiConfig {
  static const String baseUrl = 'http://localhost:3000';

  /// Mismo token público que usa el mapa (ver main.dart), reexpuesto aquí
  /// para que cualquier pantalla que necesite pegarle a la API de Mapbox
  /// (geocoding, etc.) no tenga que declarar su propio
  /// `String.fromEnvironment`. Se llena vía --dart-define-from-file=env.json.
  static const String mapboxAccessToken =
      String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
}
