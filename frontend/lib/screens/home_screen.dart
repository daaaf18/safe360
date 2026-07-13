import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/map_placeholder.dart';
import 'sos_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const MapPlaceholder(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                        color: AppColors.safe, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Zona segura ahora',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Text('Score: 8.6',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 20,
          bottom: 24,
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SosScreen()),
              );
            },
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.danger.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 2),
                ],
              ),
              child: const Center(
                child: Text('SOS',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
