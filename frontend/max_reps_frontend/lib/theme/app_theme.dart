import 'package:flutter/material.dart';

abstract final class AppColors {
  static const aqua = Color(0xFF008E97);
  static const deepAqua = Color(0xFF00656D);
  static const orange = Color(0xFFF58220);
  static const ink = Color(0xFF102F3B);
  static const muted = Color(0xFF536C76);
  static const background = Color(0xFFF3F8F9);
  static const line = Color(0xFFDCE8EB);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.aqua).copyWith(
    primary: AppColors.deepAqua,
    onPrimary: Colors.white,
    secondary: AppColors.orange,
    onSecondary: AppColors.ink,
    surface: Colors.white,
    onSurface: AppColors.ink,
    error: const Color(0xFFB42318),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme
        .copyWith(
          headlineLarge: const TextStyle(
            fontSize: 36,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
          headlineMedium: const TextStyle(
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
          headlineSmall: const TextStyle(
            fontSize: 25,
            height: 1.25,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
          titleLarge: const TextStyle(
            fontSize: 21,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            height: 1.5,
            color: AppColors.ink,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.muted,
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        )
        .apply(fontFamily: 'Roboto'),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 76,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.aqua, width: 2),
      ),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.orange,
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, 52),
        shape: rounded,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: rounded,
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: rounded,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: rounded,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
