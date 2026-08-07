part of 'smart_video_player.dart';

class _VideoActionConfirmationSheet extends StatelessWidget {
  const _VideoActionConfirmationSheet({
    required this.icon,
    required this.title,
    required this.message,
    required this.badgeLabel,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.toneColor,
    required this.primaryForegroundColor,
    required this.onConfirm,
  });

  final IconData icon;
  final String title;
  final String message;
  final String badgeLabel;
  final String primaryLabel;
  final String secondaryLabel;
  final Color toneColor;
  final Color primaryForegroundColor;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.43,
      minChildSize: 0.34,
      maxChildSize: 0.72,
      expand: false,
      builder: (context, scrollController) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AdColors.surfaceCard,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AdRadius.xl),
                ),
                border: Border.all(color: AdColors.divider),
                boxShadow: AdShadows.card(AdColors.black),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AdSpacing.xl,
                    AdSpacing.md,
                    AdSpacing.xl,
                    AdSpacing.xl,
                  ),
                  child: Semantics(
                    namesRoute: true,
                    label: title,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AdColors.onSurfaceMuted
                                  .withValues(alpha: .35),
                              borderRadius:
                                  BorderRadius.circular(AdRadius.pill),
                            ),
                          ),
                        ),
                        const SizedBox(height: AdSpacing.xl),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: toneColor.withValues(alpha: .14),
                                borderRadius:
                                    BorderRadius.circular(AdRadius.lg),
                              ),
                              child: Icon(icon, color: toneColor, size: 28),
                            ),
                            const SizedBox(width: AdSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ActionBadge(
                                    label: badgeLabel,
                                    color: toneColor,
                                  ),
                                  const SizedBox(height: AdSpacing.sm),
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: AdColors.onSurface,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AdSpacing.md),
                        Text(
                          message,
                          style: const TextStyle(
                            color: AdColors.onSurfaceMuted,
                            fontSize: 15,
                            height: 1.42,
                          ),
                        ),
                        const SizedBox(height: AdSpacing.xl),
                        FilledButton.icon(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await onConfirm();
                          },
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: toneColor,
                            foregroundColor: primaryForegroundColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AdSpacing.lg,
                              vertical: AdSpacing.md,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AdRadius.md),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          icon: Icon(icon, size: 20),
                          label: Text(
                            primaryLabel,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: AdSpacing.sm),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            foregroundColor: AdColors.onSurface,
                            side: const BorderSide(color: AdColors.divider),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AdRadius.md),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          child: Text(secondaryLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VideoCaptionSheet extends StatelessWidget {
  const _VideoCaptionSheet({
    required this.publisherName,
    required this.description,
    required this.caption,
  });

  final String publisherName;
  final String description;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.28,
      maxChildSize: 0.76,
      expand: false,
      builder: (context, scrollController) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AdColors.surfaceCard,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AdRadius.xl),
                ),
                border: Border.all(color: AdColors.divider),
                boxShadow: AdShadows.card(AdColors.black),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AdSpacing.xl,
                    AdSpacing.md,
                    AdSpacing.xl,
                    AdSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color:
                                AdColors.onSurfaceMuted.withValues(alpha: .35),
                            borderRadius: BorderRadius.circular(AdRadius.pill),
                          ),
                        ),
                      ),
                      const SizedBox(height: AdSpacing.xl),
                      const Text(
                        VideoUiStrings.videoCaptionSheetTitle,
                        style: TextStyle(
                          color: AdColors.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (publisherName.isNotEmpty) ...[
                        const SizedBox(height: AdSpacing.xs),
                        Text(
                          publisherName,
                          style: const TextStyle(
                            color: AdColors.brand,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: AdSpacing.md),
                        Text(
                          description,
                          style: const TextStyle(
                            color: AdColors.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.32,
                          ),
                        ),
                      ],
                      const SizedBox(height: AdSpacing.md),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: AdColors.onSurfaceMuted,
                          fontSize: 15,
                          height: 1.48,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionBadge extends StatelessWidget {
  const _ActionBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AdRadius.pill),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AdSpacing.sm,
          vertical: AdSpacing.xxs,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
