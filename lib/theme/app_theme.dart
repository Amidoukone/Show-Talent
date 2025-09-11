import 'package:flutter/material.dart';
import 'ad_colors.dart';
import 'ad_typography.dart';

class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AdColors.brand,
      onPrimary: AdColors.white,
      secondary: AdColors.accent,
      onSecondary: AdColors.white,
      error: AdColors.error,
      onError: AdColors.white,
      surface: AdColors.white,
      onSurface: AdColors.onSurface,
      primaryContainer: AdColors.brandVariant,
      onPrimaryContainer: AdColors.brandOn,
      secondaryContainer: AdColors.accentDark,
      onSecondaryContainer: AdColors.white,
      surfaceContainerHighest: AdColors.surfaceAlt,
      outline: AdColors.divider,
      shadow: Colors.black12,
      scrim: Colors.black54,
      inversePrimary: AdColors.brandOn,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AdColors.divider, width: 1),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AdColors.surface,
      textTheme: adTextTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AdColors.brand,
        foregroundColor: AdColors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AdColors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: AdColors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdColors.brand,
          foregroundColor: AdColors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AdColors.brand,
          side: const BorderSide(color: AdColors.brand, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AdColors.brand,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdColors.white,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AdColors.brand, width: 1.2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AdColors.error, width: 1.2),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AdColors.error, width: 1.2),
        ),
        labelStyle: const TextStyle(color: AdColors.brand),
        hintStyle: TextStyle(color: AdColors.onSurface.withOpacity(.6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AdColors.brand,
        selectedItemColor: AdColors.white,
        unselectedItemColor: Colors.white70,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
        type: BottomNavigationBarType.fixed,
      ),
      dividerColor: AdColors.divider,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AdColors.brand,
        contentTextStyle: TextStyle(color: AdColors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      // ✅ Corrigé : ThemeData.cardTheme attend un CardThemeData
      cardTheme: CardThemeData(
        color: AdColors.white,
        surfaceTintColor: Colors.transparent, // évite la sur-teinte M3
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AdColors.brand,
      ),
    );
  }
}
