import 'package:flutter/material.dart';

const kNavyDark = Color(0xFF0D1B35);
const kNavyMed = Color(0xFF162440);
const kNavyLight = Color(0xFF1E3056);
const kBlueAccent = Color(0xFF2563EB);
const kBlueDark = Color(0xFF1D4ED8);
const kBgPage = Color(0xFFF1F5F9);
const kTextPrimary = Color(0xFF1E293B);
const kTextSecondary = Color(0xFF64748B);
const kBorderColor = Color(0xFFE2E8F0);
const kSuccessGreen = Color(0xFF16A34A);
const kWarningAmber = Color(0xFFD97706);

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kBlueAccent,
      primary: kBlueAccent,
      surface: Colors.white,
      onSurface: kTextPrimary,
    ),
    scaffoldBackgroundColor: kBgPage,
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kBorderColor),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kBlueAccent,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: kBorderColor),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kBlueAccent, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold, fontSize: 28),
      headlineMedium: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold, fontSize: 22),
      headlineSmall: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w600, fontSize: 18),
      titleLarge: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w600, fontSize: 16),
      titleMedium: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w600, fontSize: 14),
      bodyLarge: TextStyle(color: kTextPrimary, fontSize: 15),
      bodyMedium: TextStyle(color: kTextPrimary, fontSize: 14),
      bodySmall: TextStyle(color: kTextSecondary, fontSize: 12),
      labelSmall: TextStyle(color: kTextSecondary, fontSize: 11),
    ),
    dividerTheme: const DividerThemeData(color: kBorderColor, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: kTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: kTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
