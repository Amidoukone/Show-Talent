import 'dart:async';

import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/auth/password_reset_flow.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';
import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:adfoot/widgets/ad_surface_card.dart';
import 'package:adfoot/widgets/ad_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.oobCode,
    this.accountEmail,
  });

  final String oobCode;

  /// The address the code was minted for, when the caller could resolve it.
  ///
  /// `verifyPasswordResetCode` returns it and it costs nothing to carry. A
  /// screen that asks for a new password without naming the account it
  /// belongs to is exactly the screen a phishing page imitates — and after a
  /// tap from an e-mail client, naming it is the only confirmation the user
  /// gets that the right link opened.
  final String? accountEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  AuthSessionService? _authSessionService;

  AuthSessionService get _sessionService =>
      _authSessionService ??= AuthSessionService();

  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  late final bool _hasValidCode;

  @override
  void initState() {
    super.initState();
    _hasValidCode = widget.oobCode.trim().isNotEmpty;

    // A code that never arrived is not a reset in progress. Release the flow
    // immediately so session routing is not held back by a dead end.
    if (!_hasValidCode) {
      PasswordResetFlow.end();
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Hands the screen back to session routing, then leaves.
  ///
  /// Every exit from this screen goes through here. While a reset is in
  /// progress `UserController` and `SplashScreen` are both barred from
  /// navigating (see [PasswordResetFlow]), so releasing the flow *before*
  /// leaving is what lets the app resume its normal routing — and what keeps
  /// this screen from being the last one the app is able to show.
  Future<void> _leaveToLogin({Map<String, dynamic>? arguments}) async {
    PasswordResetFlow.end();
    await Get.offAllNamed(AppRoutes.login, arguments: arguments);
  }

  Future<void> _resetPassword() async {
    if (_isLoading || !_hasValidCode) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final pass = _passwordController.text;

    setState(() => _isLoading = true);
    try {
      await _sessionService.confirmPasswordReset(
        code: widget.oobCode,
        newPassword: pass,
      );

      AdFeedback.success('Succès', 'Mot de passe réinitialisé avec succès.');

      final email = widget.accountEmail?.trim();
      await _leaveToLogin(
        arguments: email == null || email.isEmpty
            ? null
            // Firebase revokes the existing sessions on a password change, so
            // the next screen is always a fresh sign-in. Carrying the address
            // over spares retyping it on a screen the user did not choose.
            : <String, dynamic>{'prefillEmail': email},
      );
    } on FirebaseAuthException catch (error) {
      AdFeedback.error(
        'Réinitialisation impossible',
        AuthErrorMapper.toMessage(error),
      );
    } on AuthFlowException catch (error) {
      AdFeedback.error('Réinitialisation impossible', error.message);
    } catch (_) {
      AdFeedback.error(
        'Réinitialisation impossible',
        'Une erreur inattendue est survenue. Veuillez réessayer.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _validatePassword(String? value) {
    final pass = value ?? '';
    if (pass.isEmpty) {
      return 'Mot de passe requis.';
    }
    if (pass.length < 6) {
      return 'Le mot de passe doit contenir au moins 6 caractères.';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    final confirm = value ?? '';
    if (confirm.isEmpty) {
      return 'Confirmation requise.';
    }
    if (confirm != _passwordController.text) {
      return 'Les mots de passe ne correspondent pas.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // The screen is installed with `offAllNamed`, so there is nothing beneath
    // it: an unhandled back press would leave the app on an empty navigator.
    // Route it to login instead, releasing the flow on the way out.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _isLoading) {
          return;
        }
        unawaited(_leaveToLogin());
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AdSpacing.lg,
              vertical: AdSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: !_hasValidCode
                  ? AdStatePanel.error(
                      title: 'Lien invalide',
                      message:
                          'Le lien de réinitialisation est invalide ou incomplet. '
                          'Demandez un nouveau lien depuis la page de connexion.',
                      action: AdButton(
                        label: 'Retour à la connexion',
                        leading: Icons.arrow_back,
                        onPressed: () => unawaited(_leaveToLogin()),
                        kind: AdButtonKind.primary,
                      ),
                    )
                  : AdSurfaceCard(
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.disabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Réinitialiser le mot de passe',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.accountEmail?.trim().isNotEmpty ==
                                true) ...[
                              const SizedBox(height: AdSpacing.sm),
                              Text(
                                'Compte : ${widget.accountEmail!.trim()}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AdColors.onSurfaceMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: AdSpacing.xl),
                            AdTextField(
                              controller: _passwordController,
                              label: 'Nouveau mot de passe',
                              isPassword: true,
                              prefixIcon: const Icon(Icons.lock_outline),
                              validator: _validatePassword,
                            ),
                            const SizedBox(height: AdSpacing.md),
                            AdTextField(
                              controller: _confirmController,
                              label: 'Confirmer le mot de passe',
                              isPassword: true,
                              prefixIcon: const Icon(Icons.lock_outline),
                              validator: _validateConfirmation,
                              onSubmitted: _resetPassword,
                            ),
                            const SizedBox(height: AdSpacing.xl),
                            AdButton(
                              label: 'Valider',
                              onPressed: _isLoading ? null : _resetPassword,
                              loading: _isLoading,
                              kind: AdButtonKind.primary,
                              leading: Icons.check_rounded,
                            ),
                            const SizedBox(height: AdSpacing.sm),
                            AdButton(
                              label: 'Annuler',
                              onPressed: _isLoading
                                  ? null
                                  : () => unawaited(_leaveToLogin()),
                              kind: AdButtonKind.outline,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
