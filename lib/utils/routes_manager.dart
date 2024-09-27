import 'package:get/get.dart';

class Layout {
  static double getScreenHeight() {
    return Get.height; // Renvoie la hauteur totale de l'écran
  }

  static double getScreenWidth() {
    return Get.width; // Renvoie la largeur totale de l'écran
  }

  static double getHeight(double pixels) {
    double x = getScreenHeight() / pixels;
    return getScreenHeight() / x; // Renvoie une hauteur relative
  }

  static double getWidth(double pixels) {
    double x = getScreenWidth() / pixels;
    return getScreenWidth() / x; // Renvoie une largeur relative
  }
}
