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
    expect(
      l10n.opportunitiesSubtitleWithPlayers,
      'Offres, événements et joueurs',
    );
    expect(
      l10n.talentSearchResultsCountMany(60),
      '60 joueurs — affinez pour voir au-delà',
    );
    expect(l10n.talentSearchResultsCountOther(3), '3 joueurs');
    expect(l10n.followListEmptyFollowersMessage, 'Aucun abonné pour l’instant.');
    expect(l10n.selectUserTitle, 'Nouvelle conversation');
    expect(
      l10n.conversationsDeleteFailedMessage('network error'),
      'Impossible de supprimer la conversation : network error',
    );
    expect(l10n.chatSubtitle, 'Messagerie Adfoot');
    expect(
      l10n.chatEmptyStateMessage('Awa'),
      'Envoyez un premier message à Awa.',
    );
    expect(
      l10n.chatGuidedContextReasonMessage('Recrutement club'),
      'Motif : Recrutement club. Adfoot garde ce premier échange dans le '
      'circuit officiel.',
    );
    expect(l10n.chatTodayLabel, 'Aujourd’hui');
    expect(l10n.chatYesterdayLabel, 'Hier');
    expect(l10n.offreExpiresInDaysLabel(3), 'Expire dans 3 jours');
    expect(l10n.offreDaysRemainingLabel(20), 'Encore 20 jours');
    expect(
      l10n.offreDateSummaryLabel('05 sept. 2026', 'Expire demain'),
      '05 sept. 2026 · Expire demain',
    );
    expect(
      l10n.offreValidUntilLabel('05 sept. 2026 · Expire demain'),
      'Valide jusqu’au : 05 sept. 2026 · Expire demain',
    );
    expect(l10n.offreStatusOpenLabel, 'Ouverte');
    expect(l10n.offreContactButton, 'Contacter');
    expect(l10n.eventInDaysLabel(4), 'Dans 4 jours');
    expect(
      l10n.eventDateRangeLabel('05 sept. 2026', '07 sept. 2026'),
      '05 sept. 2026 → 07 sept. 2026',
    );
    expect(l10n.eventParticipantsCountLabel(12), '12 participants');
    expect(l10n.eventStatusOpenLabel, 'Ouvert');
    expect(
      l10n.eventDateRangeFromToLabel('05 sept. 2026', '07 sept. 2026'),
      'Du 05 sept. 2026 au 07 sept. 2026',
    );
    expect(l10n.eventCapacityValueLabel(8, 20), '8 / 20 participants');
    expect(l10n.eventRegistrationOpenToAllLabel, 'Ouverte à tous');
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
    expect(
      l10n.opportunitiesSubtitleWithPlayers,
      'Offers, events, and players',
    );
    expect(
      l10n.talentSearchResultsCountMany(60),
      '60 players — narrow your search to see more',
    );
    expect(l10n.talentSearchResultsCountOther(3), '3 players');
    expect(l10n.followListEmptyFollowersMessage, 'No followers yet.');
    expect(l10n.selectUserTitle, 'New conversation');
    expect(
      l10n.conversationsDeleteFailedMessage('network error'),
      "Couldn't delete the conversation: network error",
    );
    expect(l10n.chatSubtitle, isNot('Messagerie Adfoot'));
    expect(
      l10n.chatEmptyStateMessage('Awa'),
      'Send a first message to Awa.',
    );
    expect(
      l10n.chatGuidedContextReasonMessage('Club recruitment'),
      'Reason: Club recruitment. Adfoot keeps this first exchange in the '
      'official flow.',
    );
    expect(l10n.chatTodayLabel, 'Today');
    expect(l10n.chatYesterdayLabel, 'Yesterday');
    expect(l10n.offreExpiresInDaysLabel(3), 'Expires in 3 days');
    expect(l10n.offreDaysRemainingLabel(20), '20 days left');
    expect(
      l10n.offreDateSummaryLabel('Sep 5, 2026', 'Expires tomorrow'),
      'Sep 5, 2026 · Expires tomorrow',
    );
    expect(
      l10n.offreValidUntilLabel('Sep 5, 2026 · Expires tomorrow'),
      'Valid until: Sep 5, 2026 · Expires tomorrow',
    );
    expect(l10n.offreStatusOpenLabel, isNot('Ouverte'));
    expect(l10n.offreContactButton, 'Contact');
    expect(l10n.eventInDaysLabel(4), 'In 4 days');
    expect(
      l10n.eventDateRangeLabel('Sep 5, 2026', 'Sep 7, 2026'),
      'Sep 5, 2026 → Sep 7, 2026',
    );
    expect(l10n.eventParticipantsCountLabel(12), '12 participants');
    expect(l10n.eventStatusOpenLabel, isNot('Ouvert'));
    expect(
      l10n.eventDateRangeFromToLabel('Sep 5, 2026', 'Sep 7, 2026'),
      'From Sep 5, 2026 to Sep 7, 2026',
    );
    expect(l10n.eventCapacityValueLabel(8, 20), '8 / 20 participants');
    expect(l10n.eventRegistrationOpenToAllLabel, isNot('Ouverte à tous'));
  });
}
