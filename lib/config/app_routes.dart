import 'package:get/get.dart';

import 'app_page_bindings.dart';
import '../screens/login_screen.dart';
import '../screens/main_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/verify_email_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String main = '/main';
  static const String verifyEmail = '/verify';
  static const String resetPassword = '/reset';

  static final List<GetPage<dynamic>> pages = <GetPage<dynamic>>[
    GetPage(name: splash, page: () => const SplashScreen()),
    GetPage(name: login, page: () => const LoginScreen()),
    GetPage(
      name: main,
      page: () => const MainScreen(),
      binding: MainShellBinding(),
    ),
    GetPage(name: verifyEmail, page: () => const VerifyEmailScreen()),
    GetPage(
      name: resetPassword,
      page: () => ResetPasswordScreen(
        oobCode: _resolveResetPasswordCode(),
      ),
    ),
  ];

  static String _resolveResetPasswordCode() {
    final args = Get.arguments;
    if (args is Map) {
      final oobCodeFromArgs = args['oobCode'];
      if (oobCodeFromArgs is String && oobCodeFromArgs.isNotEmpty) {
        return oobCodeFromArgs;
      }
    }

    final params = <String, String>{...Uri.base.queryParameters};
    if (Uri.base.fragment.isNotEmpty) {
      try {
        params.addAll(Uri.splitQueryString(Uri.base.fragment));
      } catch (_) {}
    }

    return params['oobCode'] ?? '';
  }
}
