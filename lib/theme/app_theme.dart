import 'package:flutter/material.dart';

import 'ad_colors.dart';
import 'ad_tokens.dart';
import 'ad_typography.dart';

class AppTheme {
  /// Thème principal Adfoot (dark-first, Material 3).
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
      surfaceBright: AdColors.surfaceAlt,
      surfaceDim: AdColors.surface,
      surfaceContainer: AdColors.surfaceAlt,
      surfaceContainerLow: AdColors.surfaceAlt,
      surfaceContainerHigh: AdColors.surfaceCard,
      tertiary: AdColors.info,
      onTertiary: AdColors.surface,
      tertiaryContainer: AdColors.surfaceCardAlt,
      onTertiaryContainer: AdColors.onSurface,
      inverseSurface: AdColors.surfaceAlt,
      onInverseSurface: AdColors.onSurface,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AdRadius.md),
      borderSide: const BorderSide(color: AdColors.divider, width: 1),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AdColors.surface,
      textTheme: buildAdTextTheme(),
      canvasColor: AdColors.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AdColors.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AdColors.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
        ),
        iconTheme: IconThemeData(color: AdColors.onSurface),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdColors.brand,
          foregroundColor: AdColors.brandOn,
          disabledBackgroundColor: AdColors.disabled,
          disabledForegroundColor: AdColors.surfaceCard,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(
            vertical: AdSpacing.sm,
            horizontal: AdSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AdRadius.md),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          elevation: AdElevation.flat,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AdColors.brand.withValues(alpha: 0.15),
          foregroundColor: AdColors.brand,
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AdRadius.md),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AdColors.brand,
          side: const BorderSide(color: AdColors.brand, width: 1.2),
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(
            vertical: AdSpacing.sm,
            horizontal: AdSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AdRadius.md),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AdColors.brand,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AdColors.surfaceCard,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AdColors.brand, width: 1.3),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AdColors.error, width: 1.3),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AdColors.error, width: 1.3),
        ),
        labelStyle: const TextStyle(color: AdColors.onSurfaceMuted),
        hintStyle: TextStyle(
          color: AdColors.onSurfaceMuted.withValues(alpha: 0.8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AdSpacing.md,
          vertical: AdSpacing.sm,
        ),
      ),
      cardTheme: CardThemeData(
        color: AdColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: AdElevation.medium,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdRadius.lg),
          side: const BorderSide(color: AdColors.divider, width: 1),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.35),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AdColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdRadius.lg),
          side: const BorderSide(color: AdColors.divider, width: 1),
        ),
        titleTextStyle: const TextStyle(
          color: AdColors.onSurface,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
        contentTextStyle: const TextStyle(
          color: AdColors.onSurface,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AdColors.surfaceCardAlt,
        contentTextStyle: const TextStyle(
          color: AdColors.onSurface,
          fontWeight: FontWeight.w600,
        ),
        showCloseIcon: true,
        closeIconColor: AdColors.onSurfaceMuted,
        actionTextColor: AdColors.brand,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdRadius.md),
          side: const BorderSide(color: AdColors.divider),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AdColors.brand,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AdColors.surfaceAlt,
        selectedItemColor: AdColors.brand,
        unselectedItemColor: AdColors.onSurfaceMuted,
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AdColors.brand,
        foregroundColor: AdColors.brandOn,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AdColors.surfaceCard,
        selectedColor: AdColors.brand.withValues(alpha: 0.18),
        disabledColor: AdColors.disabled.withValues(alpha: 0.2),
        labelStyle: const TextStyle(
          color: AdColors.onSurface,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AdColors.brand,
          fontWeight: FontWeight.w700,
        ),
        side: const BorderSide(color: AdColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdRadius.pill),
        ),
      ),
      iconTheme: const IconThemeData(color: AdColors.onSurface),
      dividerColor: AdColors.divider,
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
