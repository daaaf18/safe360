import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../config.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../services/permission_queue_service.dart';
import '../theme.dart';
import 'safe_route_screen.dart';
import 'sos_screen.dart';
import 'report_screen.dart';

/// Cada cuánto se revisa si el vehículo/transporte se desvió de la ruta
/// esperada (POST /rutas/transporte/verificar) mientras el modo transporte
/// sigue activo.
const _intervaloVerificacionTransporte = Duration(seconds: 90);

/// Cada cuánto se revisa si hay alertas nuevas de "reporte cerca de tu
/// ruta activa" (GET /rutas/alertas — ver notificarRutasAfectadas en el
/// backend). Antes ese aviso solo llegaba por WhatsApp a tus contactos;
/// esto lo trae también a Chaty mientras la pantalla está abierta.
const _intervaloPollAlertas = Duration(seconds: 30);

class _Message {
  final String text;
  final bool fromUser;
  final String? accion; // acción sugerida por el backend, si aplica
  final String? destino; // destino extraído por Chaty, si aplica
  final String? tipoTransporte;
  final bool isAlert; // estilo visual distinto para avisos/errores
  final DateTime time;
  _Message(this.text, this.fromUser,
      {this.accion, this.destino, this.tipoTransporte, this.isAlert = false})
      : time = DateTime.now();
}

class ChatyScreen extends StatefulWidget {
  const ChatyScreen({super.key});

  @override
  State<ChatyScreen> createState() => _ChatyScreenState();
}

class _ChatyScreenState extends State<ChatyScreen> {
  final List<_Message> _messages = [
    _Message(
      'Hola, soy Chaty 💚 Toca el micrófono y dime qué necesitas: calcular '
      'una ruta segura, activar el SOS, consultar el riesgo de tu zona o '
      'abrir un reporte.',
      false,
    ),
  ];

  /// Los chips de "qué puedes preguntar" solo tienen sentido antes de que
  /// arranque la conversación de verdad — una vez que ya mandaste algo,
  /// se quitan del camino (ver build()).
  bool get _huboMensajeDeUsuario => _messages.any((m) => m.fromUser);

  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  // Antes Chaty solo se podía usar por voz (o los chips fijos) — sin
  // campo de texto, alguien sordo, mudo, o que simplemente no puede
  // hablar en voz alta en ese momento (el caso real de seguridad: alguien
  // escondiéndose de un peligro) no tenía NINGUNA forma de escribirle,
  // ni siquiera "auxilio".
  final TextEditingController _inputController = TextEditingController();

  bool _speechDisponible = false;
  bool _escuchando = false;
  bool _enviando = false;
  String _textoParcial = '';
  String _avatarActual = 'assets/chaty/chaty_neutral.png';
  bool _emergenciaDetectada = false;

  // ── Modo transporte ───────────────────────────────────────────────
  bool _viajeActivo = false;
  bool _activandoTransporte = false;

  /// Chaty no tiene memoria de conversación — cada mensaje se procesa
  /// solo, sin el historial de antes. Si dijiste "voy en Uber" sin
  /// destino, Chaty te pregunta "¿a dónde?", pero si tu SIGUIENTE mensaje
  /// es nada más el lugar ("BUAP"), Gemini lo interpretaría como una
  /// petición nueva de "calcular_ruta", no como la respuesta a esa
  /// pregunta. Esto guarda "seguimos esperando destino" del lado del
  /// cliente para que el próximo mensaje se use directo como destino, sin
  /// pasar por Gemini a adivinar el contexto.
  bool _esperandoDestinoTransporte = false;
  String? _tipoTransporteEsperado;
  Timer? _transporteTimer;

  /// Si detectamos un desvío y el usuario no hace nada en este lapso
  /// (no manda mensaje, no toca "Ir a Emergencia", no finaliza el viaje),
  /// se activa el SOS solo — para el caso real que esto cubre (el
  /// conductor se desvió y la persona no puede o no se atreve a
  /// reaccionar en el momento).
  static const _esperaAutoSos = Duration(seconds: 30);
  Timer? _autoSosTimer;

  // ── Alertas de rutas afectadas ──────────────────────────────────────
  Timer? _alertasTimer;

  @override
  void initState() {
    super.initState();
    _inicializarSpeech();
    _iniciarPollAlertas();
  }

  @override
  void dispose() {
    _transporteTimer?.cancel();
    _autoSosTimer?.cancel();
    _alertasTimer?.cancel();
    _speech.stop();
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _iniciarPollAlertas() {
    _revisarAlertas(); // primera revisión de una vez, no hasta el primer tick
    _alertasTimer?.cancel();
    _alertasTimer = Timer.periodic(_intervaloPollAlertas, (_) => _revisarAlertas());
  }

  Future<void> _revisarAlertas() async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/rutas/alertas'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (!mounted || response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final alertas = (data['alertas'] as List?) ?? [];
      for (final alerta in alertas) {
        _actualizarAvatar('emergencia');
        _agregarRespuesta(
          alerta['mensaje'] as String? ?? '⚠️ Hay un reporte cerca de tu ruta activa.',
          isAlert: true,
        );
      }
      if (alertas.isNotEmpty) {
        // Avatar en emergencia 3s tras la última alerta — tiempo
        // suficiente para que se note sin quedarse pegado ahí.
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) _actualizarAvatar('neutral');
      }
    } catch (_) {
      // Sin conexión momentánea: se reintenta en el siguiente tick.
    }
  }

  Future<void> _inicializarSpeech() async {
    final disponible = await _speech.initialize(
      onError: (error) {
        setState(() => _escuchando = false);
        _mostrarError('No se pudo escuchar: ${error.errorMsg}');
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _escuchando = false);
        }
      },
    );
    debugPrint('[Chaty] speech_to_text inicializado: $disponible');
    if (mounted) setState(() => _speechDisponible = disponible);
  }

  Future<void> _alTocarMicrofono() async {
    if (_escuchando) {
      await _speech.stop();
      setState(() => _escuchando = false);
      _actualizarAvatar('neutral');
      return;
    }

    // PermissionQueueService en vez de Permission.request() directo:
    // permission_handler solo deja una solicitud de permiso en vuelo a la
    // vez en TODO el proceso, sin importar el tipo — si otra pantalla
    // (ubicación, típicamente) tiene una en curso, esto tronaba con
    // PlatformException("A request for permissions is already running").
    final permiso = await PermissionQueueService.solicitar(Permission.microphone);
    debugPrint('[Chaty] status permiso micrófono: $permiso');
    if (permiso.isPermanentlyDenied || permiso.isRestricted) {
      // Android ya no vuelve a mostrar el diálogo del sistema en este
      // caso (lo negaste 2 veces, o "no volver a preguntar") — sin esto,
      // el botón parece que "no hace nada" porque el request() no
      // muestra nada, solo regresa denied en silencio.
      _mostrarError('El permiso de micrófono está bloqueado. Actívalo en '
          'Ajustes > Apps > Safe360 > Permisos > Micrófono.');
      return;
    }
    if (!permiso.isGranted) {
      _mostrarError('Necesito permiso de micrófono para escucharte.');
      return;
    }
    if (!_speechDisponible) {
      // `_inicializarSpeech()` corrió en `initState`, antes de que el
      // usuario diera el permiso de micrófono (recién concedido arriba) —
      // el plugin `speech_to_text` regresa `initialize() == false` (y se
      // queda así) cuando no hay permiso todavía, así que reintentamos
      // ahora que sí lo tenemos. Sin esto, el botón se quedaba "muerto"
      // para siempre después de la primera vez que se abría Chaty sin
      // permiso ya concedido.
      await _inicializarSpeech();
    }
    if (!_speechDisponible) {
      _mostrarError('El reconocimiento de voz no está disponible en este dispositivo.');
      return;
    }

    setState(() => _escuchando = true);
    _actualizarAvatar('escuchando');

    await _speech.listen(
      localeId: 'es_MX',
      onResult: (result) {
        setState(() => _textoParcial = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _enviarMensaje(result.recognizedWords.trim());
        }
      },
    );
  }

  Future<void> _enviarMensaje(String texto) async {
    final textoLimpio = texto.trim();
    if (textoLimpio.isEmpty || _enviando) return;

    // Cualquier mensaje tuyo cuenta como "sigo aquí, estoy bien" — cancela
    // el auto-SOS pendiente por un desvío detectado en modo transporte.
    _cancelarCuentaRegresivaAutoSos();

    setState(() {
      _messages.add(_Message(textoLimpio, true));
      _textoParcial = '';
      _escuchando = false;
      _enviando = true;
    });
    _actualizarAvatar('procesando');
    _scrollAlFinal();

    // Chaty preguntó "¿a dónde te llevan?" en el mensaje anterior — este
    // ES la respuesta a eso. Se usa directo como destino, sin mandarlo a
    // Gemini (que no sabe que le acabamos de preguntar algo).
    if (_esperandoDestinoTransporte) {
      final tipoTransporte = _tipoTransporteEsperado;
      _esperandoDestinoTransporte = false;
      _tipoTransporteEsperado = null;
      setState(() => _enviando = false);
      _actualizarAvatar('neutral');
      await _activarModoTransporte(textoLimpio, tipoTransporte);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _agregarRespuesta(
          'Necesitas iniciar sesión de nuevo para hablar con Chaty.',
          isAlert: true,
        );
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/chaty'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'mensaje': textoLimpio}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final respuesta = data['mensaje'] ?? data['respuesta'] ?? data['texto'];
        final accion = data['accion'] as String?;
        final destino = data['destino'] as String?;
        final tipoTransporte = data['tipo_transporte'] as String?;
        _agregarRespuesta(
          respuesta is String && respuesta.isNotEmpty ? respuesta : 'Recibido 💚',
          accion: accion,
          destino: destino,
          tipoTransporte: tipoTransporte,
        );
        // Emergencia real detectada por palabra clave: no basta con abrir
        // la pantalla y esperar a que la persona toque el botón — puede
        // que no pueda.
        if (data['emergencia_inmediata'] == true && mounted) {
          await _activarEmergenciaDeVerdad();
        }

        // Modo transporte: si Chaty ya extrajo el destino, lo activamos
        // directo (misma lógica que la emergencia — no hace falta que el
        // usuario toque nada más). Si no vino destino, Chaty ya lo
        // pregunta en su respuesta — guardamos que el SIGUIENTE mensaje
        // es la respuesta a eso (ver _esperandoDestinoTransporte arriba).
        if (accion == 'modo_transporte') {
          if (destino != null && destino.trim().isNotEmpty) {
            _esperandoDestinoTransporte = false;
            await _activarModoTransporte(destino, tipoTransporte);
          } else {
            _esperandoDestinoTransporte = true;
            _tipoTransporteEsperado = tipoTransporte;
          }
        }

        // Calcular ruta: mismo criterio — si ya sabemos el destino, no
        // tiene caso mandar solo un botón para que el usuario lo vuelva a
        // escribir en Ruta segura. Se calcula de una vez (origen = tu GPS
        // actual) y se abre la pantalla ya con la ruta lista, el mapa, el
        // TrustScore, los puntos seguros, etc. — igual que "reactivar" una
        // ruta frecuente desde Perfil.
        if (accion == 'calcular_ruta' && destino != null && destino.trim().isNotEmpty) {
          await _calcularYMostrarRuta(destino);
        }

        // Consultar zona: antes esto no hacía nada más que el texto
        // genérico de Gemini — ahora sí revisa tu GPS real solo (no hace
        // falta que digas "usa mi ubicación") y manda la evaluación de
        // verdad como un mensaje aparte de Chaty.
        if (accion == 'consultar_zona') {
          await _consultarZonaActual();
        }

        // "Ya llegué" — el backend ya confirmó que había un viaje activo;
        // aquí se hace la parte que solo el cliente puede hacer (parar el
        // timer local de monitoreo) además de avisarle al backend.
        if (accion == 'finalizar_viaje') {
          await _finalizarViaje();
        }
      } else {
        _agregarRespuesta(
          'No pude procesar eso ahora mismo. Intenta de nuevo en un momento.',
          isAlert: true,
        );
      }
    } catch (_) {
      _agregarRespuesta(
        'No pude conectarme con Chaty. Revisa tu conexión.',
        isAlert: true,
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
      _actualizarAvatar('neutral');
    }
  }

  void _agregarRespuesta(
    String texto, {
    bool isAlert = false,
    String? accion,
    String? destino,
    String? tipoTransporte,
  }) {
    if (!mounted) return;
    setState(() => _messages.add(_Message(
          texto,
          false,
          isAlert: isAlert,
          accion: accion,
          destino: destino,
          tipoTransporte: tipoTransporte,
        )));
    _scrollAlFinal();
  }

  bool _calculandoRuta = false;
  bool _consultandoZona = false;

  /// "Qué tan segura está mi zona" — pide tu GPS real y le pregunta al
  /// backend por reportes/luminarias/riesgo por horario cerca de ese
  /// punto (GET /zonas/aqui). Antes esto no hacía nada; el `mensaje` de
  /// Gemini sonaba a que sí iba a revisar algo, pero nunca se conectó a
  /// datos reales.
  Future<void> _consultarZonaActual() async {
    if (_consultandoZona) return;
    _consultandoZona = true;
    try {
      final ubicacion = await LocationService.obtenerUbicacionActual();
      if (!mounted) return;
      if (!ubicacion.exito) {
        _agregarRespuesta(
          'No pude revisar tu zona: ${ubicacion.mensajeError}',
          isAlert: true,
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final uri = Uri.parse('${ApiConfig.baseUrl}/zonas/aqui').replace(queryParameters: {
        'lat': '${ubicacion.posicion!.latitude}',
        'lon': '${ubicacion.posicion!.longitude}',
      });
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final esAlto = data['nivel_riesgo'] == 'alto';
        _agregarRespuesta(data['mensaje'] ?? 'Ya revisé tu zona.', isAlert: esAlto);
      } else {
        _agregarRespuesta('No pude revisar tu zona ahora mismo.', isAlert: true);
      }
    } catch (_) {
      if (mounted) {
        _agregarRespuesta('No pude revisar tu zona — revisa tu conexión.', isAlert: true);
      }
    } finally {
      _consultandoZona = false;
    }
  }

  /// Geocodifica el destino que Chaty extrajo y abre Ruta segura ya con
  /// esa ruta calculada (origen = tu GPS actual) — el usuario no tiene que
  /// volver a escribir nada, igual que "reactivar" una ruta frecuente
  /// desde Perfil (misma pantalla, mismo mecanismo).
  Future<void> _calcularYMostrarRuta(String destino) async {
    if (_calculandoRuta) return;
    _calculandoRuta = true;
    try {
      final resultado = await GeocodingService.buscar(destino);
      if (!mounted) return;
      if (resultado == null) {
        _agregarRespuesta(
          'No encontré "$destino" en Puebla. ¿Puedes decirme la dirección más específica?',
          isAlert: true,
        );
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SafeRouteScreen(
          initialDestinoLat: resultado.lat,
          initialDestinoLon: resultado.lon,
        ),
      ));
    } finally {
      _calculandoRuta = false;
    }
  }

  /// Activa el modo transporte: geocodifica el destino que Chaty extrajo,
  /// registra el viaje en el backend (POST /rutas/transporte) y arranca el
  /// monitoreo periódico de desvío.
  Future<void> _activarModoTransporte(String destino, String? tipoTransporte) async {
    if (_activandoTransporte || _viajeActivo) return;
    setState(() => _activandoTransporte = true);

    try {
      final origenResultado = await LocationService.obtenerUbicacionActual();
      if (!origenResultado.exito) {
        _agregarRespuesta(
          'No pude activar el modo transporte: ${origenResultado.mensajeError}',
          isAlert: true,
        );
        return;
      }

      final destinoResuelto = await GeocodingService.buscar(destino);
      if (destinoResuelto == null) {
        _agregarRespuesta(
          'No encontré "$destino". ¿Puedes decirme la dirección más específica?',
          isAlert: true,
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        _agregarRespuesta('Necesitas iniciar sesión para activar el modo transporte.',
            isAlert: true);
        return;
      }

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/rutas/transporte'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'origen_lat': origenResultado.posicion!.latitude,
              'origen_lon': origenResultado.posicion!.longitude,
              'destino_lat': destinoResuelto.lat,
              'destino_lon': destinoResuelto.lon,
              'tipo_transporte': tipoTransporte,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final recomendaciones = (data['recomendaciones'] as List?)
                ?.map((r) => '• $r')
                .join('\n') ??
            '';
        _agregarRespuesta(
          '${data['message'] ?? 'Modo transporte activado.'}'
          '${recomendaciones.isNotEmpty ? '\n\n$recomendaciones' : ''}\n\n'
          'Voy a avisarte si detecto un desvío de más de 300 m de tu ruta.',
        );
        if (mounted) setState(() => _viajeActivo = true);
        _iniciarMonitoreoTransporte();
      } else {
        final data = jsonDecode(response.body);
        _agregarRespuesta(
          data['error'] ?? 'No se pudo activar el modo transporte.',
          isAlert: true,
        );
      }
    } catch (_) {
      _agregarRespuesta(
        'No pude conectarme para activar el modo transporte. Revisa tu conexión.',
        isAlert: true,
      );
    } finally {
      if (mounted) setState(() => _activandoTransporte = false);
    }
  }

  void _iniciarMonitoreoTransporte() {
    _transporteTimer?.cancel();
    _transporteTimer =
        Timer.periodic(_intervaloVerificacionTransporte, (_) => _verificarDesvioTransporte());
  }

  /// Se llama cada [_intervaloVerificacionTransporte] mientras el viaje
  /// sigue activo: manda el GPS actual a POST /rutas/transporte/verificar,
  /// que compara contra la línea origen→destino y avisa si te desviaste
  /// más de 300 m (el conductor tomó otra ruta, por ejemplo).
  Future<void> _verificarDesvioTransporte() async {
    if (!mounted || !_viajeActivo) return;

    final resultado = await LocationService.obtenerUbicacionActual();
    if (!resultado.exito) return; // se reintenta en el siguiente tick

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/rutas/transporte/verificar'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'latitud_actual': resultado.posicion!.latitude,
              'longitud_actual': resultado.posicion!.longitude,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted || !_viajeActivo) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['hayDesvio'] == true) {
          _actualizarAvatar('emergencia');
          _agregarRespuesta(
            '${data['alerta'] ?? '⚠️ Detecté que te desviaste de la ruta esperada.'} '
            'Si no respondes en ${_esperaAutoSos.inSeconds}s, activo el SOS por ti.',
            isAlert: true,
            accion: 'activar_sos',
          );
          _iniciarCuentaRegresivaAutoSos();
        }
      } else if (response.statusCode == 404) {
        // El backend ya no tiene el viaje como activo (p. ej. se finalizó
        // desde otra sesión) — dejamos de monitorear.
        _detenerMonitoreoTransporte();
      }
    } catch (_) {
      // Sin conexión momentánea: se reintenta en el siguiente tick.
    }
  }

  Future<void> _finalizarViaje() async {
    _detenerMonitoreoTransporte();
    _cancelarCuentaRegresivaAutoSos(); // llegaste — ya no hace falta el auto-SOS pendiente
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/rutas/transporte/finalizar'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      _agregarRespuesta('✅ Viaje finalizado. ¡Llegaste segura!');
      _actualizarAvatar('feliz');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _actualizarAvatar('neutral');
      });
    } catch (_) {
      // Ya se dejó de monitorear localmente aunque el backend no responda.
    }
  }

  void _iniciarCuentaRegresivaAutoSos() {
    _autoSosTimer?.cancel();
    _autoSosTimer = Timer(_esperaAutoSos, _activarSosAutomatico);
  }

  void _cancelarCuentaRegresivaAutoSos() {
    _autoSosTimer?.cancel();
    _autoSosTimer = null;
  }

  /// Se dispara sola si detectamos un desvío en modo transporte y pasan
  /// [_esperaAutoSos] sin que el usuario mande un mensaje, toque "Ir a
  /// Emergencia" o finalice el viaje — o sea, sin ninguna señal de que
  /// está bien y puede reaccionar por su cuenta. `SosScreen(autoActivar:
  /// true)` se encarga de todo (WhatsApp + SMS + rastreo) por el mismo
  /// camino de siempre — no duplicamos esa llamada aquí.
  Future<void> _activarSosAutomatico() async {
    if (!mounted) return;
    _agregarRespuesta(
      '🚨 No respondiste a tiempo — activando el SOS por tu seguridad.',
      isAlert: true,
    );
    _actualizarAvatar('emergencia');
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SosScreen(autoActivar: true)),
      );
    }
  }

  void _detenerMonitoreoTransporte() {
    _transporteTimer?.cancel();
    _transporteTimer = null;
    if (mounted) setState(() => _viajeActivo = false);
  }

  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  void _actualizarAvatar(String estado) {
  const avatares = {
    'neutral':     'assets/chaty/chaty_neutral.png',
    'escuchando':  'assets/chaty/chaty_escuchando.png',
    'procesando':  'assets/chaty/chaty_procesando.png',
    'emergencia':  'assets/chaty/chaty_emergencia.png',
    'feliz':       'assets/chaty/chaty_feliz.png',
  };
  if (mounted) setState(() => _avatarActual = avatares[estado] ?? avatares['neutral']!);
}

  /// Traduce la "accion" del backend en un botón de acción dentro del mensaje.
  Widget? _actionButton(_Message m) {
    switch (m.accion) {
      case 'calcular_ruta':
        return _goToButton('Ir a Ruta segura', Icons.alt_route,
            () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SafeRouteScreen())));
      case 'activar_sos':
        return _goToButton('Ir a Emergencia', Icons.emergency, () {
          _cancelarCuentaRegresivaAutoSos(); // tocó el botón — ya no hace falta activarlo solo
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SosScreen()));
        });
      case 'abrir_reporte':
        return _goToButton('Ir a Reportar', Icons.warning_amber_rounded,
            () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReportScreen())));
      case 'modo_transporte':
        // Si Chaty ya extrajo el destino, esto normalmente ya se activó
        // solo (ver _enviarMensaje) — el botón queda como reintento por si
        // falló. Si no hay destino, no hay nada que activar todavía: el
        // usuario tiene que decir a dónde va en su siguiente mensaje.
        if (_viajeActivo) {
          return _goToButton('Finalizar viaje', Icons.check_circle_outline, _finalizarViaje);
        }
        if (m.destino != null && m.destino!.trim().isNotEmpty) {
          return _goToButton(
            _activandoTransporte ? 'Activando...' : 'Reintentar modo transporte',
            Icons.directions_car,
            _activandoTransporte
                ? () {}
                : () => _activarModoTransporte(m.destino!, m.tipoTransporte),
          );
        }
        return null;
      default:
        return null; // 'responder' y 'consultar_zona' se quedan como texto
    }
  }

  Widget _goToButton(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: const BorderSide(color: AppColors.safe),
          foregroundColor: AppColors.safe,
        ),
      ),
    );
  }

  /// El SOS se dispara solo (WhatsApp + SMS + rastreo cada 2 min) apenas
  /// carga la pantalla — mismo camino sin importar de dónde vino la señal
  /// de emergencia: palabra clave por voz/texto, o este chip de un solo
  /// toque (pensado para cuando ni siquiera escribir "auxilio" es una
  /// opción rápida — alguien que no puede hablar tampoco debería tener
  /// que escribir bajo presión, un toque debe bastar igual que la voz).
  Future<void> _activarEmergenciaDeVerdad() async {
    _actualizarAvatar('emergencia');
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SosScreen(autoActivar: true)),
      );
    }
  }

  /// Respuesta fija, sin pasarla por Gemini — es contenido estático (qué
  /// hace la app), no algo que necesite interpretación de lenguaje
  /// natural, así que preguntarle a un modelo de IA solo la hace más
  /// lenta y gasta cuota para nada.
  void _explicarComoFunciona() {
    setState(() => _messages.add(_Message('¿Cómo funciona Chaty?', true)));
    _scrollAlFinal();
    _agregarRespuesta(
      'Puedo ayudarte a calcular una ruta segura, activar el SOS, revisar '
      'qué tan segura está tu zona, monitorear tu viaje si vas en Uber/taxi, '
      'o abrir un reporte — dime o escríbeme qué necesitas.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
    AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Image.asset(
        _avatarActual,
        key: ValueKey(_avatarActual),
        height: 36,
        width: 36,
      ),
    ),
    const SizedBox(width: 8),
    const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chaty', style: TextStyle(fontSize: 16)),
        Text('Tu asistente de seguridad',
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ],
    ),
  ),
      body: Column(
        children: [
          // Banner superior
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.safe.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield, color: AppColors.safe, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Monitoreando tu zona',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      Text('Chaty está activo y disponible',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
              ],
            ),
          ),
          if (_viajeActivo)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_car, color: AppColors.warning, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Modo transporte activo — monitoreando tu ruta',
                        style: TextStyle(color: AppColors.warning, fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: _finalizarViaje,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Finalizar', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          // Mensajes
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_enviando ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.only(left: 4, top: 4),
                    child: Text('Chaty está escribiendo...',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  );
                }
                return _bubble(_messages[i]);
              },
            ),
          ),
          // Texto parcial mientras escucha
          if (_escuchando)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _textoParcial.isEmpty ? 'Escuchando…' : _textoParcial,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          // El SOS de un toque ya vive en Home (el botón flotante) — no
          // hacía falta duplicarlo aquí. "¿Cómo funciona?" se queda como
          // el único chip, solo antes de que arranque la conversación de
          // verdad (después ya no hace falta).
          if (!_huboMensajeDeUsuario)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _quickChip(
                    Icons.info_outline, '¿Cómo funciona?', _explicarComoFunciona),
              ),
            ),
          // El micrófono sigue siendo lo principal (grande, primero en el
          // ojo) — el texto va como compañero más chico en la misma fila,
          // no como una sección aparte con el mismo peso visual. Es la
          // alternativa para quien no puede o no quiere hablar en voz
          // alta (sordo, mudo, o una situación donde hablar delataría
          // dónde está), pero no compite con la voz por atención.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    enabled: !_enviando,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'O escribe…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        onPressed: _enviando
                            ? null
                            : () {
                                final texto = _inputController.text;
                                _inputController.clear();
                                _enviarMensaje(texto);
                              },
                        icon: const Icon(Icons.send, size: 18, color: AppColors.textSecondary),
                      ),
                    ),
                    onSubmitted: (texto) {
                      _inputController.clear();
                      _enviarMensaje(texto);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Se queda notablemente más grande que el campo de texto
                // a propósito — sigue siendo la forma principal de hablar
                // con Chaty, el texto es el respaldo, no un igual.
                GestureDetector(
                  onTap: _enviando ? null : _alTocarMicrofono,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: _escuchando ? AppColors.danger : AppColors.safe,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_escuchando ? AppColors.danger : AppColors.safe)
                              .withOpacity(0.45),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: _enviando
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                          )
                        : Icon(
                            _escuchando ? Icons.mic : Icons.mic_none,
                            color: Colors.white,
                            size: 28,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(_Message m) {
    final align = m.fromUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = m.isAlert
        ? AppColors.warning.withOpacity(0.15)
        : (m.fromUser ? AppColors.safe : AppColors.surface);
    final textColor = m.isAlert
        ? AppColors.warning
        : (m.fromUser ? Colors.white : AppColors.textPrimary);
    final action = m.fromUser ? null : _actionButton(m);
    final time =
        '${m.time.hour.toString().padLeft(2, '0')}:${m.time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: m.isAlert ? Border.all(color: AppColors.warning.withOpacity(0.5)) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text, style: TextStyle(color: textColor, fontSize: 13)),
            if (action != null) action,
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: TextStyle(color: textColor.withOpacity(0.55), fontSize: 9)),
                if (m.fromUser) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.done_all, size: 12, color: Colors.white70),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChip(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color?.withOpacity(0.12) ?? AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color ?? AppColors.surfaceLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    color: color ?? AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: color != null ? FontWeight.w700 : FontWeight.w400,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}