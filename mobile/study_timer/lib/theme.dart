import 'package:flutter/material.dart';

const kHeader = Color(0xFF4F46E5); // indigo (en-têtes)
const kPrimary = Color(0xFF4F46E5); // indigo (boutons)
const kDark = Color(0xFF312E81); // indigo foncé (accueil, bannières)
const kYellow = Color(0xFFFBBF24); // ambre (bouton « Commencer »)
const kCoral = Color(0xFFFB7185); // corail (tuile active)
const kIndigo = Color(0xFF7C3AED); // violet
const kPeach = Color(0xFF10B981); // émeraude

ThemeData buildTheme(Brightness b) {
  final light = b == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: b,
  ).copyWith(primary: light ? kPrimary : const Color(0xFFA5B4FC));
  final surface = light ? Colors.white : const Color(0xFF1A1A2E);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: light
        ? const Color(0xFFF5F5FB)
        : const Color(0xFF0F0F1A),
    appBarTheme: const AppBarTheme(
      backgroundColor: kHeader,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      centerTitle: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? const Color(0xFFEEEEF8) : const Color(0xFF26263F),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: light ? Colors.white : Colors.black87,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    bottomAppBarTheme: BottomAppBarThemeData(color: surface, elevation: 8),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: scheme.primaryContainer,
    ),
  );
}
