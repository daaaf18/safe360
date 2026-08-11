import 'package:flutter/material.dart';
import '../theme.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  bool _activated = false;

  final _contacts = const ['Mamá', 'Ana (roomie)', 'Luis (hermano)'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergencia')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            GestureDetector(
              onLongPress: () => setState(() => _activated = true),
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _activated ? AppColors.danger : AppColors.surface,
                  border: Border.all(color: AppColors.danger, width: 3),
                ),
                child: Center(
                  child: Text(
                    _activated ? 'ALERTA\nACTIVA' : 'Mantén\npresionado\npara activar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _activated ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_activated)
              Column(
                children: [
                  const Text('Compartiendo tu ubicación en tiempo real',
                      style: TextStyle(color: AppColors.danger)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() => _activated = false),
                    child: const Text('Cancelar alerta'),
                  ),
                ],
              )
            else
              const Text(
                'Al activar, se notificará tu ubicación en tiempo real a tus contactos de confianza',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            const SizedBox(height: 28),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Se notificará a:',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 8),
            ..._contacts.map((c) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(c,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    trailing: const Icon(Icons.check_circle,
                        color: AppColors.safe, size: 20),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
