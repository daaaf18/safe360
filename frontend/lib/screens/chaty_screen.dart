import 'package:flutter/material.dart';
import '../theme.dart';

class _Message {
  final String text;
  final bool fromUser;
  final bool isAlert;
  const _Message(this.text, this.fromUser, {this.isAlert = false});
}

class ChatyScreen extends StatelessWidget {
  const ChatyScreen({super.key});

  static const _messages = [
    _Message('Voy sola a casa', true),
    _Message(
        'Esta ruta tiene riesgo bajo ahora, pero baja después de las 9pm. '
        '¿Quieres que te avise si algo cambia?',
        false,
        isAlert: true),
    _Message('Sí, por favor', true),
    _Message('Listo, estaré monitoreando tu trayecto 💚', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chaty')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _messages.map((m) => _bubble(m)).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.safe,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 32),
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
        ? AppColors.warning.withOpacity(0.18)
        : m.fromUser
            ? AppColors.safe
            : AppColors.surface;
    final textColor = m.fromUser ? Colors.white : AppColors.textPrimary;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: m.isAlert
              ? Border.all(color: AppColors.warning.withOpacity(0.6))
              : null,
        ),
        child: Text(m.text, style: TextStyle(color: textColor)),
      ),
    );
  }
}
