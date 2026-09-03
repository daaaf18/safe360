import 'package:url_launcher/url_launcher.dart';

/// Respaldo del SOS cuando no hay internet: no depende de Twilio ni de
/// ningún servicio con costo — abre la app de mensajes del celular con el
/// SMS de emergencia ya redactado (destinatarios + texto), usando el canal
/// nativo del teléfono (SMS sí funciona con solo señal celular, sin datos).
///
/// El usuario todavía tiene que tocar "Enviar" en su app de mensajes —
/// Android no deja mandar SMS sin que el usuario confirme, por diseño — así
/// que esto no reemplaza al WhatsApp automático, es el plan B cuando de
/// plano no hay forma de pegarle al backend.
class SmsFallbackService {
  /// Devuelve `true` si se pudo abrir la app de mensajes, `false` si no hay
  /// contactos con teléfono o si el dispositivo no tiene forma de mandar SMS.
  static Future<bool> abrirSmsDeEmergencia({
    required List<dynamic> contactos,
    required double latitud,
    required double longitud,
    required String nombreUsuario,
    bool ubicacionEsReal = true,
  }) async {
    final numeros = contactos
        .map((c) => (c['telefono']?.toString() ?? '').replaceAll(RegExp(r'\D'), ''))
        .where((n) => n.length >= 10)
        .toSet() // sin duplicados
        .toList();
    if (numeros.isEmpty) return false;

    final link = 'https://maps.google.com/?q=$latitud,$longitud';
    final aviso = ubicacionEsReal ? '' : ' (ubicacion aproximada)';
    final mensaje = 'ALERTA SOS - Safe360\n\n'
        '$nombreUsuario activo una alerta de emergencia. Sin internet, este SOS se mando por SMS.\n\n'
        'Ubicacion actual$aviso:\n$link\n\n'
        'Por favor contactame o llama al 911 si no respondo.\n'
        'Emergencias: 911 | Linea de la Mujer: 800-911-2000';

    // sms:num1,num2,num3?body=... — la app nativa de Mensajes de Android
    // soporta destinatarios separados por coma para un SMS/MMS grupal.
    final uri = Uri(
      scheme: 'sms',
      path: numeros.join(','),
      queryParameters: {'body': mensaje},
    );

    return launchUrl(uri);
  }
}
