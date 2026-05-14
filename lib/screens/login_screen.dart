import 'package:adfoot/controller/user_controller.dart';
import 'dart:async';

import 'package:adfoot/screens/signup_screen.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthSessionService _authSessionService = AuthSessionService();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isResettingPassword = false;
  String? _sessionNoticeTitle;
  String? _sessionNoticeMessage;
  String _sessionNoticeKind = 'error';

  bool get _isBusy => _isLoading || _isResettingPassword;

  @override
  void initState() {
    super.initState();
    _captureSessionNotice();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isBusy) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final snapshot = await _authSessionService.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (snapshot.destination == AuthSessionDestination.login) {
        _showErrorSnackbar(
          snapshot.failureMessage ??
              snapshot.failure?.loginMessage ??
              'Connexion impossible pour le moment.',
          title: snapshot.failureTitle ?? 'Connexion impossible',
        );
        return;
      }

      final userController = Get.find<UserController>();
      await userController.applyResolvedSessionSnapshot(snapshot).timeout(
            const Duration(seconds: 12),
            onTimeout: () => userController.kickstart(),
          );
    } on FirebaseAuthException catch (error) {
      _showErrorSnackbar(AuthErrorMapper.toMessage(error));
    } on AuthFlowException catch (error) {
      _showErrorSnackbar(error.message);
    } catch (_) {
      _showErrorSnackbar(
        'Une erreur inattendue s’est produite. Veuillez réessayer.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    if (_isBusy) {
      return;
    }

    final email = _emailController.text.trim();
    final emailError = _validateEmailValue(email);
    if (emailError != null) {
      _showErrorSnackbar(emailError, title: 'Reinitialisation impossible');
      return;
    }

    if (mounted) {
      setState(() => _isResettingPassword = true);
    }

    try {
      await _authSessionService.sendPasswordResetEmail(
        email: email,
      );

      AdFeedback.success(
        'Succès',
        'E-mail de reinitialisation envoye.',
      );
    } on FirebaseAuthException catch (error) {
      _showErrorSnackbar(
        AuthErrorMapper.toMessage(error),
        title: 'Reinitialisation impossible',
      );
    } on AuthFlowException catch (error) {
      _showErrorSnackbar(error.message, title: 'Reinitialisation impossible');
    } catch (_) {
      _showErrorSnackbar(
        'Impossible d\'envoyer le lien de reinitialisation pour le moment.',
        title: 'Reinitialisation impossible',
      );
    } finally {
      if (mounted) {
        setState(() => _isResettingPassword = false);
      }
    }
  }

  String? _validateEmailValue(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'Veuillez saisir votre e-mail.';
    }
    final ok =
        RegExp(r'^[\w\.\-+]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(normalized);
    if (!ok) {
      return 'Veuillez saisir une adresse e-mail valide.';
    }
    return null;
  }

  void _captureSessionNotice() {
    Map<String, String>? notice;

    final args = Get.arguments;
    if (args is Map) {
      final prefillEmail = args['prefillEmail']?.toString().trim();
      if (prefillEmail != null && prefillEmail.isNotEmpty) {
        _emailController.text = prefillEmail;
      }

      final title = args['sessionNoticeTitle']?.toString().trim();
      final message = args['sessionNoticeMessage']?.toString().trim();
      final kind = args['sessionNoticeKind']?.toString().trim().toLowerCase();
      if (message != null && message.isNotEmpty) {
        notice = <String, String>{
          'sessionNoticeTitle': (title == null || title.isEmpty)
              ? 'Information importante'
              : title,
          'sessionNoticeMessage': message,
          'sessionNoticeKind': (kind == null || kind.isEmpty) ? 'error' : kind,
        };
      }
    }

    notice ??= Get.find<UserController>().consumePendingSessionNotice();
    if (notice == null) {
      return;
    }

    final title = notice['sessionNoticeTitle']?.trim();
    final message = notice['sessionNoticeMessage']?.trim();
    if (message == null || message.isEmpty) {
      return;
    }

    _sessionNoticeTitle =
        (title == null || title.isEmpty) ? 'Information importante' : title;
    _sessionNoticeMessage = message;
    _sessionNoticeKind =
        notice['sessionNoticeKind']?.trim().toLowerCase() ?? 'error';
  }

  void _showErrorSnackbar(
    String message, {
    String title = 'Connexion echouee',
  }) {
    AdFeedback.error(
      title,
      message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSuccessNotice = _sessionNoticeKind == 'success';
    final noticeBackground = isSuccessNotice
        ? cs.primaryContainer.withValues(alpha: 0.95)
        : cs.errorContainer.withValues(alpha: 0.95);
    final noticeBorder = isSuccessNotice
        ? cs.primary.withValues(alpha: 0.18)
        : cs.error.withValues(alpha: 0.18);
    final noticeForeground =
        isSuccessNotice ? cs.onPrimaryContainer : cs.onErrorContainer;
    final noticeIcon =
        isSuccessNotice ? Icons.verified_outlined : Icons.gpp_bad_outlined;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_sessionNoticeMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: noticeBackground,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: noticeBorder,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                noticeIcon,
                                color: noticeForeground,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _sessionNoticeTitle ??
                                          'Information importante',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: noticeForeground,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _sessionNoticeMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: noticeForeground.withValues(
                                                alpha: .92),
                                            height: 1.35,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Align(
                        alignment: Alignment.center,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/logo.png',
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Connectez-vous',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ravi de vous revoir !',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withValues(alpha: .7),
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      AdTextField(
                        controller: _emailController,
                        label: 'Adresse e-mail',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.email_outlined),
                        validator: (v) => _validateEmailValue(v ?? ''),
                      ),
                      const SizedBox(height: 16),
                      AdTextField(
                        controller: _passwordController,
                        label: 'Mot de passe',
                        isPassword: true,
                        prefixIcon: const Icon(Icons.lock_outline),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Mot de passe requis'
                            : null,
                        onSubmitted: _login,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isBusy ? null : _resetPassword,
                          child: const Text('Mot de passe oublie ?'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      AdButton(
                        label: 'Se connecter',
                        onPressed: _isBusy ? null : _login,
                        loading: _isLoading,
                        leading: Icons.login_rounded,
                        kind: AdButtonKind.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tous les comptes sont maintenant crees par l\'administration Adfoot.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: .7),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Nouveau ici ?',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: .8),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          TextButton(
                            onPressed: _isBusy
                                ? null
                                : () => Get.to(() => const SignUpScreen()),
                            child: const Text('Obtenir un accès'),
                          ),
                        ],
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
