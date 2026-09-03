import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_contacts/flutter_contacts.dart';
import '../config.dart';
import '../theme.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  // baseUrl centralizado en config.dart

  List<dynamic> _contactosConfianza = [];
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
        Uri.parse('${ApiConfig.baseUrl}/users/$_userId/contactos'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _contactosConfianza = jsonDecode(response.body);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // El backend exige teléfono de EXACTAMENTE 10 dígitos y nombre solo con
  // letras/espacios (ver validarContacto en validacion.middleware.js). Los
  // contactos reales del celular casi nunca vienen así: traen lada "+52",
  // espacios, guiones, paréntesis, y el nombre puede traer apellidos con
  // símbolos raros, emojis, etc. Antes se mandaban tal cual, el backend
  // los rechazaba con 400, y como el catch no mostraba nada, parecía que
  // "elegir un contacto no hacía nada". Esto los normaliza antes de
  // mandarlos.
  String _soloDigitos(String texto) => texto.replaceAll(RegExp(r'\D'), '');

  /// Últimos 10 dígitos del número (quita lada de país tipo 52/521 que
  /// antepone el celular a los contactos mexicanos).
  String _telefonoA10Digitos(String telefono) {
    final digitos = _soloDigitos(telefono);
    if (digitos.length <= 10) return digitos;
    return digitos.substring(digitos.length - 10);
  }

  String _nombreValido(String nombre) {
    final limpio = nombre
        .replaceAll(RegExp(r'[^a-zA-ZáéíóúÁÉÍÓÚñÑ\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return limpio.isEmpty ? 'Contacto' : limpio;
  }

  Future<void> _agregarContacto(String nombre, String telefono, String email) async {
    final telefonoLimpio = _telefonoA10Digitos(telefono);
    if (telefonoLimpio.length != 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            'No se pudo agregar a $nombre: su número ($telefono) no tiene un '
            'formato reconocible.')));
      }
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/users/$_userId/contactos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'nombre': _nombreValido(nombre),
          'telefono': telefonoLimpio,
          if (email.isNotEmpty) 'email': email,
        }),
      );

      if (response.statusCode == 201) {
        _cargarContactos();
      } else if (mounted) {
        String detalle = 'Intenta de nuevo.';
        try {
          final data = jsonDecode(response.body);
          final errores = data['errores'] as List?;
          if (errores != null && errores.isNotEmpty) {
            detalle = errores.map((e) => e['msg']).join(', ');
          } else if (data['error'] != null) {
            detalle = data['error'];
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo agregar a $nombre: $detalle')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo agregar a $nombre: sin conexión con el servidor.')),
        );
      }
    }
  }

  Future<void> _eliminarContacto(int contactoId) async {
    try {
      await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/users/$_userId/contactos/$contactoId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      _cargarContactos();
    } catch (e) {
      // Error silencioso
    }
  }

  Future<void> _seleccionarDeContactos() async {
    // Pedir permiso
    final permiso =
        await FlutterContacts.permissions.request(PermissionType.read);
    if (permiso != PermissionStatus.granted &&
        permiso != PermissionStatus.limited) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso de contactos denegado')),
        );
      }
      return;
    }

    // Obtener contactos del dispositivo
    final contactos = await FlutterContacts.getAll(
      properties: {ContactProperty.phone, ContactProperty.email},
    );

    if (!mounted) return;

    // Mostrar lista de contactos del celular
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Selecciona un contacto',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: contactos.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay contactos en tu dispositivo',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: contactos.length,
                      itemBuilder: (_, i) {
                        final c = contactos[i];
                        final telefono = c.phones.isNotEmpty
                            ? c.phones.first.number
                            : '';
                        final email = c.emails.isNotEmpty
                            ? c.emails.first.address
                            : '';

                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.surface,
                            child: Icon(Icons.person, color: AppColors.textSecondary),
                          ),
                          title: Text(
                            c.displayName ?? '',
                            style: const TextStyle(color: AppColors.textPrimary),
                          ),
                          subtitle: Text(
                            telefono,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          onTap: telefono.isNotEmpty
                              ? () {
                                  Navigator.pop(ctx);
                                  _agregarContacto(
                                    c.displayName ?? '',
                                    telefono,
                                    email,
                                  );
                                }
                              : null,
                        );
                      },
                    ),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.safe,
        onPressed: _seleccionarDeContactos,
        icon: const Icon(Icons.contacts, color: Colors.white),
        label: const Text('Agregar', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contactosConfianza.isEmpty
              ? const Center(
                  child: Text(
                    'No tienes contactos de confianza.\nToca "Agregar" para seleccionar de tus contactos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _contactosConfianza.length,
                  itemBuilder: (context, i) {
                    final c = _contactosConfianza[i];
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
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.danger),
                          onPressed: () => _eliminarContacto(c['id']),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}