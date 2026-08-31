part of 'home_screen.dart';

class _VideoSearchSheet extends StatelessWidget {
  const _VideoSearchSheet({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.isLoading,
    required this.error,
    required this.results,
    required this.userController,
    required this.onChanged,
    required this.onClear,
    required this.onResultSelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final bool isLoading;
  final String? error;
  final List<Video> results;
  final UserController userController;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<Video> onResultSelected;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final availableHeight = math.max(
      300.0,
      media.size.height - bottomInset - media.padding.top - 8,
    );
    final sheetMaxHeight = math.min(media.size.height * 0.86, availableHeight);
    final active = query.trim().isNotEmpty;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 620, maxHeight: sheetMaxHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AdColors.surfaceCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AdRadius.lg),
              ),
              border: Border.all(color: AdColors.divider),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            VideoUiStrings.videoSearchTitle,
                            style: TextStyle(
                              color: AdColors.onSurface,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (active)
                          TextButton.icon(
                            onPressed: onClear,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text(VideoUiStrings.videoSearchClear),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      onChanged: onChanged,
                      textInputAction: TextInputAction.search,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      style: const TextStyle(
                        color: AdColors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      cursorColor: AdColors.brand,
                      decoration: InputDecoration(
                        hintText: VideoUiStrings.videoSearchHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: AdColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AdRadius.md),
                          borderSide: const BorderSide(color: AdColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AdRadius.md),
                          borderSide: const BorderSide(color: AdColors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AdRadius.md),
                          borderSide: const BorderSide(
                            color: AdColors.brand,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(child: _buildContent(active)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool active) {
    if (!active) {
      return const _VideoSearchEmptyHint(
        icon: Icons.manage_search_rounded,
        title: VideoUiStrings.videoSearchOpen,
        message: VideoUiStrings.videoSearchEmptyMessage,
      );
    }

    if (isLoading && results.isEmpty) {
      return const _VideoSearchEmptyHint(
        icon: Icons.search_rounded,
        title: VideoUiStrings.videoSearchLoadingTitle,
        message: VideoUiStrings.videoSearchLoadingMessage,
      );
    }

    if (results.isEmpty) {
      return _VideoSearchEmptyHint(
        icon: Icons.search_off_rounded,
        title: VideoUiStrings.videoSearchEmptyTitle,
        message: error ?? VideoUiStrings.videoSearchEmptyMessage,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          const Divider(color: AdColors.divider, height: 1),
      itemBuilder: (context, index) {
        final video = results[index];
        final author = userController.usersCache[video.uid];
        return _VideoSearchResultTile(
          video: video,
          authorName: (author?.nom ?? '').trim(),
          // L'auteur est deja resolu ici pour son nom : le badge ne coute
          // aucune lecture supplementaire.
          isAgencyPlayer: showsAgencyBadge(author),
          onTap: () => onResultSelected(video),
        );
      },
    );
  }
}

class _VideoSearchEmptyHint extends StatelessWidget {
  const _VideoSearchEmptyHint({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AdColors.brand, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AdColors.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AdColors.onSurfaceMuted,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoSearchResultTile extends StatelessWidget {
  const _VideoSearchResultTile({
    required this.video,
    required this.authorName,
    required this.isAgencyPlayer,
    required this.onTap,
  });

  final Video video;
  final String authorName;
  final bool isAgencyPlayer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = authorName.isNotEmpty
        ? authorName
        : VideoUiStrings.defaultPublisherName;
    final subtitle = video.caption.trim().isNotEmpty
        ? video.caption.trim()
        : video.description.trim();

    return Semantics(
      button: true,
      label: VideoUiStrings.videoSearchResultHint,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AdRadius.sm),
                child: SizedBox(
                  width: 48,
                  height: 68,
                  child: video.thumbnailUrl.trim().isEmpty
                      ? const ColoredBox(
                          color: AdColors.surface,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: AdColors.brand,
                          ),
                        )
                      // Le même magasin que le préchargement du contrôleur :
                      // `Image.network` n'a aucun cache disque et
                      // retéléchargeait chaque miniature à chaque défilement,
                      // puis encore après chaque redémarrage.
                      : CachedNetworkImage(
                          imageUrl: video.thumbnailUrl.trim(),
                          fit: BoxFit.cover,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholder: (_, _) => const ColoredBox(
                            color: AdColors.surface,
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: AdColors.brand,
                            ),
                          ),
                          errorWidget: (_, _, _) => const ColoredBox(
                            color: AdColors.surface,
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: AdColors.brand,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AdColors.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isAgencyPlayer) ...[
                          const SizedBox(width: 6),
                          const AdAgencyBadge(),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AdColors.onSurfaceMuted,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.play_circle_fill_rounded,
                color: AdColors.brand,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
