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

    // A secret named in a function's options must exist in Secret Manager or
    // the entire deploy is rejected. Binding it unconditionally would mean
    // "Brevo is not set up yet" stopped anyone deploying any Cloud Function.
    test('the secret is only required once sending is switched on', () {
      final delivery = _read('functions/src/email_delivery.ts');

      expect(
        delivery,
        contains('const EMAIL_SECRETS = (process.env.SMTP_USER ?? "").trim() ?'),
      );
      expect(delivery, contains('[BREVO_SMTP_KEY] :\n  [];'));
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
