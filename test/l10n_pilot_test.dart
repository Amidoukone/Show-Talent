import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the ARB -> AppLocalizations pipeline end to end for the login
/// screen pilot: both locales resolve, the French template is not silently
/// used as an English fallback, and the one parameterized string substitutes
/// its placeholder correctly in each language.
void main() {
  Future<AppLocalizations> resolve(
    WidgetTester tester,
    Locale locale,
  ) async {
    late AppLocalizations resolved;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            resolved = AppLocalizations.of(context)!;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return resolved;
  }

  testWidgets('French resolves to the template strings', (tester) async {
    final l10n = await resolve(tester, const Locale('fr'));

    expect(l10n.loginScreenTitle, 'Connectez-vous');
    expect(l10n.loginSubmit, 'Se connecter');
    expect(
      l10n.resetPasswordEmailSentMessage('joueur@example.com'),
      'Lien de réinitialisation envoyé à joueur@example.com. '
      'Pensez à vérifier vos spams si vous ne le voyez pas.',
    );
  });

  testWidgets('English resolves to real translations, not the French '
      'fallback', (tester) async {
    final l10n = await resolve(tester, const Locale('en'));

    expect(l10n.loginScreenTitle, 'Sign in');
    expect(l10n.loginSubmit, 'Sign in');
    expect(l10n.loginScreenSubtitle, isNot('Ravi de vous revoir !'));
    expect(
      l10n.resetPasswordEmailSentMessage('player@example.com'),
      "Reset link sent to player@example.com. Check your spam folder if "
      "you don't see it.",
    );
  });
}
