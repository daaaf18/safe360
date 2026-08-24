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

class _Message {
  final String text;
  final bool fromUser;
  final String? accion; // acción sugerida por el backend, si aplica
  final bool isAlert; // estilo visual distinto para avisos/errores
  const _Message(this.text, this.fromUser, {this.accion, this.isAlert = false});
}

class ChatyScreen extends StatefulWidget {
  const ChatyScreen({super.key});

  @override
  State<ChatyScreen> createState() => _ChatyScreenState();
}

class _ChatyScreenState extends State<ChatyScreen> {
  final List<_Message> _messages = [
    const _Message(
        'Hola, soy Chaty 💚 Podés pedirme una ruta segura, activar el SOS, '
        'consultar el riesgo de tu zona o abrir un reporte. Tocá el '
        'micrófono para hablarme.',
        false),
  ];

  final stt.SpeechToText _speech = stt.SpeechToText();
  final ScrollController _scrollController = ScrollController();

  bool _speechDisponible = false;
  bool _escuchando = false;
  bool _enviando = false;
  String _textoParcial = '';

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

    setState(() {
      _escuchando = true;
      _textoParcial = '';
    });

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
    setState(() {
      _messages.add(_Message(texto, true));
      _escuchando = false;
      _textoParcial = '';
      _enviando = true;
    });
    _scrollAlFinal();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        _agregarRespuesta(
          'Necesitás iniciar sesión de nuevo para hablar con Chaty.',
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
        body: jsonEncode({'mensaje': texto}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final respuesta = data['mensaje'] ?? data['respuesta'] ?? data['texto'];
        _agregarRespuesta(
          respuesta is String && respuesta.isNotEmpty ? respuesta : 'Recibido 💚',
          accion: data['accion'] as String?,
        );
      } else {
        _agregarRespuesta(
          'No pude procesar eso ahora mismo. Intentá de nuevo en un momento.',
          isAlert: true,
        );
      }
    } catch (_) {
      _agregarRespuesta(
        'No pude conectarme con Chaty. Revisá tu conexión.',
        isAlert: true,
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
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

  @override
  void dispose() {
    _speech.stop();
    _scrollController.dispose();
    super.dispose();
  }

  /// Traduce la "accion" que regresa el backend en un botón de navegación.
  /// accion puede ser: calcular_ruta | activar_sos | consultar_zona |
  /// abrir_reporte | responder
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
      default:
        return null; // 'responder' y 'consultar_zona' se quedan como texto
    }
  }

  Widget _goToButton(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.shield, color: AppColors.safe, size: 20),
            SizedBox(width: 8),
            Column(
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
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: _messages.map((m) => _bubble(m)).toList(),
            ),
          ),
          if (_escuchando)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _textoParcial.isEmpty ? 'Escuchando…' : _textoParcial,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
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
                  ),
                  child: _enviando
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Icon(
                          _escuchando ? Icons.mic : Icons.mic_none,
                          color: Colors.white,
                          size: 32,
                        ),
                ),
              ),
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

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: m.isAlert
              ? Border.all(color: AppColors.warning.withOpacity(0.5))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text, style: TextStyle(color: textColor, fontSize: 13)),
            if (action != null) action,
          ],
        ),
      ),
    );
  }
}