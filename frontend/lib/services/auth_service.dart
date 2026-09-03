import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AuthService {
  static String get baseUrl => ApiConfig.baseUrl;

  /// El backend regresa errores en 2 formatos distintos según el caso:
  /// - Errores normales:        { error: "mensaje" }
  /// - Errores de validación
  ///   (express-validator):     { errores: [{ msg: "mensaje", ... }, ...] }
  /// Este helper cubre ambos para que el mensaje de error siempre se
  /// muestre bien en pantalla.
  static String _extraerError(Map<String, dynamic> data, String fallback) {
    if (data['error'] != null) return data['error'] as String;
    if (data['errores'] is List && (data['errores'] as List).isNotEmpty) {
      final primero = (data['errores'] as List).first;
      if (primero is Map && primero['msg'] != null) return primero['msg'] as String;
    }
    return fallback;
  }

  /// Sin timeout, si el backend no responde (apagado, IP equivocada en
  /// config.dart, celular fuera de la red WiFi de la compu) la petición se
  /// queda colgada indefinidamente y la pantalla de login parece "trabada".
  /// Con esto, a los 10s se cae con un mensaje claro en vez de quedarse ahí.
  static const _timeout = Duration(seconds: 10);
  static const _errorConexion =
      'No se pudo conectar con el servidor. Revisa que el backend esté '
      'corriendo y que la IP en config.dart sea correcta.';

  // Login con email y contraseña
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_timeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('usuario', jsonEncode(data['usuario']));
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': _extraerError(data, 'Error al iniciar sesión')};
      }
    } catch (e) {
      return {'success': false, 'error': _errorConexion};
    }
  }

  // Login con Google
  static Future<Map<String, dynamic>> loginConGoogle(String idToken) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken}),
          )
          .timeout(_timeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('usuario', jsonEncode(data['usuario']));
        await prefs.remove('isGuest');
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': _extraerError(data, 'Error con Google')};
      }
    } catch (e) {
      return {'success': false, 'error': _errorConexion};
    }
  }

  // Register
  static Future<Map<String, dynamic>> register(String nombre, String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'nombre': nombre, 'email': email, 'password': password}),
          )
          .timeout(_timeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('usuario', jsonEncode(data['usuario']));
        await prefs.remove('isGuest');
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': _extraerError(data, 'Error al registrarse')};
      }
    } catch (e) {
      return {'success': false, 'error': _errorConexion};
    }
  }

  // Entrar como invitado
static Future<void> loginAsGuest() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('isGuest', true);
}

// Verificar si es invitado
static Future<bool> isGuest() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('isGuest') ?? false;
}

// Verificar si es la primera vez que abre la app
  static Future<bool> isFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('firstTime') ?? true;
  }

  // Marcar que ya vio el onboarding
  static Future<void> setFirstTimeDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('firstTime', false);
  }

  // Cerrar sesión
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('usuario');
    await prefs.remove('isGuest');
  }

  // Obtener token guardado
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Verificar si hay sesión activa
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }
}