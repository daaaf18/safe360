import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Cambia esta IP por la de tu computadora cuando pruebes en emulador
  static const String baseUrl = 'http://localhost:3000';

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
      return {'success': false, 'error': data['error'] ?? 'Error al iniciar sesión'};
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
      return {'success': false, 'error': data['error'] ?? 'Error con Google'};
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
      return {'success': false, 'error': data['error'] ?? 'Error al registrarse'};
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