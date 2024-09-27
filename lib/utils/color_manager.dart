import 'package:flutter/material.dart';

class ColorManager {
  static Color primaryColor = HexColor.fromHex('#010205'); // Couleur primaire (noir profond)
  static Color secondaryColor = HexColor.fromHex('#540f11'); // Couleur secondaire (rouge sombre)
  static Color white = HexColor.fromHex('#ffffff'); // Blanc
  static Color grey = HexColor.fromHex('#989c98'); // Gris
  static Color red = HexColor.fromHex('#bf0f02'); // Rouge vif
}

extension HexColor on Color {
  static Color fromHex(String hexColorString) {
    hexColorString = hexColorString.replaceAll('#', '');
    if (hexColorString.length == 6) {
      hexColorString = 'FF$hexColorString'; // Ajout d'opacité par défaut (FF)
    }
    return Color(int.parse(hexColorString, radix: 16));
  }
}
