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
/// -----------------------------------------------------------------------
class ApiConfig {
  static const String baseUrl = 'http://localhost:3000';
}
