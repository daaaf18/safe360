import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../config.dart';
import '../theme.dart';
import 'safe_route_screen.dart';
import 'sos_screen.dart';
import 'report_screen.dart';
import 'contacts_screen.dart';

class _Message {
  final String text;
  final bool fromUser;
  final String? accion; // acción sugerida por el backend, si aplica
  final bool isAlert; // estilo visual distinto para avisos/errores
  final DateTime time;
  _Message(this.text, this.fromUser, {this.accion, this.isAlert = false})
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

  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechDisponible = false;
  bool _escuchando = false;
  bool _enviando = false;
  String _textoParcial = '';
  String _avatarActual = 'assets/chaty/chaty_neutral.png';
  bool _emergenciaDetectada = false;

  @override
  void initState() {
    super.initState();
    _inicializarSpeech();
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
    if (mounted) setState(() => _speechDisponible = disponible);
  }

  Future<void> _alTocarMicrofono() async {
    if (_escuchando) {
      await _speech.stop();
      setState(() => _escuchando = false);
      _actualizarAvatar('neutral');
      return;
    }

    final permiso = await Permission.microphone.request();
    if (!permiso.isGranted) {
      _mostrarError('Necesito permiso de micrófono para escucharte.');
      return;
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

    setState(() {
      _messages.add(_Message(textoLimpio, true));
      _textoParcial = '';
      _escuchando = false;
      _enviando = true;
    });
    _actualizarAvatar('procesando');
    _scrollAlFinal();

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
        _agregarRespuesta(
          respuesta is String && respuesta.isNotEmpty ? respuesta : 'Recibido 💚',
          accion: data['accion'] as String?,
        );
        // Si es emergencia inmediata, navegar al SOS automáticamente
      if (data['emergencia_inmediata'] == true && mounted) {
        _actualizarAvatar('emergencia');
          await Future.delayed(const Duration(milliseconds: 800));
          Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SosScreen()),
  );
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

  void _agregarRespuesta(String texto, {bool isAlert = false, String? accion}) {
    if (!mounted) return;
    setState(() => _messages.add(_Message(texto, false, isAlert: isAlert, accion: accion)));
    _scrollAlFinal();
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

  @override
  void dispose() {
    _speech.stop();
    _scrollController.dispose();
    super.dispose();
  }

  /// Traduce la "accion" del backend en un botón de navegación dentro del mensaje.
  Widget? _actionButton(String? accion) {
    switch (accion) {
      case 'calcular_ruta':
        return _goToButton('Ir a Ruta segura', Icons.alt_route,
            () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SafeRouteScreen())));
      case 'activar_sos':
        return _goToButton('Ir a Emergencia', Icons.emergency,
            () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SosScreen())));
      case 'abrir_reporte':
        return _goToButton('Ir a Reportar', Icons.warning_amber_rounded,
            () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReportScreen())));
      case 'modo_transporte':
        return _goToButton('Activar modo escolta', Icons.directions_car,
            () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SosScreen())));
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

  void _accionRapida(String texto) => _enviarMensaje(texto);

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
          // Chips de acciones rápidas
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _quickChip(Icons.info_outline, '¿Cómo funciona?',
                    () => _accionRapida('¿Cómo funciona Chaty?')),
                _quickChip(Icons.warning_amber_rounded, 'Reporte rápido',
                    () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ReportScreen()))),
                _quickChip(Icons.people_outline, 'Contactos de confianza',
                    () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const ContactsScreen()))),
              ],
            ),
          ),
          // Botón de micrófono
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: GestureDetector(
                onTap: _enviando ? null : _alTocarMicrofono,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _escuchando ? AppColors.danger : AppColors.safe,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_escuchando ? AppColors.danger : AppColors.safe)
                            .withOpacity(0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: _enviando
                      ? const Padding(
                          padding: EdgeInsets.all(22),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        )
                      : Icon(
                          _escuchando ? Icons.mic : Icons.mic_none,
                          color: Colors.white,
                          size: 30,
                        ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _escuchando ? 'Toca para detener' : 'Mantén presionado o toca para hablar',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
    final action = m.fromUser ? null : _actionButton(m.accion);
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

  Widget _quickChip(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.surfaceLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}