import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Convierte una dirección escrita ("BUAP", "Zócalo de Puebla", etc.) a
/// coordenadas reales usando la API de Geocoding de Mapbox.
///
/// Antes, Ruta segura ignoraba por completo lo que escribías en los campos
/// de Origen/Destino y siempre calculaba la misma ruta de prueba
/// hardcodeada — esto es lo que lo conecta de verdad.
class GeocodingService {
  // Puebla, para que resultados ambiguos ("Centro", "Zócalo") prioricen
  // la zona piloto en vez de, por ejemplo, un lugar con el mismo nombre en
  // otro país.
  static const double _proximityLat = 19.0414;
  static const double _proximityLon = -98.2063;

  // `proximity` solo ordena por cercanía, no descarta resultados lejanos
  // (escribir "Centro" podía sugerir el de otra ciudad o país). `bbox` sí
  // restringe de verdad — mismos límites que usa el mapa (safe360_map.dart)
  // para la zona piloto de Puebla, así las sugerencias siempre son de ahí.
  static const String _bboxPuebla = '-98.35,18.80,-98.00,19.22';

  /// Devuelve (lat, lon) del mejor resultado, o `null` si no hay token
  /// configurado, no hay resultados, o falla la petición.
  static Future<({double lat, double lon})?> buscar(String direccion) async {
    final resultados = await sugerencias(direccion, limite: 1);
    if (resultados.isEmpty) return null;
    return (lat: resultados.first.lat, lon: resultados.first.lon);
  }

  /// Lista de direcciones que coinciden con lo que se lleva escrito hasta
  /// ahora (autocompletado tipo DiDi/Uber, mientras el usuario teclea).
  /// Devuelve `[]` si no hay token, no hay resultados, o falla la petición
  /// — nunca truena, para que se pueda llamar en cada letra sin cuidado.
  static Future<List<({String nombre, double lat, double lon})>> sugerencias(
    String texto, {
    int limite = 5,
  }) async {
    final query = texto.trim();
    if (query.isEmpty) return [];

    final token = ApiConfig.mapboxAccessToken;
    if (token.isEmpty) return [];

    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json',
      {
        'access_token': token,
        'proximity': '$_proximityLon,$_proximityLat',
        'bbox': _bboxPuebla,
        'language': 'es',
        'autocomplete': 'true',
        'limit': '$limite',
      },
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null) return [];

      return features
          .map((f) {
            final feature = f as Map<String, dynamic>;
            final coords = feature['center'] as List;
            return (
              nombre: feature['place_name'] as String? ?? query,
              lat: (coords[1] as num).toDouble(),
              lon: (coords[0] as num).toDouble(),
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Geocoding inverso: de coordenadas a un nombre de lugar/dirección
  /// legible. Se usa en el selector "marcar en el mapa" de Ruta segura
  /// (como en DiDi) para mostrar qué hay bajo el pin mientras lo mueves,
  /// en vez de solo enseñar lat/lon crudas.
  static Future<String?> direccionDesde(double lat, double lon) async {
    final token = ApiConfig.mapboxAccessToken;
    if (token.isEmpty) return null;

    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/$lon,$lat.json',
      {
        'access_token': token,
        'language': 'es',
        'limit': '1',
      },
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return null;

      return (features.first as Map<String, dynamic>)['place_name'] as String?;
    } catch (_) {
      return null;
    }
  }
}
