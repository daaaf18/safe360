import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/map_placeholder.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _category = 'Robo';

  final _categories = const [
    ('Robo', Icons.warning_amber_outlined),
    ('Acoso', Icons.report_problem_outlined),
    ('Poca iluminación', Icons.lightbulb_outline),
    ('Accidente vial', Icons.car_crash_outlined),
    ('Otro', Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar incidente')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Categoría', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _category,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                style: const TextStyle(color: AppColors.textPrimary),
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c.$1,
                          child: Row(children: [
                            Icon(c.$2, size: 18, color: AppColors.warning),
                            const SizedBox(width: 10),
                            Text(c.$1),
                          ]),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Descripción', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            maxLines: 4,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Describe brevemente lo que pasó...',
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Adjuntar foto o video'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.surfaceLight),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Ubicación detectada', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: const SizedBox(height: 140, child: MapPlaceholder()),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reporte enviado (demo)')),
              );
            },
            child: const Text('Enviar reporte'),
          ),
        ],
      ),
    );
  }
}
