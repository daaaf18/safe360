import 'package:flutter/material.dart';
import '../theme.dart';

/// Placeholder visual del mapa con heatmap simulado.
/// TODO: reemplazar por mapbox_maps_flutter cuando se integre el SDK real.
class MapPlaceholder extends StatelessWidget {
  final bool showRoute;

  const MapPlaceholder({super.key, this.showRoute = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFF1A2A2E)),
        // Manchas de "heatmap" simuladas
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
        if (showRoute)
          Positioned(
            top: 150,
            left: 60,
            right: 60,
            bottom: 200,
            child: CustomPaint(painter: _RoutePainter()),
          ),
        Center(
          child: Icon(Icons.my_location, color: Colors.white.withOpacity(0.9), size: 28),
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: Text(
            'Vista previa del mapa',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
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
        boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 40)],
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
