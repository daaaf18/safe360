import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets/safe360_map.dart';
import '../services/location_service.dart';
import 'mapa_completo_screen.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _category = 'Robo';
  final _descController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  // --- Evidencia (foto/video) ---
  final _picker = ImagePicker();
  final _supabase = Supabase.instance.client;
  XFile? _pickedFile;
  bool _isVideo = false;
  bool _uploadingEvidencia = false;
  String? _evidenciaUrl;

  final _categories = const [
    ('Robo', Icons.warning_amber_rounded, AppColors.danger),
    ('Acoso', Icons.report_problem_outlined, AppColors.danger),
    ('Poca iluminación', Icons.lightbulb_outline, AppColors.warning),
    ('Accidente vial', Icons.car_crash_outlined, Colors.purpleAccent),
    ('Otro', Icons.more_horiz, AppColors.textSecondary),
  ];

  // Centro de Puebla como fallback si no hay permiso de ubicación, el GPS
  // está apagado, o el dispositivo no reporta posición (p. ej. emulador sin
  // ubicación simulada). Se reemplaza por la ubicación real en initState.
  double _latitud = 19.0414;
  double _longitud = -98.2063;
  bool _ubicacionEsReal = false;
  String? _errorUbicacion;

  @override
  void initState() {
    super.initState();
    _obtenerUbicacion();
  }

  Future<void> _obtenerUbicacion() async {
    final resultado = await LocationService.obtenerUbicacionActual();
    if (!mounted) return;
    if (resultado.exito) {
      setState(() {
        _latitud = resultado.posicion!.latitude;
        _longitud = resultado.posicion!.longitude;
        _ubicacionEsReal = true;
        _errorUbicacion = null;
      });
    } else {
      setState(() => _errorUbicacion = resultado.mensajeError);
    }
  }

  Future<void> _mostrarOpcionesEvidencia() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: AppColors.textPrimary),
                title: const Text('Tomar foto', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _seleccionarArchivo(esVideo: false, source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
                title: const Text('Elegir foto de galería', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _seleccionarArchivo(esVideo: false, source: ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined, color: AppColors.textPrimary),
                title: const Text('Grabar video', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _seleccionarArchivo(esVideo: true, source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined, color: AppColors.textPrimary),
                title: const Text('Elegir video de galería', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _seleccionarArchivo(esVideo: true, source: ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _seleccionarArchivo({required bool esVideo, required ImageSource source}) async {
    final XFile? file = esVideo
        ? await _picker.pickVideo(source: source)
        : await _picker.pickImage(source: source, imageQuality: 80);

    if (file == null) return;

    setState(() {
      _pickedFile = file;
      _isVideo = esVideo;
      _error = null;
    });

    await _subirEvidencia(file, esVideo);
  }

  Future<void> _subirEvidencia(XFile file, bool esVideo) async {
    setState(() {
      _uploadingEvidencia = true;
      _error = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last;
      final nombreArchivo =
          '${DateTime.now().millisecondsSinceEpoch}_${file.name}'.replaceAll(' ', '_');
      final path = 'reportes/$nombreArchivo';

      await _supabase.storage.from('evidencias').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: esVideo ? 'video/$ext' : 'image/$ext',
              upsert: false,
            ),
          );

      final publicUrl = _supabase.storage.from('evidencias').getPublicUrl(path);

      setState(() {
        _evidenciaUrl = publicUrl;
        _uploadingEvidencia = false;
      });
    } catch (e) {
      setState(() {
        _uploadingEvidencia = false;
        _error = 'No se pudo subir la evidencia';
        _pickedFile = null;
      });
    }
  }

  void _quitarEvidencia() {
    setState(() {
      _pickedFile = null;
      _evidenciaUrl = null;
    });
  }

  Future<void> _enviarReporte() async {
    if (_descController.text.trim().isEmpty) {
      setState(() => _error = 'Agrega una descripción al reporte');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() {
          _loading = false;
          _error = 'Debes iniciar sesión para reportar';
        });
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/reportes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'categoria': _category,
          'descripcion': _descController.text.trim(),
          'latitud': _latitud,
          'longitud': _longitud,
          'evidencia_url': _evidenciaUrl,
        }),
      );

      setState(() => _loading = false);

      if (response.statusCode == 201) {
        setState(() {
          _success = '¡Reporte enviado correctamente!';
          _descController.clear();
          _category = 'Robo';
          _pickedFile = null;
          _evidenciaUrl = null;
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() => _error = data['error'] ?? 'Error al enviar el reporte');
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error de conexión con el servidor';
      });
    }
  }

  Widget _buildEvidenciaBox() {
    if (_pickedFile == null) {
      return OutlinedButton.icon(
        onPressed: _mostrarOpcionesEvidencia,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Adjuntar foto o video'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.surfaceLight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _isVideo
                ? Container(
                    width: 48,
                    height: 48,
                    color: Colors.black26,
                    child: const Icon(Icons.videocam, color: Colors.white70),
                  )
                : Image.file(File(_pickedFile!.path), width: 48, height: 48, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _uploadingEvidencia ? 'Subiendo evidencia...' : 'Evidencia lista para enviar',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          if (_uploadingEvidencia)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
              onPressed: _quitarEvidencia,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('Reportar incidente'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Center(
            child: Text('Tu reporte nos ayuda a mantener la comunidad segura',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          const SizedBox(height: 20),
          const Text('1. Categoría del incidente',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: _categories.map((c) {
              final selected = _category == c.$1;
              return GestureDetector(
                onTap: () => setState(() => _category = c.$1),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? c.$3.withOpacity(0.12) : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: selected ? c.$3 : Colors.transparent, width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(c.$2, color: c.$3, size: 22),
                      const SizedBox(height: 6),
                      Text(c.$1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),
          const Text('2. Describe lo que pasó',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _descController,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Describe brevemente lo que pasó, cuándo ocurrió, si hay involucrados, etc.',
              counterStyle: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 18),
          const Text('3. Agrega evidencia (opcional)',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _buildEvidenciaBox(),
          const SizedBox(height: 8),
          Row(children: const [
            Icon(Icons.lock_outline, size: 13, color: AppColors.textSecondary),
            SizedBox(width: 6),
            Text('Tu identidad se mantendrá anónima',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ]),
          const SizedBox(height: 22),
          const Text('4. Ubicación del incidente',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          GestureDetector(
            // El preview chiquito solo da una idea del punto; tocarlo abre
            // el mapa completo para poder verlo bien y confirmar que es el
            // lugar correcto.
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MapaCompletoScreen(
                titulo: 'Ubicación del incidente',
                centerLat: _latitud,
                centerLon: _longitud,
                reportes: [
                  {
                    'latitud': _latitud,
                    'longitud': _longitud,
                    'categoria': _category,
                    'estado': 'pendiente',
                  },
                ],
              ),
            )),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 150,
                    child: IgnorePointer(
                      // Solo vista previa: el punto es fijo
                      // (centerLat/centerLon), no permitimos mover el mapa
                      // desde este preview chiquito. Le mandamos un
                      // "reporte" sintético para que se vea el pin exacto
                      // del incidente, coloreado según la categoría elegida.
                      child: Safe360Map(
                        centerLat: _latitud,
                        centerLon: _longitud,
                        reportes: [
                          {
                            'latitud': _latitud,
                            'longitud': _longitud,
                            'categoria': _category,
                            'estado': 'pendiente',
                          },
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen, size: 14, color: AppColors.textPrimary),
                        SizedBox(width: 4),
                        Text('Ver completo',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_ubicacionEsReal) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.warning.withOpacity(0.9)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_errorUbicacion ?? "No se pudo obtener tu ubicación real."} '
                  'El reporte se enviará con una ubicación aproximada del centro de Puebla.',
                  style: const TextStyle(color: AppColors.warning, fontSize: 11),
                ),
              ),
              TextButton(
                onPressed: _obtenerUbicacion,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Reintentar', style: TextStyle(fontSize: 11)),
              ),
            ]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            Text(
              _success!,
              style: const TextStyle(color: AppColors.safe, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 26),
          ElevatedButton(
            onPressed: (_loading || _uploadingEvidencia) ? null : _enviarReporte,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Enviar reporte'),
          ),
        ],
      ),
    );
  }
}