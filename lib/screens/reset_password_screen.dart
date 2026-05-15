import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:adfoot/widgets/ad_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.oobCode});

  final String oobCode;

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
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
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

      AdFeedback.success(
        'Succès',
        'Mot de passe réinitialisé avec succès.',
      );

      await Get.offAllNamed(AppRoutes.login);
    } on FirebaseAuthException catch (error) {
      AdFeedback.error(
        'Reinitialisation impossible',
        AuthErrorMapper.toMessage(error),
      );
    } on AuthFlowException catch (error) {
      AdFeedback.error(
        'Reinitialisation impossible',
        error.message,
      );
    } catch (_) {
      AdFeedback.error(
        'Reinitialisation impossible',
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
      return 'Le mot de passe doit contenir au moins 6 caracteres.';
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

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: !_hasValidCode
                ? AdStatePanel.error(
                    title: 'Lien invalide',
                    message:
                        'Le lien de reinitialisation est invalide ou incomplet. '
                        'Demandez un nouveau lien depuis la page de connexion.',
                    action: AdButton(
                      label: 'Retour a la connexion',
                      leading: Icons.arrow_back,
                      onPressed: () => Get.offAllNamed(AppRoutes.login),
                      kind: AdButtonKind.primary,
                    ),
                  )
                : Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.disabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Reinitialiser le mot de passe',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            AdTextField(
                              controller: _passwordController,
                              label: 'Nouveau mot de passe',
                              isPassword: true,
                              prefixIcon: const Icon(Icons.lock_outline),
                              validator: _validatePassword,
                            ),
                            const SizedBox(height: 16),
                            AdTextField(
                              controller: _confirmController,
                              label: 'Confirmer le mot de passe',
                              isPassword: true,
                              prefixIcon: const Icon(Icons.lock_outline),
                              validator: _validateConfirmation,
                              onSubmitted: _resetPassword,
                            ),
                            const SizedBox(height: 24),
                            AdButton(
                              label: 'Valider',
                              onPressed: _isLoading ? null : _resetPassword,
                              loading: _isLoading,
                              kind: AdButtonKind.primary,
                              leading: Icons.check_rounded,
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
