import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  static const String baseUrl = 'http://10.0.2.2:3000';

  List<dynamic> _contactos = [];
  bool _loading = true;
  int? _userId;
  String? _token;

  @override
  void initState() {
    super.initState();
    _cargarContactos();
  }

  Future<void> _cargarContactos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      final usuarioStr = prefs.getString('usuario');

      if (_token == null || usuarioStr == null) {
        setState(() => _loading = false);
        return;
      }

      final usuario = jsonDecode(usuarioStr);
      _userId = usuario['id'];

      final response = await http.get(
        Uri.parse('$baseUrl/users/$_userId/contactos'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _contactos = jsonDecode(response.body);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _agregarContacto(String nombre, String telefono, String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/$_userId/contactos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'nombre': nombre,
          'telefono': telefono,
          'email': email,
        }),
      );

      if (response.statusCode == 201) {
        _cargarContactos();
      }
    } catch (e) {
      // Error silencioso por ahora
    }
  }

  Future<void> _eliminarContacto(int contactoId) async {
    try {
      await http.delete(
        Uri.parse('$baseUrl/users/$_userId/contactos/$contactoId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      _cargarContactos();
    } catch (e) {
      // Error silencioso
    }
  }

  void _mostrarFormulario() {
    final nombreCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Agregar contacto',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nombreCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: telefonoCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Teléfono'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Email (opcional)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (nombreCtrl.text.isNotEmpty && telefonoCtrl.text.isNotEmpty) {
                  _agregarContacto(
                    nombreCtrl.text.trim(),
                    telefonoCtrl.text.trim(),
                    emailCtrl.text.trim(),
                  );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Guardar contacto'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contactos de confianza')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.safe,
        onPressed: _mostrarFormulario,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contactos.isEmpty
              ? const Center(
                  child: Text(
                    'No tienes contactos de confianza.\nAgrega uno con el botón +',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _contactos.length,
                  itemBuilder: (context, i) {
                    final c = _contactos[i];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(
                          c['nombre'] ?? '',
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                        subtitle: Text(
                          c['telefono'] ?? '',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          onPressed: () => _eliminarContacto(c['id']),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}