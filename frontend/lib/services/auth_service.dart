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

  // Login con email y contraseña
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      await prefs.setString('usuario', jsonEncode(data['usuario']));
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': _extraerError(data, 'Error al iniciar sesión')};
    }
  }

  // Login con Google
  static Future<Map<String, dynamic>> loginConGoogle(String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      await prefs.setString('usuario', jsonEncode(data['usuario']));
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': _extraerError(data, 'Error con Google')};
    }
  }

  // Register
  static Future<Map<String, dynamic>> register(String nombre, String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nombre': nombre, 'email': email, 'password': password}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      await prefs.setString('usuario', jsonEncode(data['usuario']));
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': _extraerError(data, 'Error al registrarse')};
    }
  }

  // Cerrar sesión
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('usuario');
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