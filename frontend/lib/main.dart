import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Mapbox ---
  // En Flutter Web (modo debug/DDC), mapbox_maps_flutter truena al llamar
  // setAccessToken (usa bool.fromEnvironment fuera de un const constructor
  // en su logging interno). Se omite en web hasta que el paquete lo soporte.
  const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  if (!kIsWeb && accessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(accessToken);
  } else if (accessToken.isEmpty) {
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

  // --- Verificar si es primera vez ---
  final esFirstTime = await AuthService.isFirstTime();

  runApp(Safe360App(mostrarOnboarding: esFirstTime));
}

class Safe360App extends StatelessWidget {
  final bool mostrarOnboarding;
  const Safe360App({super.key, required this.mostrarOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Safe360',
      debugShowCheckedModeBanner: false,
      theme: buildSafe360Theme(),
      home: mostrarOnboarding ? const OnboardingScreen() : const LoginScreen(),
    );
  }
}