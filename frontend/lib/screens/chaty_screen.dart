import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../theme.dart';
import 'safe_route_screen.dart';
import 'sos_screen.dart';
import 'report_screen.dart';

class _Message {
  final String text;
  final bool fromUser;
  final String? accion; // acción sugerida por el backend, si aplica
  const _Message(this.text, this.fromUser, {this.accion});
}

class ChatyScreen extends StatefulWidget {
  const ChatyScreen({super.key});

  @override
  State<ChatyScreen> createState() => _ChatyScreenState();
}

class _ChatyScreenState extends State<ChatyScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  final List<_Message> _messages = [
    const _Message(
        'Hola, soy Chaty 💚 Puedo ayudarte a calcular una ruta segura, '
        'activar el SOS, consultar el riesgo de una zona o abrir un reporte. '
        '¿En qué te ayudo?',
        false),
  ];

  bool _sending = false;

  Future<void> _enviarMensaje() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _sending) return;

    setState(() {
      _messages.add(_Message(texto, true));
      _controller.clear();
      _sending = true;
    });
    _scrollToEnd();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() {
          _messages.add(const _Message(
              'Necesitas iniciar sesión para hablar con Chaty.', false));
          _sending = false;
        });
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

      final data = jsonDecode(response.body);

      setState(() {
        if (response.statusCode == 200) {
          _messages.add(_Message(
            data['mensaje'] ?? 'Entendido.',
            false,
            accion: data['accion'],
          ));
        } else {
          _messages.add(_Message(
              data['error'] ?? 'No pude procesar tu mensaje.', false));
        }
        _sending = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(const _Message(
            'No pude conectarme con el servidor. Intenta de nuevo.', false));
        _sending = false;
      });
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
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
      case 'consultar_zona':
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
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_sending ? 1 : 0),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                        color: AppColors.surface, borderRadius: BorderRadius.circular(30)),
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _enviarMensaje(),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _enviarMensaje,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration:
                        const BoxDecoration(color: AppColors.safe, shape: BoxShape.circle),
                    child: const Icon(Icons.send, color: Colors.white, size: 18),
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
    final color = m.fromUser ? AppColors.safe : AppColors.surface;
    final textColor = m.fromUser ? Colors.white : AppColors.textPrimary;
    final action = m.fromUser ? null : _actionButton(m.accion);

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
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
