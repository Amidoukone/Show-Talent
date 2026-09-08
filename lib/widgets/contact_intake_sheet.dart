import 'dart:math' as math;

import 'package:adfoot/l10n/generated/app_localizations.dart';
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

  List<_ReasonOption> _reasonOptions(AppLocalizations l10n) {
    return <_ReasonOption>[
      _ReasonOption(
        code: ContactReasonCode.opportunity,
        label: ContactIntake.reasonLabel(ContactReasonCode.opportunity),
        description: l10n.contactIntakeSheetReasonOpportunityDescription,
      ),
      _ReasonOption(
        code: ContactReasonCode.trial,
        label: ContactIntake.reasonLabel(ContactReasonCode.trial),
        description: l10n.contactIntakeSheetReasonTrialDescription,
      ),
      _ReasonOption(
        code: ContactReasonCode.application,
        label: ContactIntake.reasonLabel(ContactReasonCode.application),
        description: l10n.contactIntakeSheetReasonApplicationDescription,
      ),
      _ReasonOption(
        code: ContactReasonCode.followUp,
        label: ContactIntake.reasonLabel(ContactReasonCode.followUp),
        description: l10n.contactIntakeSheetReasonFollowUpDescription,
      ),
      _ReasonOption(
        code: ContactReasonCode.information,
        label: ContactIntake.reasonLabel(ContactReasonCode.information),
        description: l10n.contactIntakeSheetReasonInformationDescription,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;
    final bottomInset = media.viewInsets.bottom;
    final availableHeight = math.max(
      260.0,
      media.size.height - bottomInset - media.padding.top - 8,
    );
    final sheetMaxHeight = math.min(media.size.height * 0.92, availableHeight);
    final contextLabel = widget.context.normalizedTitle?.isNotEmpty == true
        ? '${widget.context.displayLabel} - ${widget.context.normalizedTitle}'
        : widget.context.displayLabel;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: sheetMaxHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(
                top: BorderSide(color: cs.outline.withValues(alpha: 0.22)),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    // Guardrail: keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                            l10n.contactIntakeSheetTitle,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.contactIntakeSheetSubtitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
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
                            initialValue: _selectedReason,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l10n.contactIntakeSheetReasonLabel,
                            ),
                            items: _reasonOptions(l10n)
                                .map(
                                  (option) => DropdownMenuItem<String>(
                                    value: option.code,
                                    child: Text(
                                      option.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _selectedReason = value);
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _reasonOptions(l10n)
                                    .firstWhere(
                                      (option) =>
                                          option.code == _selectedReason,
                                      orElse: () => _reasonOptions(l10n).last,
                                    )
                                    .description ??
                                '',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.65),
                                  height: 1.28,
                                ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _introController,
                            maxLength: 280,
                            minLines: 3,
                            maxLines: 5,
                            scrollPadding: const EdgeInsets.only(bottom: 120),
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              labelText: l10n.contactIntakeSheetIntroLabel,
                              hintText: l10n.contactIntakeSheetIntroHint,
                              alignLabelWithHint: true,
                            ),
                            validator: (value) {
                              final normalized = value?.trim() ?? '';
                              if (normalized.length < 12) {
                                return l10n
                                    .contactIntakeSheetIntroTooShortError;
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(
                      top: BorderSide(
                        color: cs.outline.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: AdButton(
                            label: l10n.commonCancel,
                            kind: AdButtonKind.outline,
                            size: AdButtonSize.compact,
                            expanded: false,
                            onPressed: () => Get.back<GuidedContactDraft?>(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AdButton(
                            label: l10n.contactIntakeSheetStartAction,
                            size: AdButtonSize.compact,
                            expanded: false,
                            onPressed: _submit,
                          ),
                        ),
                      ],
                    ),
                  ),
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
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.contactIntakeSheetTargetLabel(targetName, targetRole),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
