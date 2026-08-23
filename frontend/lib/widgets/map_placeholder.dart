import 'package:flutter/material.dart';
import '../theme.dart';

/// Placeholder visual del mapa con heatmap.
/// Muestra reportes reales si se proporcionan, o blobs simulados si no hay datos.
/// TODO: reemplazar por mapbox_maps_flutter cuando se integre el SDK real.
class MapPlaceholder extends StatelessWidget {
  final bool showRoute;
  final List<dynamic> reportes;

  const MapPlaceholder({
    super.key,
    this.showRoute = false,
    this.reportes = const [],
  });

  Color _colorCategoria(String categoria) {
    switch (categoria.toLowerCase()) {
      case 'robo':
      case 'acoso':
        return AppColors.danger;
      case 'poca iluminación':
      case 'accidente vial':
        return AppColors.warning;
      default:
        return AppColors.warning;
    }
  }

  // Convierte índice de reporte a posición relativa en la pantalla
  // Cuando se integre Mapbox, esto se reemplaza por coordenadas reales
  Map<String, double> _posicionSimulada(int index, int total) {
    final positions = [
      {'top': 80.0, 'left': 40.0},
      {'top': 220.0, 'right': 30.0},
      {'bottom': 140.0, 'left': 90.0},
      {'top': 150.0, 'left': 150.0},
      {'bottom': 80.0, 'right': 60.0},
    ];
    return positions[index % positions.length];
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFF1A2A2E)),

        // Blobs del heatmap — reales si hay reportes, simulados si no
        if (reportes.isEmpty) ...[
          Positioned(
            top: 80,
            left: 40,
            child: _blob(AppColors.safe, 120),
          ),
          Positioned(
            top: 220,
            right: 30,
            child: _blob(AppColors.warning, 90),
          ),
          Positioned(
            bottom: 140,
            left: 90,
            child: _blob(AppColors.danger, 70),
          ),
        ] else ...[
          ...List.generate(
            reportes.length > 5 ? 5 : reportes.length,
            (i) {
              final reporte = reportes[i];
              final color = _colorCategoria(reporte['categoria'] ?? '');
              final pos = _posicionSimulada(i, reportes.length);
              final size = reporte['estado'] == 'verificado' ? 100.0 : 70.0;

              Widget blob = _blob(color, size);

              if (pos.containsKey('right') && pos.containsKey('bottom')) {
                return Positioned(bottom: pos['bottom'], right: pos['right'], child: blob);
              } else if (pos.containsKey('right')) {
                return Positioned(top: pos['top'], right: pos['right'], child: blob);
              } else if (pos.containsKey('bottom')) {
                return Positioned(bottom: pos['bottom'], left: pos['left'], child: blob);
              } else {
                return Positioned(top: pos['top'], left: pos['left'], child: blob);
              }
            },
          ),
        ],

        if (showRoute)
          Positioned(
            top: 150,
            left: 60,
            right: 60,
            bottom: 200,
            child: CustomPaint(painter: _RoutePainter()),
          ),

        Center(
          child: Icon(
            Icons.my_location,
            color: Colors.white.withOpacity(0.9),
            size: 28,
          ),
        ),

        Positioned(
          bottom: 12,
          right: 12,
          child: Text(
            reportes.isEmpty
                ? 'Vista previa del mapa'
                : '${reportes.length} reporte${reportes.length != 1 ? 's' : ''} en la zona',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.35),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.25), blurRadius: 40),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
          size.width * 0.3, size.height * 0.5, size.width * 0.5, size.height * 0.4)
      ..quadraticBezierTo(
          size.width * 0.8, size.height * 0.3, size.width, 0);

    final segments = [AppColors.safe, AppColors.warning, AppColors.danger];
    for (var i = 0; i < segments.length; i++) {
      final paint = Paint()
        ..color = segments[i]
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final metrics = path.computeMetrics().first;
      final start = metrics.length * (i / segments.length);
      final end = metrics.length * ((i + 1) / segments.length);
      canvas.drawPath(metrics.extractPath(start, end), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}