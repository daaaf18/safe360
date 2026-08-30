import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Mapbox ---
  // El token público de Mapbox se pasa en tiempo de build/run con:
  //   flutter run --dart-define-from-file=env.json
  // Ver env.example.json para el formato esperado.
  const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  if (accessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(accessToken);
  } else {
    debugPrint(
      '⚠️  MAPBOX_ACCESS_TOKEN no configurado. El mapa no va a cargar tiles. '
      'Corré la app con --dart-define-from-file=env.json',
    );
  }

  // --- Supabase ---
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const Safe360App());
}

class Safe360App extends StatelessWidget {
  const Safe360App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Safe360',
      debugShowCheckedModeBanner: false,
      theme: buildSafe360Theme(),
      home: const LoginScreen(),
    );
  }
}
