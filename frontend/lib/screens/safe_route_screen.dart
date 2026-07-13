import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/map_placeholder.dart';

class SafeRouteScreen extends StatelessWidget {
  const SafeRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ruta segura')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Origen',
              prefixIcon: Icon(Icons.trip_origin, color: AppColors.safe),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Destino',
              prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.danger),
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: const SizedBox(
                height: 260, child: MapPlaceholder(showRoute: true)),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: AppColors.safe,
                    child: Icon(Icons.shield, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TrustScore de la ruta',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600)),
                        Text('Riesgo bajo en horario actual',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Text('8.2/10',
                      style: TextStyle(
                          color: AppColors.safe, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.surfaceLight),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Ver ruta alternativa'),
          ),
        ],
      ),
    );
  }
}
