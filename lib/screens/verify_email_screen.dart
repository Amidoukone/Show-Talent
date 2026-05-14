import 'package:adfoot/config/app_routes.dart';
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

  static const String _loginAfterVerificationMessage =
      'Si la page web indique que votre e-mail a été vérifié, '
      'retournez à la connexion puis reconnectez-vous pour activer le compte.';

  @override
  void initState() {
    super.initState();

    final args = Get.arguments;
    if (args is Map) {
      _emailSent = args['emailSent'] == true;
      _sentAtMs = args['sentAt'] is int ? args['sentAt'] as int : null;
      if (_sentAtMs != null) {
        VerifyEmailThrottle.lastSentAt =
            DateTime.fromMillisecondsSinceEpoch(_sentAtMs!);
      }
    }

    _handlePossibleRedirectParams();
  }

  String _defaultUxMessage({required bool emailSent}) {
    final email = _authSessionService.currentUserEmail;
    final emailLine =
        (email != null && email.isNotEmpty) ? 'Adresse : $email\n\n' : '';

    return emailSent
        ? 'Un e-mail de vérification a été envoyé.\n\n$emailLine'
            'Ouvre ta boîte de réception et clique sur le lien.\n'
            'Si tu ne le vois pas, vérifie aussi Spam / Indésirables / Promotions.\n\n'
            'Une fois l’e-mail vérifié dans le navigateur, reviens ici puis retourne à la connexion.'
        : 'Vérifie ta boîte mail et clique sur le lien de vérification.\n\n$emailLine'
            'Si tu ne le vois pas, vérifie aussi Spam / Indésirables / Promotions.\n\n'
            'Une fois l’e-mail vérifié dans le navigateur, reviens ici puis retourne à la connexion.';
  }

  Future<void> _goBackToLogin() async {
    try {
      await _authSessionService.signOut();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    await Get.offAllNamed(AppRoutes.login);
  }

  Future<void> _redirectToLogin({
    String? email,
    String? message,
  }) async {
    try {
      await _authSessionService.signOut();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    await Get.offAllNamed(
      AppRoutes.login,
      arguments: <String, dynamic>{
        if (email != null && email.isNotEmpty) 'prefillEmail': email,
        'sessionNoticeTitle': 'E-mail vérifié',
        'sessionNoticeMessage': message ??
            'Votre e-mail a été vérifié. Connectez-vous pour continuer.',
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
          await _redirectToLogin(
            email: _authSessionService.currentUserEmail,
            message: _loginAfterVerificationMessage,
          );
          return;
        } on FirebaseAuthException catch (error) {
          debugPrint('applyActionCode error: ${error.code} - ${error.message}');
          if (mounted) {
            setState(() {
              _message =
                  'Le lien de vérification est invalide ou expiré. Demandez un nouveau lien.';
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

    if (!VerifyEmailThrottle.canSendNow()) {
      AdFeedback.warning(
        'Veuillez patienter',
        'Attendez quelques secondes avant de renvoyer.',
      );
      return;
    }

    if (mounted) {
      setState(() {
        _resending = true;
      });
    }

    try {
      final result =
          await _authSessionService.sendCurrentUserEmailVerification();

      if (!result.sent) {
        if (!mounted) {
          return;
        }

        AdFeedback.error(
          'Erreur',
          result.errorMessage ?? 'Erreur d\'envoi.',
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
        'Lien envoyé',
        'Un e-mail de vérification a été renvoyé.',
      );
    } on AuthFlowException catch (error) {
      if (!mounted) {
        return;
      }

      AdFeedback.error(
        'Erreur',
        error.message,
      );
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AdAppBar(
        title: 'Vérification e-mail',
        subtitle: 'Sécurisation du compte Adfoot',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: (_isProcessing || _resending) ? null : _goBackToLogin,
          tooltip: 'Retour',
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isProcessing
              ? const AdStatePanel.loading(
                  title: 'Vérification en cours',
                  message: 'Préparation du parcours de vérification...',
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
                        const SizedBox(height: 24),
                        AdButton(
                          onPressed: _goBackToLogin,
                          leading: Icons.login_outlined,
                          label: 'Retour à la connexion',
                        ),
                        const SizedBox(height: 12),
                        AdButton(
                          onPressed: _resending ? null : _resendEmail,
                          loading: _resending,
                          leading: Icons.email_outlined,
                          kind: AdButtonKind.tonal,
                          label: 'Renvoyer le lien de vérification',
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
