import 'package:adfoot/screens/reset_password_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  testWidgets('shows invalid-link state when reset code is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const GetMaterialApp(
        home: ResetPasswordScreen(oobCode: ''),
      ),
    );

    expect(find.text('Lien invalide'), findsOneWidget);
    expect(find.text('Retour a la connexion'), findsOneWidget);
  });
}
