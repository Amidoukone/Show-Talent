import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// Creating an account is the only way onto this platform, and until now it
/// e-mailed nobody.
///
/// `provisionManagedAccount` minted a password-setup link and handed it back
/// to the admin to copy out of a dialog. An invitation nobody pasted anywhere
/// is an account nobody can sign in to, and nothing said so. The sending now
/// happens in the Function — under conditions that must not be relaxed by a
/// later edit, because this code runs *inside* the callable that has already
/// created the account.
void main() {
  group('the invitation is sent without ever risking the account', () {
    // The account exists in Auth and in Firestore before the relay is ever
    // contacted. Moving the send earlier would let a refused SMTP login abort
    // a provision that had already half happened.
    test('the send happens after the account is committed', () {
      final source = _read('functions/src/managed_accounts.ts');

      final commit = source.indexOf('await provisionBatch.commit();');
      final send = source.indexOf('await sendAccountInviteEmail(');
      expect(commit, isNonNegative);
      expect(send, isNonNegative);
      expect(
        commit,
        lessThan(send),
        reason: 'an e-mail must never be able to roll back an account',
      );
    });

    // Every failure path returns an outcome. A throw here would surface to
    // the admin as a failed creation for an account that exists.
    test('the sender cannot throw', () {
      final delivery = _read('functions/src/email_delivery.ts');

      expect(delivery, contains('} catch (error) {'));
      expect(delivery, contains("reason: \"send_failed\""));
      expect(delivery, contains("reason: \"not_configured\""));
      expect(delivery, contains("reason: \"invalid_recipient\""));
      expect(
        delivery,
        isNot(contains('throw new')),
        reason: 'the caller has already created the account',
      );
    });

    // Unbounded SMTP is how "Créer le compte" spins for a minute and the
    // admin retries, inviting the same person twice.
    test('the transport is bounded', () {
      final delivery = _read('functions/src/email_delivery.ts');

      for (final option in const <String>[
        'connectionTimeout:',
        'greetingTimeout:',
        'socketTimeout:',
      ]) {
        expect(delivery, contains(option), reason: option);
      }
    });

    // The whole point of keeping the link: an SMTP outage costs a
    // copy-paste, never an unreachable member.
    test('the link is returned whether or not the mail left', () {
      final provision = _read('functions/src/managed_accounts.ts');
      final resend = _read('functions/src/admin_account_actions.ts');

      for (final source in <String>[provision, resend]) {
        expect(source, contains('passwordSetupLink,'));
        expect(source, contains('inviteEmailSent: invite.sent'));
        expect(source, contains('inviteEmailReason: invite.reason ?? null'));
      }
    });

    // Without this the secret is simply absent at runtime and every
    // invitation is silently skipped as "not_configured".
    test('both callables are bound to the SMTP secret', () {
      final provision = _read('functions/src/managed_accounts.ts');
      final resend = _read('functions/src/admin_account_actions.ts');
      final delivery = _read('functions/src/email_delivery.ts');

      expect(delivery, contains('defineSecret("BREVO_SMTP_KEY")'));
      for (final source in <String>[provision, resend]) {
        expect(
          source,
          contains('{...LOW_CPU_CALLABLE_OPTIONS, secrets: EMAIL_SECRETS}'),
        );
      }
    });

    // This binding was conditional on SMTP_USER until production disproved
    // the assumption behind it. The CLI's discovery pass is what evaluates
    // this line, and it runs without the .env values in its environment: the
    // array came out empty, the secret was never bound, and the deploy
    // reported success while every invitation was skipped as
    // "not_configured". The switch belongs at runtime, where the value can
    // actually be read. Cost of the fix: BREVO_SMTP_KEY must now exist in
    // every project this codebase is deployed to, staging included.
    test('the SMTP secret is bound unconditionally', () {
      final delivery = _read('functions/src/email_delivery.ts');

      expect(delivery, contains('const EMAIL_SECRETS = [BREVO_SMTP_KEY];'));
      expect(
        delivery,
        isNot(contains('const EMAIL_SECRETS = (process.env.SMTP_USER')),
        reason: 'deploy-time discovery cannot see SMTP_USER',
      );
      // The runtime switch is what still keeps an unconfigured project quiet.
      expect(delivery, contains('if (!user || !pass || !fromAddress) {'));
    });

    // Identity Toolkit reports its per-address link rate limit as a generic
    // auth/internal-error, so only the raw server message identifies it. Two
    // clicks on "Renvoyer l'invitation" are enough to reach it, and it used
    // to surface in the portal as a bare "Internal error" that told the
    // operator nothing -- least of all that waiting was the entire fix.
    test('a refused action link explains itself to the operator', () {
      final support = _read('functions/src/admin_account_support.ts');

      expect(support, contains('function isActionLinkRateLimited('));
      expect(support, contains('TOO_MANY_ATTEMPTS_TRY_LATER'));
      expect(support, contains('"resource-exhausted"'));
      expect(support, contains('reason: "too_many_attempts"'));
      // No auth failure reaches the portal as a bare INTERNAL any more.
      expect(support, contains('reason: "action_link_failed", code'));
    });

    // An admin-provisioned address is trusted: there is no self-signup, and
    // the invitation is delivered to the address the admin typed. Leaving
    // emailVerified false wrote `estActif: false` into the profile, so the
    // portal showed the new member "Inactif / Acces limite" -- and it stayed
    // that way after the password was set, because completing a reset
    // updates Firebase Auth and nothing else. The profile was reconciled
    // only on the member's first mobile sign-in, by the repair callable.
    test('provisioning marks the address verified and the profile active', () {
      final provision = _read('functions/src/managed_accounts.ts');

      expect(provision, contains('if (!userRecord.emailVerified) {'));
      expect(provision, contains('emailVerified: true,'));
      expect(
        provision,
        contains(
          'estActif: userRecord.emailVerified && '
          'userRecord.disabled !== true,',
        ),
      );
      // Which is also why the second link is never minted: setting the
      // password is the single action asked of the member.
      expect(
        provision,
        contains('const emailVerificationLink = userRecord.emailVerified ?'),
      );
    });

    // Operator input from the portal's form reaches an HTML document.
    test('the display name is escaped into the HTML part', () {
      final delivery = _read('functions/src/email_delivery.ts');

      expect(delivery, contains('function escapeHtml('));
      expect(delivery, contains('escapeHtml(greeting)'));
      expect(delivery, contains('escapeHtml(intro)'));
      expect(delivery, contains('escapeHtml(input.passwordSetupLink)'));
    });

    // A message with an HTML part and no text part is a known spam signal,
    // and this one exists to land in an inbox.
    test('the message carries both parts', () {
      final delivery = _read('functions/src/email_delivery.ts');

      expect(delivery, contains('text,'));
      expect(delivery, contains('html,'));
    });

    // These lines are readable by anyone with Logs Viewer. An invitation log
    // that carried the address would become a roster of every member.
    test('failures are logged without the recipient', () {
      final delivery = _read('functions/src/email_delivery.ts');

      final failure = delivery.indexOf('account invite e-mail failed');
      expect(failure, isNonNegative);
      final end = (failure + 400).clamp(0, delivery.length);
      final block = delivery.substring(failure, end);
      expect(block, isNot(contains('to,')));
      expect(block, isNot(contains('input.to')));
    });
  });
}
