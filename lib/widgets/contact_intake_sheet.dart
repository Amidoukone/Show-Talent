import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ContactIntakeSheet extends StatefulWidget {
  const ContactIntakeSheet({
    super.key,
    required this.currentUser,
    required this.otherUser,
    required this.context,
  });

  final AppUser currentUser;
  final AppUser otherUser;
  final ContactContext context;

  @override
  State<ContactIntakeSheet> createState() => _ContactIntakeSheetState();
}

class _ContactIntakeSheetState extends State<ContactIntakeSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _introController = TextEditingController();

  late String _selectedReason;

  @override
  void initState() {
    super.initState();
    _selectedReason = _defaultReason();
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  String _defaultReason() {
    if (widget.currentUser.canPublishOpportunities &&
        widget.otherUser.isPlayer) {
      return ContactReasonCode.opportunity;
    }

    if (widget.currentUser.isPlayer &&
        widget.otherUser.canPublishOpportunities) {
      return ContactReasonCode.application;
    }

    return ContactReasonCode.information;
  }

  List<_ReasonOption> _reasonOptions() {
    return const <_ReasonOption>[
      _ReasonOption(
        code: ContactReasonCode.opportunity,
        label: 'Opportunité',
        description: 'Prise de contact autour d’une opportunité concrète.',
      ),
      _ReasonOption(
        code: ContactReasonCode.trial,
        label: 'Essai / Évaluation',
        description: 'Invitation, observation ou mise à l’essai.',
      ),
      _ReasonOption(
        code: ContactReasonCode.application,
        label: 'Candidature / Présentation',
        description: 'Présentation de profil ou manifestation d’intérêt.',
      ),
      _ReasonOption(
        code: ContactReasonCode.followUp,
        label: 'Suivi',
        description: 'Relance ou suivi d’un échange déjà engagé.',
      ),
      _ReasonOption(
        code: ContactReasonCode.information,
        label: 'Information',
        description: 'Question ou demande de précision.',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final contextLabel = widget.context.normalizedTitle?.isNotEmpty == true
        ? '${widget.context.displayLabel} - ${widget.context.normalizedTitle}'
        : widget.context.displayLabel;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Premier contact guidé',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ce premier échange est cadré pour garder une mise en relation claire et suivie par Adfoot.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.72),
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 16),
                _ContextCard(
                  title: contextLabel,
                  targetName: widget.otherUser.nom,
                  targetRole: widget.otherUser.role,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedReason,
                  decoration: const InputDecoration(
                    labelText: 'Motif du contact',
                  ),
                  items: _reasonOptions()
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option.code,
                          child: Text(option.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _selectedReason = value);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _reasonOptions()
                          .firstWhere(
                            (option) => option.code == _selectedReason,
                            orElse: () => _reasonOptions().last,
                          )
                          .description ??
                      '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _introController,
                  maxLength: 280,
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Message d’introduction',
                    hintText:
                        'Expliquez clairement l’objet du contact et la prochaine étape souhaitée.',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    final normalized = value?.trim() ?? '';
                    if (normalized.length < 12) {
                      return 'Ajoutez un message un peu plus précis.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AdButton(
                        label: 'Annuler',
                        kind: AdButtonKind.outline,
                        expanded: false,
                        onPressed: () => Get.back<GuidedContactDraft?>(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AdButton(
                        label: 'Lancer le contact',
                        expanded: false,
                        onPressed: _submit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Get.back<GuidedContactDraft>(
      result: GuidedContactDraft(
        context: widget.context,
        reasonCode: _selectedReason,
        introMessage: _introController.text.trim(),
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.title,
    required this.targetName,
    required this.targetRole,
  });

  final String title;
  final String targetName;
  final String targetRole;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onPrimaryContainer,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Contact visé : $targetName ($targetRole)',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onPrimaryContainer.withValues(alpha: 0.86),
                ),
          ),
        ],
      ),
    );
  }
}

class _ReasonOption {
  const _ReasonOption({
    required this.code,
    required this.label,
    required this.description,
  });

  final String code;
  final String label;
  final String? description;
}
