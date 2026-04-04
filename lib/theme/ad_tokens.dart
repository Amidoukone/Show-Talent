import 'package:flutter/material.dart';

class AdSpacing {
  const AdSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

class AdRadius {
  const AdRadius._();

  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

class AdElevation {
  const AdElevation._();

  static const double flat = 0;
  static const double low = 2;
  static const double medium = 6;
  static const double high = 12;
}

class AdMotion {
  const AdMotion._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
}

class AdShadows {
  const AdShadows._();

  static List<BoxShadow> card(Color color) {
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: 0.28),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
