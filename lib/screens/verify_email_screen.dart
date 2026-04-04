import 'dart:async';

import 'package:adfoot/config/app_environment.dart';
import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/email_link_handler.dart';
import 'package:adfoot/services/verify_email_throttle.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
  bool _finishing = false;
  bool _resending = false;
  String? _message;

  Timer? _pollingTimer;
  StreamSubscription<void>? _linkSub;

  bool _emailSent = false;
  int? _sentAtMs;

  static final ActionCodeSettings _acs = ActionCodeSettings(
    url: AppEnvironmentConfig.emailVerificationActionUrl,
    handleCodeInApp: false,
  );

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

    _listenToEmailVerification();
    _handlePossibleRedirectParams().then((_) {
      _startVerificationPolling();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  String _defaultUxMessage({required bool emailSent}) {
    final email = _authSessionService.currentUserEmail;
    final emailLine =
        (email != null && email.isNotEmpty) ? 'Adresse : $email\n\n' : '';

    return emailSent
        ? 'Un e-mail de verification a ete envoye.\n\n$emailLine'
            'Ouvre ta boite de reception et clique sur le lien.\n'
            'Si tu ne le vois pas, verifie aussi Spam / Indesirables / Promotions.\n\n'
            'Apres avoir clique, reviens ici et appuie sur "J\'ai clique sur le lien, continuer".'
        : 'Verifie ta boite mail et clique sur le lien de verification.\n\n$emailLine'
            'Si tu ne le vois pas, verifie aussi Spam / Indesirables / Promotions.\n\n'
            'Apres avoir clique, reviens ici et appuie sur "J\'ai clique sur le lien, continuer".';
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

  Map<String, String> _mergedParamsFrom(Uri uri) {
    final params = <String, String>{...uri.queryParameters};
    if (uri.fragment.isNotEmpty) {
      try {
        params.addAll(Uri.splitQueryString(uri.fragment));
      } catch (_) {}
    }
    return params;
  }

  Future<void> _handlePossibleRedirectParams() async {
    if (!kIsWeb) {
      return;
    }

    final params = _mergedParamsFrom(Uri.base);
    final mode = params['mode'];
    final oobCode = params['oobCode'];

    if (mode == 'verifyEmail' && oobCode != null && oobCode.isNotEmpty) {
      try {
        await _authSessionService.applyEmailVerificationCode(oobCode);
      } on FirebaseAuthException catch (error) {
        debugPrint('applyActionCode error: ${error.code} - ${error.message}');
      }

      final user = _authSessionService.currentUser;
      if (user == null) {
        if (!mounted) {
          return;
        }

        setState(() {
          _isProcessing = false;
          _message =
              'E-mail verifie. Veuillez vous reconnecter pour continuer.';
        });
        return;
      }

      if (_authSessionService.isCurrentUserEmailVerified) {
        await _finalizeVerificationAndNavigate();
      }
    }
  }

  void _listenToEmailVerification() {
    EmailLinkHandler.init().then((_) {
      _linkSub = EmailLinkHandler.onEmailVerified.listen((_) {
        _onEmailVerified();
      });
    });
  }

  void _startVerificationPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final refreshed = await _authSessionService.reloadCurrentUser();
        if (refreshed == null) {
          return;
        }

        if (refreshed.emailVerified) {
          _onEmailVerified();
        }
      } catch (_) {
        // Ignore intermittent reload failures while polling.
      }
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _isProcessing = false;
      _message = _defaultUxMessage(emailSent: _emailSent);
    });
  }

  Future<void> _onEmailVerified() async {
    if (_finishing || !mounted) {
      return;
    }

    setState(() {
      _finishing = true;
    });

    try {
      _pollingTimer?.cancel();
      _linkSub?.cancel();
      await _finalizeVerificationAndNavigate();
    } finally {
      if (mounted) {
        setState(() {
          _finishing = false;
        });
      }
    }
  }

  Future<void> _finalizeVerificationAndNavigate() async {
    try {
      final snapshot = await _authSessionService.finalizeCurrentVerifiedSession(
        updateLastLogin: true,
        signOutOnInvalid: true,
      );

      if (!mounted) {
        return;
      }

      if (snapshot.destination == AuthSessionDestination.main) {
        await Get.offAllNamed(AppRoutes.main);
        Get.find<UserController>().kickstart();
        return;
      }

      await Get.offAllNamed(AppRoutes.login);
    } on AuthFlowException catch (error) {
      if (!mounted) {
        return;
      }

      final needsVerificationHint =
          error.message.contains('n\'est pas encore detecte') ||
              error.message.contains('n\'est pas encore détecté');

      setState(() {
        _message = needsVerificationHint
            ? '${_defaultUxMessage(emailSent: _emailSent)}\n\n'
                'Ton e-mail n\'est pas encore detecte comme verifie.\n'
                'Apres avoir clique sur le lien, attends 2 a 5 secondes puis reessaie.'
            : error.message;
      });
    }
  }

  Future<void> _resendEmail() async {
    if (_isProcessing || _finishing || _resending) {
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
      final result = await _authSessionService.sendCurrentUserEmailVerification(
        actionCodeSettings: _acs,
      );

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
        'Lien envoye',
        'Un e-mail de verification a ete renvoye.',
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
        title: 'Verification e-mail',
        subtitle: 'Securisation du compte Adfoot',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: (_isProcessing || _finishing || _resending)
              ? null
              : _goBackToLogin,
          tooltip: 'Retour',
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isProcessing
              ? const AdStatePanel.loading(
                  title: 'Verification en cours',
                  message: 'Initialisation de la session securisee...',
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
                          onPressed: _finishing ? null : _onEmailVerified,
                          loading: _finishing,
                          leading: Icons.check_circle_outline,
                          label: _finishing
                              ? 'Verification...'
                              : 'J\'ai clique sur le lien, continuer',
                        ),
                        const SizedBox(height: 12),
                        AdButton(
                          onPressed:
                              (_finishing || _resending) ? null : _resendEmail,
                          loading: _resending,
                          leading: Icons.email_outlined,
                          kind: AdButtonKind.tonal,
                          label: 'Renvoyer le lien de verification',
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
