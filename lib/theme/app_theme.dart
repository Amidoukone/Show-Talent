import 'package:flutter/material.dart';
import 'ad_colors.dart';
import 'ad_typography.dart';

class AppTheme {
  /// Thème clair principal — utilisé dans toute l’application
  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AdColors.brand,
      onPrimary: AdColors.brandOn,
      secondary: AdColors.accent,
      onSecondary: AdColors.surface,
      error: AdColors.error,
      onError: AdColors.white,
      surface: AdColors.surface,
      onSurface: AdColors.onSurface,
      primaryContainer: AdColors.brandVariant,
      onPrimaryContainer: AdColors.surface,
      secondaryContainer: AdColors.accentDark,
      onSecondaryContainer: AdColors.surface,
      surfaceContainerHighest: AdColors.surfaceCardAlt,
      outline: AdColors.divider,
      shadow: Colors.black54,
      scrim: Colors.black54,
      inversePrimary: AdColors.brandOn,

      // Champs supplémentaires pour compatibilité M3
      surfaceBright: AdColors.surfaceAlt,
      surfaceDim: AdColors.surface,
      surfaceContainer: AdColors.surfaceAlt,
      surfaceContainerLow: AdColors.surfaceAlt,
      surfaceContainerHigh: AdColors.surfaceCard,
      tertiary: AdColors.accent,
      onTertiary: AdColors.surface,
      tertiaryContainer: AdColors.accentDark,
      onTertiaryContainer: AdColors.surface,
      inverseSurface: AdColors.surfaceAlt,
      onInverseSurface: AdColors.onSurface,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AdColors.divider, width: 1),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AdColors.surface,
      textTheme: adTextTheme,
      canvasColor: AdColors.surface,

      // --- AppBar ---
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AdColors.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AdColors.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: AdColors.onSurface),
      ),

      // --- Boutons ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdColors.brand,
          foregroundColor: AdColors.brandOn,
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

      // --- Champs de texte (InputDecoration) ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdColors.surfaceCard,
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
        labelStyle: const TextStyle(color: AdColors.onSurfaceMuted),
        // ✅ Remplacement withOpacity → withValues(alpha: 0.6)
        hintStyle: TextStyle(
          color: AdColors.onSurfaceMuted.withValues(alpha: 0.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),

      // --- Barre de navigation ---
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AdColors.surfaceAlt,
        selectedItemColor: AdColors.brand,
        unselectedItemColor: AdColors.onSurfaceMuted,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        type: BottomNavigationBarType.fixed,
      ),

      dividerColor: AdColors.divider,

      // --- SnackBars ---
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AdColors.surfaceCard,
        contentTextStyle: TextStyle(
          color: AdColors.onSurface,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // --- Cartes ---
      cardTheme: CardThemeData(
        color: AdColors.surfaceCard,
        surfaceTintColor: Colors.transparent, // évite la sur-teinte M3
        elevation: 6,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AdColors.divider, width: 1),
        ),
        shadowColor: Colors.black.withOpacity(0.35),
      ),

      // --- Indicateurs de chargement ---
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AdColors.brand,
      ),

      // --- Autres ---
      iconTheme: const IconThemeData(color: AdColors.onSurface),
      dividerTheme: const DividerThemeData(
        color: AdColors.divider,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AdColors.onSurface,
        textColor: AdColors.onSurface,
        tileColor: AdColors.surfaceCard,
      ),
    );
  }
}
