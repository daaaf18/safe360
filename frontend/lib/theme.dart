import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta de colores de Safe360
class AppColors {
  static const Color background = Color(0xFF121417);
  static const Color surface = Color(0xFF1B1F24);
  static const Color surfaceLight = Color(0xFF262B32);
  static const Color textPrimary = Color(0xFFF2F4F5);
  static const Color textSecondary = Color(0xFFA0A7B0);

  static const Color safe = Color(0xFF1FA98F); // verde-azulado: zona segura
  static const Color warning = Color(0xFFF4C542); // amarillo: riesgo medio
  static const Color danger = Color(0xFFE1483F); // rojo: riesgo alto / SOS
}

/// Tipografía: antes usaba la fuente default de Android (Roboto) sin
/// ningún ajuste — funcional, pero sin ninguna personalidad propia.
/// Overpass tiene herencia de señalética de carretera en EE.UU. (encaja
/// con "navegación segura"), para títulos y números grandes; Public Sans
/// (diseñada para uso gubernamental/cívico, muy legible) para todo el
/// texto de lectura — misma pareja que ya usa la guía de referencia de la
/// app, para que se sienta como la misma marca en los dos lados.
TextStyle _display({double size = 24, FontWeight weight = FontWeight.w800, Color? color}) =>
    GoogleFonts.overpass(fontSize: size, fontWeight: weight, color: color ?? AppColors.textPrimary);

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w400, Color? color}) =>
    GoogleFonts.publicSans(fontSize: size, fontWeight: weight, color: color ?? AppColors.textSecondary);

ThemeData buildSafe360Theme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.safe,
      secondary: AppColors.warning,
      error: AppColors.danger,
      surface: AppColors.surface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      foregroundColor: AppColors.textPrimary,
      centerTitle: true,
      titleTextStyle: _display(size: 19, weight: FontWeight.w700),
    ),
    textTheme: TextTheme(
      displayLarge: _display(size: 34, weight: FontWeight.w800),
      displayMedium: _display(size: 28, weight: FontWeight.w800),
      headlineLarge: _display(size: 26, weight: FontWeight.w800),
      headlineMedium: _display(size: 24, weight: FontWeight.w700),
      headlineSmall: _display(size: 20, weight: FontWeight.w700),
      titleLarge: _display(size: 18, weight: FontWeight.w700),
      titleMedium: _display(size: 16, weight: FontWeight.w600),
      titleSmall: _display(size: 14, weight: FontWeight.w600),
      bodyLarge: _body(size: 16, color: AppColors.textPrimary),
      bodyMedium: _body(size: 14, color: AppColors.textSecondary),
      bodySmall: _body(size: 12, color: AppColors.textSecondary),
      labelLarge: _body(size: 15, weight: FontWeight.w600, color: AppColors.textPrimary),
      labelMedium: _body(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary),
      labelSmall: _body(size: 11, weight: FontWeight.w600, color: AppColors.textSecondary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      hintStyle: _body(color: AppColors.textSecondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.safe,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: GoogleFonts.publicSans(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        textStyle: GoogleFonts.publicSans(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: GoogleFonts.publicSans(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.safe,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      selectedLabelStyle: GoogleFonts.publicSans(fontWeight: FontWeight.w600, fontSize: 11),
      unselectedLabelStyle: GoogleFonts.publicSans(fontWeight: FontWeight.w500, fontSize: 11),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    // Material 3 (useMaterial3: true arriba) ya trae de fábrica una
    // transición de página tipo zoom bastante pulida — no hace falta
    // pisarla a mano.
  );
}
