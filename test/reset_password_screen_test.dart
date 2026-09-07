import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/screens/reset_password_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  testWidgets('shows invalid-link state when reset code is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        // Pinned, like lib/main.dart pins the real app to French: the test
        // host's default locale is not guaranteed to be French, and this
        // test asserts literal French strings.
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResetPasswordScreen(oobCode: ''),
      ),
    );

    expect(find.text('Lien invalide'), findsOneWidget);
    expect(find.text('Retour à la connexion'), findsOneWidget);
  });
}
