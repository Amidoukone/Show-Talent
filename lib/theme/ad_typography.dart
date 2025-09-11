import 'package:flutter/material.dart';
import 'ad_colors.dart';

TextTheme adTextTheme = const TextTheme(
  displayLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w700),
  displayMedium: TextStyle(fontSize: 40, fontWeight: FontWeight.w700),
  headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
  headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
  titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
  titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  titleSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
  bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
).apply(
  bodyColor: AdColors.onSurface,
  displayColor: AdColors.onSurface,
);
