import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:adfoot/services/app_logger.dart';
import 'package:adfoot/services/legal/terms_acceptance_service.dart';
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_feedback.dart';

/// The gate a signed-in user passes once per version of the terms.
///
/// Deliberately not a dialog. A dialog can be dismissed by a back gesture, a
/// tap outside, or a rebuild, and a consent that can be skipped by accident is
/// not a consent — it is a record that will not survive being questioned. This
/// screen replaces the app's content until the user acts, and the only two
/// ways out are accepting or signing out.
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({
    super.key,
    required this.config,
    required this.onAccept,
    required this.onSignOut,
    this.launchUrlOverride,
  });

  final TermsConfig config;

  /// Records the acceptance. Throws to signal failure; the screen stays.
  final Future<void> Function() onAccept;

  final Future<void> Function() onSignOut;

  /// Test seam: the real implementation opens the browser.
  final Future<bool> Function(Uri url)? launchUrlOverride;

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _isAccepting = false;
  bool _isSigningOut = false;

  /// True once the user has ticked the box confirming they are an adult.
  ///
  /// The terms reserve the service to people aged 18 or over (article 4), and
  /// a rule nobody was ever asked about is a rule that cannot be enforced
  /// afterwards. This is the affirmative declaration article 4.1 refers to.
  bool _confirmsAdult = false;

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    try {
      final launcher = widget.launchUrlOverride;
      final opened = launcher != null
          ? await launcher(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened || !mounted) return;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'could not open a legal document',
        source: 'legal/open_document',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, dynamic>{'url': url},
      );
    }

    if (!mounted) return;
    // Never a dead end: if no browser opens, the address is still readable and
    // can be typed elsewhere. Refusing to accept a text you were unable to
    // read is the reasonable response, and it must remain possible.
    AdFeedback.error(
      'Ouverture impossible',
      'Impossible d’ouvrir le document. Adresse : $url',
    );
  }

  Future<void> _accept() async {
    if (_isAccepting || !_confirmsAdult) return;

    setState(() => _isAccepting = true);
    try {
      await widget.onAccept();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'terms acceptance could not be recorded',
        source: 'legal/accept',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      AdFeedback.error(
        'Enregistrement impossible',
        'Votre acceptation n’a pas pu être enregistrée. '
            'Vérifiez votre réseau puis réessayez.',
      );
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      await widget.onSignOut();
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final busy = _isAccepting || _isSigningOut;

    return PopScope(
      // The whole point of the screen: there is no way past it but through it.
      canPop: false,
      child: Scaffold(
        backgroundColor: AdColors.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                children: [
                  const Icon(
                    Icons.gavel_rounded,
                    size: 44,
                    color: AdColors.brand,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Nos conditions d’utilisation',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AdColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    config.effectiveOn.isEmpty
                        ? 'Version ${config.requiredVersion}'
                        : 'Version ${config.requiredVersion} — '
                              'en vigueur au ${config.effectiveOn}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdColors.onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Avant de continuer, prenez connaissance des conditions '
                    'qui encadrent votre utilisation d’Adfoot et du traitement '
                    'de vos données.',
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.5,
                      color: AdColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _Highlights(),
                  const SizedBox(height: 24),
                  _DocumentLink(
                    label: 'Conditions générales d’utilisation',
                    icon: Icons.description_outlined,
                    onTap: busy ? null : () => _open(config.termsUrl),
                  ),
                  const SizedBox(height: 10),
                  _DocumentLink(
                    label: 'Politique de confidentialité',
                    icon: Icons.privacy_tip_outlined,
                    onTap: busy ? null : () => _open(config.privacyUrl),
                  ),
                  const SizedBox(height: 24),
                  _AdultCheckbox(
                    value: _confirmsAdult,
                    enabled: !busy,
                    onChanged: (value) =>
                        setState(() => _confirmsAdult = value ?? false),
                  ),
                  const SizedBox(height: 24),
                  AdButton(
                    label: 'J’accepte et je continue',
                    loading: _isAccepting,
                    onPressed: (_confirmsAdult && !busy) ? _accept : null,
                  ),
                  const SizedBox(height: 10),
                  AdButton(
                    label: 'Se déconnecter',
                    kind: AdButtonKind.outline,
                    loading: _isSigningOut,
                    onPressed: busy ? null : _signOut,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sans acceptation, votre compte reste créé mais '
                    'l’application ne peut pas être utilisée.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AdColors.onSurfaceMuted,
                    ),
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

/// The three points a user would otherwise only find by reading the whole text.
///
/// Not a substitute for the terms — the full document is one tap away — but
/// the commitments that decide whether someone should trust this platform, put
/// where they will actually be read.
class _Highlights extends StatelessWidget {
  const _Highlights();

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String, String)>[
      (
        Icons.money_off_rounded,
        'Gratuit pour les joueurs',
        'Adfoot ne vous demandera jamais d’argent pour être vu, sélectionné '
            'ou testé. Signalez toute demande de paiement.',
      ),
      (
        Icons.handshake_outlined,
        'Nous ne sommes pas votre agent',
        'Adfoot vous rend visible auprès des clubs et recruteurs, sans '
            'garantir un essai ni un contrat, et sans commission.',
      ),
      (
        Icons.verified_user_outlined,
        'Vos vidéos vous appartiennent',
        'Vous en restez propriétaire. Vous pouvez les retirer, et supprimer '
            'votre compte, à tout moment.',
      ),
    ];

    return Column(
      children: [
        for (final (icon, title, body) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: AdColors.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AdColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.42,
                          color: AdColors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DocumentLink extends StatelessWidget {
  const _DocumentLink({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdColors.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AdColors.onSurfaceMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AdColors.onSurface,
                  ),
                ),
              ),
              const Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: AdColors.onSurfaceMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdultCheckbox extends StatelessWidget {
  const _AdultCheckbox({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: AdColors.brand,
              checkColor: AdColors.brandOn,
            ),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Je déclare avoir 18 ans ou plus et j’accepte les '
                  'conditions générales d’utilisation ainsi que la politique '
                  'de confidentialité.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.42,
                    color: AdColors.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
