import 'package:flutter/material.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'contacts_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _reports = [
    ('Poca iluminación', '3 jul 2026', Icons.hourglass_bottom, AppColors.warning),
    ('Robo', '28 jun 2026', Icons.check_circle, AppColors.safe),
    ('Acoso', '20 jun 2026', Icons.check_circle, AppColors.safe),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.surface,
            child: Icon(Icons.person, size: 42, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('Jessica Corona',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
          const Center(
            child: Text('jessica@safe360.app',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withOpacity(0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_off, color: AppColors.warning, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Modo sin conexión: usando la última ruta segura guardada',
                    style: TextStyle(color: AppColors.warning, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Mis reportes',
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._reports.map((r) => Card(
                child: ListTile(
                  leading: Icon(r.$3, color: r.$4),
                  title: Text(r.$1,
                      style: const TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(r.$2,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              )),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.people_outline, color: AppColors.textPrimary),
            title: const Text('Contactos de confianza',
                style: TextStyle(color: AppColors.textPrimary)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ContactsScreen()),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
