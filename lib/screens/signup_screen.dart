import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/verify_email_throttle.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/utils/auth_error_mapper.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_text_field.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final AuthSessionService _authSessionService = AuthSessionService();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  String _selectedRole = 'joueur';
  bool _isLoading = false;

  static const _roles = publicSelfSignupRoles;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authSessionService.signUpPublicAccount(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        nom: _nameController.text.trim(),
        role: _selectedRole,
        phone: _phoneController.text.trim(),
      );

      if (result.emailDelivery.sent && result.emailDelivery.sentAtMs != null) {
        VerifyEmailThrottle.lastSentAt =
            DateTime.fromMillisecondsSinceEpoch(result.emailDelivery.sentAtMs!);
        VerifyEmailThrottle.markSentNow();
      } else if (result.emailDelivery.errorMessage != null) {
        AdFeedback.warning(
          'Attention',
          'E-mail non envoyé. Vous pourrez le renvoyer depuis l\'écran suivant.',
        );
      }

      if (!mounted) {
        return;
      }

      AdFeedback.success(
        'Compte créé',
        result.emailDelivery.sent
            ? 'Vérifiez votre adresse e-mail pour activer votre compte.'
            : 'Compte créé. Vous pourrez renvoyer le lien depuis l\'écran suivant.',
      );

      await Get.find<UserController>().applyResolvedSessionSnapshot(
        result.session,
        routeArguments: {
          'emailSent': result.emailDelivery.sent,
          'sentAt': result.emailDelivery.sentAtMs,
        },
      );
    } on FirebaseAuthException catch (error) {
      AdFeedback.error('Erreur', AuthErrorMapper.toMessage(error));
    } on AuthFlowException catch (error) {
      AdFeedback.error('Accès refusé', error.message);
    } catch (error) {
      AdFeedback.error(
        'Erreur',
        'Une erreur inattendue s\'est produite. Réessayez.',
      );
      debugPrint('SignUp unexpected error: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                        'Créez un compte',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rejoignez la communauté Adfoot',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'L’inscription publique est réservée aux joueurs et aux fans. '
                                'Les comptes club, recruteur et agent sont créés '
                                'par l’équipe Adfoot.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      AdTextField(
                        controller: _nameController,
                        label: 'Nom complet',
                        prefixIcon: const Icon(Icons.person_outline),
                        validator: _validateName,
                      ),
                      const SizedBox(height: 16),
                      AdTextField(
                        controller: _emailController,
                        label: 'Adresse e-mail',
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.email_outlined),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),
                      AdTextField(
                        controller: _phoneController,
                        label: 'Numéro de téléphone (optionnel)',
                        keyboardType: TextInputType.phone,
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                      const SizedBox(height: 16),
                      AdTextField(
                        controller: _passwordController,
                        label: 'Mot de passe',
                        isPassword: true,
                        prefixIcon: const Icon(Icons.lock_outline),
                        validator: (val) => (val?.length ?? 0) < 6
                            ? 'Minimum 6 caractères'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Rôle',
                          prefixIcon: Icon(Icons.account_circle_outlined),
                        ),
                        items: _roles
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(role.capitalizeFirst!),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedRole = value ?? 'joueur');
                        },
                      ),
                      const SizedBox(height: 24),
                      AdButton(
                        label: 'S’inscrire',
                        onPressed: _isLoading ? null : _signUp,
                        loading: _isLoading,
                        leading: Icons.person_add_alt_1_rounded,
                        kind: AdButtonKind.primary,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isLoading ? null : () => Get.back(),
                        child: const Text('Déjà un compte ? Se connecter'),
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

  String? _validateName(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'Le nom est requis';
    }
    if (!RegExp(r"^[A-Za-zÀ-ÿ\s'’-]+$").hasMatch(normalized)) {
      return 'Nom invalide';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'Email requis';
    }
    if (!RegExp(r'^[\w\.\-+]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(normalized)) {
      return 'Email invalide';
    }
    return null;
  }
}
