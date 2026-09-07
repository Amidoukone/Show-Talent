import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the ARB -> AppLocalizations pipeline end to end for each screen
/// migrated so far (login, signup, verify email, reset password, terms
/// acceptance, main navigation shell, settings, profile): both locales
/// resolve, the French template is not silently used as an English
/// fallback, and parameterized strings substitute their placeholder
/// correctly in each language.
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
    expect(l10n.signupTitle, 'Obtenir un accès');
    expect(
      l10n.signupRolesCardMessage('joueur, fan, club'),
      'Tous les comptes sont provisionnés dans le portail admin : '
      'joueur, fan, club.',
    );
    expect(
      l10n.verifyEmailAddressLine('joueur@example.com'),
      'Adresse : joueur@example.com',
    );
    expect(l10n.commonBackToLogin, 'Retour à la connexion');
    expect(
      l10n.newPasswordAccountLabel('joueur@example.com'),
      'Compte : joueur@example.com',
    );
    expect(
      l10n.termsVersionWithDateLabel('1.0', '1 septembre 2026'),
      'Version 1.0 — en vigueur au 1 septembre 2026',
    );
    expect(
      l10n.termsOpenFailureMessage('https://adfoot.org/legal/terms.html'),
      'Impossible d’ouvrir le document. '
      'Adresse : https://adfoot.org/legal/terms.html',
    );
    expect(l10n.mainNavCareerLabel, 'Carrière');
    expect(l10n.commonRetry, 'Réessayer');
    expect(
      l10n.settingsAcceptedVersionLabel('2.1'),
      'Version 2.1, acceptée',
    );
    expect(
      l10n.settingsContactTeamSubtitle('+225 00 00 00 00'),
      'Ouvrir WhatsApp : +225 00 00 00 00',
    );
    expect(
      l10n.settingsSupportNoticeMessage('adfoot.org', '+225 00 00 00 00'),
      'Faites vérifier toute opportunité via adfoot.org ou WhatsApp : '
      '+225 00 00 00 00.',
    );
    expect(l10n.profileRoleFan, 'Supporter');
    expect(
      l10n.profileStatsAttestedWithDateMessage('12/03/2026'),
      'Chiffres attestés par Adfoot le 12/03/2026',
    );
    expect(
      l10n.profileSeasonSummaryAppearances(28),
      '28 matchs',
    );
    expect(l10n.profileSeasonSummaryGoals(11), '11 buts');
    expect(l10n.profileCtaCompleteButton, 'Compléter');
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
    expect(l10n.signupTitle, isNot('Obtenir un accès'));
    expect(
      l10n.signupRolesCardMessage('joueur, fan, club'),
      'All accounts are provisioned in the admin portal: '
      'joueur, fan, club.',
    );
    expect(
      l10n.verifyEmailAddressLine('player@example.com'),
      'Address: player@example.com',
    );
    expect(l10n.commonBackToLogin, isNot('Retour à la connexion'));
    expect(
      l10n.newPasswordAccountLabel('player@example.com'),
      'Account: player@example.com',
    );
    expect(
      l10n.termsVersionWithDateLabel('1.0', 'September 1, 2026'),
      'Version 1.0 — effective September 1, 2026',
    );
    expect(
      l10n.termsOpenFailureMessage('https://adfoot.org/legal/terms.html'),
      "Couldn't open the document. "
      'Address: https://adfoot.org/legal/terms.html',
    );
    expect(l10n.mainNavCareerLabel, isNot('Carrière'));
    expect(l10n.commonRetry, 'Retry');
    expect(
      l10n.settingsAcceptedVersionLabel('2.1'),
      'Version 2.1, accepted',
    );
    expect(
      l10n.settingsContactTeamSubtitle('+225 00 00 00 00'),
      'Open WhatsApp: +225 00 00 00 00',
    );
    expect(
      l10n.settingsSupportNoticeMessage('adfoot.org', '+225 00 00 00 00'),
      'Have any opportunity checked via adfoot.org or WhatsApp: '
      '+225 00 00 00 00.',
    );
    expect(l10n.profileRoleFan, 'Fan');
    expect(
      l10n.profileStatsAttestedWithDateMessage('03/12/2026'),
      'Stats verified by Adfoot on 03/12/2026',
    );
    expect(
      l10n.profileSeasonSummaryAppearances(28),
      '28 matches',
    );
    expect(l10n.profileSeasonSummaryGoals(11), '11 goals');
    expect(l10n.profileCtaCompleteButton, 'Complete');
  });
}
