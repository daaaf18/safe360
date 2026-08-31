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