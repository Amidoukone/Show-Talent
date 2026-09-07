import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/l10n/generated/app_localizations.dart';
import 'package:adfoot/services/auth/auth_diagnostics.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/verify_email_throttle.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../utils/email_action_link_parser.dart';
import '../widgets/ad_app_bar.dart';
import '../widgets/ad_button.dart';
import '../widgets/ad_feedback.dart';
import '../widgets/ad_state_panel.dart';
import '../widgets/ad_surface_card.dart';
import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/theme/ad_tokens.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthSessionService _authSessionService = AuthSessionService();

  bool _isProcessing = true;
  bool _resending = false;
  String? _message;

  bool _emailSent = false;
  int? _sentAtMs;
  bool _redirectParamsHandled = false;

  @override
  void initState() {
    super.initState();

    final args = Get.arguments;
    if (args is Map) {
      _emailSent = args['emailSent'] == true;
      _sentAtMs = args['sentAt'] is int ? args['sentAt'] as int : null;
      if (_sentAtMs != null) {
        VerifyEmailThrottle.lastSentAt = DateTime.fromMillisecondsSinceEpoch(
          _sentAtMs!,
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not in initState: on non-web (the common case), this runs through to
    // AppLocalizations.of(context) synchronously, before initState returns
    // -- Flutter forbids depending on an inherited widget (Localizations
    // included) until after initState completes. didChangeDependencies is
    // the framework's own prescribed place for exactly this.
    if (!_redirectParamsHandled) {
      _redirectParamsHandled = true;
      _handlePossibleRedirectParams();
    }
  }

  String _defaultUxMessage({required bool emailSent}) {
    final l10n = AppLocalizations.of(context)!;
    final email = _authSessionService.currentUserEmail;
    final emailLine = (email != null && email.isNotEmpty)
        ? '${l10n.verifyEmailAddressLine(email)}\n\n'
        : '';

    final buffer = StringBuffer()
      ..write(emailSent ? l10n.verifyEmailSentIntro : l10n.verifyEmailUnsentIntro)
      ..write('\n\n')
      ..write(emailLine);
    if (emailSent) {
      buffer
        ..write(l10n.verifyEmailCheckInboxInstruction)
        ..write('\n');
    }
    buffer
      ..write(l10n.verifyEmailCheckSpamInstruction)
      ..write('\n\n')
      ..write(l10n.verifyEmailReturnToLoginInstruction);
    return buffer.toString();
  }

  Future<void> _goBackToLogin() async {
    try {
      await _authSessionService.signOut();
    } catch (error) {
      AppLogger.debug('VerifyEmailScreen sign-out before login error: $error');
    }

    if (!mounted) {
      return;
    }

    await Get.offAllNamed(AppRoutes.login);
  }

  Future<void> _redirectToLogin({String? email, String? message}) async {
    try {
      await _authSessionService.signOut();
    } catch (error) {
      AppLogger.debug(
        'VerifyEmailScreen sign-out before redirect error: $error',
      );
    }

    if (!mounted) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    await Get.offAllNamed(
      AppRoutes.login,
      arguments: <String, dynamic>{
        if (email != null && email.isNotEmpty) 'prefillEmail': email,
        'sessionNoticeTitle': l10n.verifyEmailVerifiedNoticeTitle,
        'sessionNoticeMessage':
            message ?? l10n.verifyEmailVerifiedNoticeMessage,
        'sessionNoticeKind': 'success',
      },
    );
  }

  Future<void> _handlePossibleRedirectParams() async {
    if (kIsWeb) {
      final params = EmailActionLinkParser.extract(Uri.base);
      final mode = params['mode'];
      final oobCode = params['oobCode'];

      if (mode == 'verifyEmail' && oobCode != null && oobCode.isNotEmpty) {
        try {
          await _authSessionService.applyEmailVerificationCode(oobCode);
          if (!mounted) {
            return;
          }
          final l10n = AppLocalizations.of(context)!;
          await _redirectToLogin(
            email: _authSessionService.currentUserEmail,
            message: l10n.verifyEmailAfterVerificationMessage,
          );
          return;
        } on FirebaseAuthException catch (error) {
          // The verification twin of a refused reset link, and reported the
          // same way. The user is told on screen, so this is `handled` rather
          // than `failure` — but a rise in the rate is how a broken link flow
          // shows up, and that has to be visible somewhere other than a debug
          // log release builds discard.
          AuthDiagnostics.handled(
            'verifyEmail link refused (${error.code})',
            stage: 'verify_email_link',
            error: error,
          );
          if (mounted) {
            setState(() {
              _message =
                  AppLocalizations.of(context)!.verifyEmailInvalidLinkMessage;
            });
          }
        }
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isProcessing = false;
      _message = _defaultUxMessage(emailSent: _emailSent);
    });
  }

  Future<void> _resendEmail() async {
    if (_isProcessing || _resending) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;

    if (!VerifyEmailThrottle.canSendNow()) {
      AdFeedback.warning(
        l10n.verifyEmailThrottleTitle,
        l10n.verifyEmailThrottleMessage,
      );
      return;
    }

    if (mounted) {
      setState(() {
        _resending = true;
      });
    }

    try {
      final result = await _authSessionService
          .sendCurrentUserEmailVerification();

      if (!result.sent) {
        if (!mounted) {
          return;
        }

        AdFeedback.error(
          l10n.verifyEmailGenericErrorTitle,
          result.errorMessage ?? l10n.verifyEmailSendErrorDefault,
        );
        return;
      }

      VerifyEmailThrottle.markSentNow();

      if (!mounted) {
        return;
      }

      setState(() {
        _emailSent = true;
        _message = _defaultUxMessage(emailSent: true);
      });

      AdFeedback.success(
        l10n.verifyEmailResentTitle,
        l10n.verifyEmailResentMessage,
      );
    } on AuthFlowException catch (error) {
      if (!mounted) {
        return;
      }

      AdFeedback.error(l10n.verifyEmailGenericErrorTitle, error.message);
    } finally {
      if (mounted) {
        setState(() {
          _resending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AdAppBar(
        title: l10n.verifyEmailAppBarTitle,
        subtitle: l10n.verifyEmailAppBarSubtitle,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: (_isProcessing || _resending) ? null : _goBackToLogin,
          tooltip: l10n.verifyEmailBackTooltip,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AdSpacing.xl),
          child: _isProcessing
              ? AdStatePanel.loading(
                  title: l10n.verifyEmailLoadingTitle,
                  message: l10n.verifyEmailLoadingMessage,
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: AdSurfaceCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _message ?? _defaultUxMessage(emailSent: _emailSent),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AdSpacing.xl),
                        AdButton(
                          onPressed: _goBackToLogin,
                          leading: Icons.login_outlined,
                          label: l10n.verifyEmailBackToLogin,
                        ),
                        const SizedBox(height: AdSpacing.sm),
                        AdButton(
                          onPressed: _resending ? null : _resendEmail,
                          loading: _resending,
                          leading: Icons.email_outlined,
                          kind: AdButtonKind.tonal,
                          label: l10n.verifyEmailResendLink,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
