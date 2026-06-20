import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/config/app_routes.dart';
import 'package:adfoot/controller/offre_controller.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/screens/chat_screen.dart';
import 'package:adfoot/screens/offres_form.dart';
import 'package:adfoot/screens/profile_screen.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:adfoot/widgets/ad_app_bar.dart';
import 'package:adfoot/widgets/ad_button.dart';
import 'package:adfoot/widgets/ad_dialogs.dart';
import 'package:adfoot/widgets/ad_feedback.dart';
import 'package:adfoot/widgets/ad_state_panel.dart';
import 'package:adfoot/widgets/ad_system_notice.dart';
import 'package:adfoot/widgets/contact_intake_sheet.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

// Palette
import 'package:adfoot/theme/ad_colors.dart';
import 'package:adfoot/theme/ad_tokens.dart';

part 'offre_screen_widgets.dart';

class OffreScreen extends StatefulWidget {
  const OffreScreen({super.key});

  @override
  State<OffreScreen> createState() => _OffreScreenState();
}

class _OffreScreenState extends State<OffreScreen> {
  final OffreController offreController = Get.find<OffreController>();
  final UserController userController = Get.find<UserController>();
  final ChatController chatController = Get.find<ChatController>();

  final TextEditingController _searchController = TextEditingController();

  String _selectedStatus = 'tous';
  final String _selectedRole = 'tous';
  String _sort = 'recentes';
  bool _onlyMine = false;
  bool _onlyExpiringSoon = false;

  /// Anti-spam: only one view counted per offer per session.
  final Set<String> _viewedOffres = <String>{};
  final Set<String> _pendingOfferActions = <String>{};
  AdSystemNoticeData? _systemNotice;
  bool _hasCapturedRouteNotice = false;
  static const int _expiringSoonDays = 7;

  String _normalizeStatus(String rawStatus) {
    final value = rawStatus.trim().toLowerCase();
    switch (value) {
      case 'ouverte':
        return 'ouverte';
      case 'fermee':
      case 'fermée':
        return 'fermee';
      case 'archivee':
      case 'archivée':
        return 'archivee';
      case 'brouillon':
        return 'brouillon';
      default:
        return value;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureRouteSystemNotice();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AdAppBar(
        title: 'Offres',
        subtitle: 'Opportunites, candidatures et suivi',
        showBottomDivider: true,
      ),
      body: Obx(() {
        final currentUser = userController.user;
        final allOffres = offreController.offres;
        final offres = _filteredOffres(allOffres, currentUser);
        final canLoadMoreOffres = offreController.hasMoreOffres;

        if (offreController.isLoading && allOffres.isEmpty) {
          return _buildSkeletons();
        }

        if (allOffres.isEmpty) {
          return Column(
            children: [
              _buildSystemNoticeSlot(),
              Expanded(
                child: _buildEmptyState(currentUser, filteredOut: false),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildSystemNoticeSlot(),
            _buildOffersOverview(allOffres, offres, currentUser),
            _buildFilters(currentUser),
            Expanded(
              child: offres.isEmpty
                  ? _buildEmptyState(
                      currentUser,
                      filteredOut: true,
                      canLoadMore: canLoadMoreOffres,
                      isLoadingMore: offreController.isLoadingMore,
                    )
                  : ListView.builder(
                      itemCount: offres.length + (canLoadMoreOffres ? 1 : 0),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
                      itemBuilder: (context, index) {
                        if (index == offres.length) {
                          return _buildLoadMoreFooter();
                        }

                        final cs = Theme.of(context).colorScheme;
                        final offre = offres[index];

                        // =========================================================
                        // View increment with anti-rebuild protection.
                        // =========================================================
                        if (currentUser != null &&
                            currentUser.uid != offre.recruteur.uid &&
                            !_viewedOffres.contains(offre.id)) {
                          _viewedOffres.add(offre.id);

                          // Fire-and-forget to keep UI responsive.
                          offreController.incrementVues(
                            offre: offre,
                            viewer: currentUser,
                          );
                        }

                        final isOwner = currentUser?.uid == offre.recruteur.uid;
                        final isPostulable =
                            currentUser?.role == 'joueur' &&
                            _normalizeStatus(offre.statut) == 'ouverte';

                        return Card(
                          color: AdColors.surfaceCard,
                          clipBehavior: Clip.antiAlias,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: AdColors.divider),
                          ),
                          elevation: 0,
                          child: InkWell(
                            onTap: () => _showOfferDetails(
                              context,
                              offre,
                              isOwner,
                              isPostulable,
                              currentUser,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRecruteurSection(context, offre),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              offre.titre,
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w800,
                                                color: cs.onSurface,
                                                height: 1.18,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              offre.description,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: AdColors.onSurfaceMuted,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _StatusBadge(status: offre.statut),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (offreController.isLoading)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 8),
                                          child: LinearProgressIndicator(
                                            minHeight: 2,
                                          ),
                                        ),
                                      if (offre.posteRecherche?.isNotEmpty ??
                                          false)
                                        _buildChip(
                                          Icons.sports_soccer,
                                          offre.posteRecherche!,
                                        ),
                                      if (offre.niveau?.isNotEmpty ?? false)
                                        _buildChip(
                                          Icons.star_border,
                                          offre.niveau!,
                                        ),
                                      if (offre.localisation?.isNotEmpty ??
                                          false)
                                        _buildChip(
                                          Icons.place_outlined,
                                          offre.localisation!,
                                        ),
                                      if (offre.remuneration?.isNotEmpty ??
                                          false)
                                        _buildChip(
                                          Icons.payments_outlined,
                                          offre.remuneration!,
                                        ),
                                      if (_isExpired(offre))
                                        _buildAlertChip(
                                          Icons.timer_off_outlined,
                                          'Expirée',
                                          AdColors.error,
                                        )
                                      else if (_isExpiringSoon(offre))
                                        _buildAlertChip(
                                          Icons.schedule_rounded,
                                          _expirySummary(offre),
                                          AdColors.warning,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildValidityRow(offre),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      _OfferInlineStat(
                                        icon: Icons.remove_red_eye_outlined,
                                        label: '${offre.vues ?? 0} vues',
                                      ),
                                      _OfferInlineStat(
                                        icon: Icons.group_outlined,
                                        label:
                                            '${offre.candidats.length} candidatures',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildActionButtons(
                                    context,
                                    offre,
                                    isOwner,
                                    isPostulable,
                                    currentUser,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      }),
      floatingActionButton: _buildFloatingButton(),
    );
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus = 'tous';
      _sort = 'recentes';
      _onlyMine = false;
      _onlyExpiringSoon = false;
    });
  }

  void _captureRouteSystemNotice() {
    if (!mounted || _hasCapturedRouteNotice) return;
    _hasCapturedRouteNotice = true;

    final args = Get.arguments;
    if (args is! Map) return;

    final message = args['offerSystemNoticeMessage']?.toString().trim();
    if (message == null || message.isEmpty) return;

    final title = args['offerSystemNoticeTitle']?.toString().trim();
    final kind = args['offerSystemNoticeKind']?.toString().trim();
    _showSystemNotice(
      title: title == null || title.isEmpty ? 'Action confirmée' : title,
      message: message,
      tone: kind == 'info'
          ? AdSystemNoticeTone.info
          : AdSystemNoticeTone.success,
    );
  }

  Future<void> _openCreateOfferForm() async {
    final result = await Get.to(() => const OffreFormScreen());
    _handleOfferFormResult(result);
  }

  Future<void> _openEditOfferForm(Offre offre) async {
    final result = await Get.to(
      () => const OffreFormScreen(),
      arguments: offre,
    );
    _handleOfferFormResult(result);
  }

  void _handleOfferFormResult(Object? result) {
    if (result == null || !mounted) return;

    if (result is OffreFormResult) {
      _showSystemNotice(
        title: result.title,
        message: result.message,
        tone: result.kind == 'info'
            ? AdSystemNoticeTone.info
            : AdSystemNoticeTone.success,
      );
      return;
    }

    if (result is Map) {
      final message = result['offerSystemNoticeMessage']?.toString().trim();
      if (message == null || message.isEmpty) return;
      final title = result['offerSystemNoticeTitle']?.toString().trim();
      final kind = result['offerSystemNoticeKind']?.toString().trim();
      _showSystemNotice(
        title: title == null || title.isEmpty ? 'Action confirmée' : title,
        message: message,
        tone: kind == 'info'
            ? AdSystemNoticeTone.info
            : AdSystemNoticeTone.success,
      );
      return;
    }

    if (result == true) {
      _showSystemNotice(
        title: 'Offre enregistrée',
        message: 'La liste des offres a été mise à jour.',
      );
    }
  }

  void _showSystemNotice({
    required String title,
    required String message,
    AdSystemNoticeTone tone = AdSystemNoticeTone.success,
  }) {
    final resolvedTitle = title.trim();
    final resolvedMessage = message.trim();
    if (!mounted || resolvedMessage.isEmpty) return;

    setState(() {
      _systemNotice = AdSystemNoticeData(
        title: resolvedTitle.isEmpty ? 'Action confirmée' : resolvedTitle,
        message: resolvedMessage,
        tone: tone,
      );
    });
  }

  void _dismissSystemNotice() {
    if (!mounted || _systemNotice == null) return;
    setState(() => _systemNotice = null);
  }

  void _handleActionResponse(
    ActionResponse response, {
    required String successTitle,
  }) {
    if (response.toast == ToastLevel.none) {
      return;
    }

    if (response.success) {
      _showSystemNotice(title: successTitle, message: response.message);
      return;
    }

    if (response.toast == ToastLevel.info) {
      AdFeedback.info('Information', response.message);
      return;
    }

    AdFeedback.error('Erreur', response.message);
  }

  bool get _hasActiveFilters {
    return _searchController.text.trim().isNotEmpty ||
        _selectedStatus != 'tous' ||
        _sort != 'recentes' ||
        _onlyMine ||
        _onlyExpiringSoon;
  }

  String _offerActionKey(Offre offre, String action) => '${offre.id}:$action';

  bool _isOfferActionPending(Offre offre, String action) {
    return _pendingOfferActions.contains(_offerActionKey(offre, action));
  }

  Future<ActionResponse?> _runOfferAction({
    required Offre offre,
    required String action,
    required Future<ActionResponse> Function() task,
  }) async {
    final key = _offerActionKey(offre, action);
    if (_pendingOfferActions.contains(key)) {
      return null;
    }

    if (mounted) {
      setState(() => _pendingOfferActions.add(key));
    } else {
      _pendingOfferActions.add(key);
    }

    try {
      return await task();
    } finally {
      if (mounted) {
        setState(() => _pendingOfferActions.remove(key));
      } else {
        _pendingOfferActions.remove(key);
      }
    }
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  int _daysUntilEnd(Offre offre) {
    return _dateOnly(
      offre.dateFin,
    ).difference(_dateOnly(DateTime.now())).inDays;
  }

  bool _isExpired(Offre offre) {
    return _daysUntilEnd(offre) < 0;
  }

  bool _isExpiringSoon(Offre offre) {
    final days = _daysUntilEnd(offre);
    return days >= 0 && days <= _expiringSoonDays;
  }

  bool _isOfferOpenForApplications(Offre offre) {
    return _normalizeStatus(offre.statut) == 'ouverte' && !_isExpired(offre);
  }

  String _expirySummary(Offre offre) {
    final days = _daysUntilEnd(offre);
    if (days < 0) return 'Expirée';
    if (days == 0) return 'Dernier jour';
    if (days == 1) return 'Expire demain';
    if (days <= _expiringSoonDays) return 'Expire dans $days jours';
    return 'Encore $days jours';
  }

  // =========================================================
  // Filtering / sorting
  // =========================================================
  List<Offre> _filteredOffres(List<Offre> source, AppUser? currentUser) {
    final query = _searchController.text.toLowerCase().trim();

    List<Offre> filtered = source.where((o) {
      final matchesSearch =
          query.isEmpty ||
          o.titre.toLowerCase().contains(query) ||
          o.description.toLowerCase().contains(query) ||
          (o.posteRecherche ?? '').toLowerCase().contains(query) ||
          (o.localisation ?? '').toLowerCase().contains(query) ||
          (o.niveau ?? '').toLowerCase().contains(query) ||
          (o.remuneration ?? '').toLowerCase().contains(query) ||
          o.recruteur.nom.toLowerCase().contains(query) ||
          o.recruteur.role.toLowerCase().contains(query);

      final matchesStatus = _selectedStatus == 'tous'
          ? true
          : _normalizeStatus(o.statut) == _selectedStatus;

      final matchesRole = _selectedRole == 'tous'
          ? true
          : o.recruteur.role == _selectedRole;

      final matchesMine =
          !_onlyMine ||
          (currentUser != null && o.recruteur.uid == currentUser.uid);

      final matchesExpiring = !_onlyExpiringSoon || _isExpiringSoon(o);

      return matchesSearch &&
          matchesStatus &&
          matchesRole &&
          matchesMine &&
          matchesExpiring;
    }).toList();

    if (_sort == 'fin') {
      filtered.sort((a, b) => a.dateFin.compareTo(b.dateFin));
    } else {
      filtered.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
    }

    return filtered;
  }

  // =========================================================
  // UI builders
  // =========================================================
  Widget _buildSkeletons() {
    return ListView.builder(
      itemCount: 3,
      padding: const EdgeInsets.all(12),
      itemBuilder: (_, _) => Card(
        color: AdColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AdColors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 14, width: 120, color: AdColors.surfaceCardAlt),
              const SizedBox(height: 10),
              Container(
                height: 16,
                width: double.infinity,
                color: AdColors.surfaceCardAlt,
              ),
              const SizedBox(height: 8),
              Container(
                height: 16,
                width: double.infinity,
                color: AdColors.surfaceCardAlt,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemNoticeSlot() {
    final notice = _systemNotice;

    return AnimatedSwitcher(
      duration: AdMotion.normal,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: notice == null
          ? const SizedBox.shrink(key: ValueKey<String>('offer-notice-empty'))
          : Padding(
              key: ValueKey<String>(
                'offer-notice-${notice.title}-${notice.message}',
              ),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: AdSystemNotice(
                notice: notice,
                onDismiss: _dismissSystemNotice,
              ),
            ),
    );
  }

  Widget _buildOffersOverview(
    List<Offre> allOffres,
    List<Offre> filteredOffres,
    AppUser? currentUser,
  ) {
    final isPublisher = isOpportunityPublisherRole(currentUser?.role);
    final openCount = allOffres
        .where((offre) => _isOfferOpenForApplications(offre))
        .length;
    final expiringCount = allOffres
        .where((offre) => _isExpiringSoon(offre))
        .length;
    final totalCandidates = allOffres.fold<int>(
      0,
      (total, offre) => total + offre.candidats.length,
    );
    final ownedOffers = currentUser == null
        ? <Offre>[]
        : allOffres
              .where((offre) => offre.recruteur.uid == currentUser.uid)
              .toList();
    final myOffers = ownedOffers.length;
    final myCandidates = ownedOffers.fold<int>(
      0,
      (total, offre) => total + offre.candidats.length,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        color: AdColors.surface,
        border: Border(bottom: BorderSide(color: AdColors.divider)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AdColors.brand.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AdRadius.md),
                      border: Border.all(
                        color: AdColors.brand.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.local_offer_outlined,
                      color: AdColors.brand,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offres disponibles',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AdColors.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isPublisher
                              ? 'Gérez vos publications et suivez les candidatures.'
                              : 'Repérez rapidement les opportunités ouvertes.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AdColors.onSurfaceMuted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _OfferMetric(
                    icon: Icons.filter_list_rounded,
                    label: 'Affichées',
                    value: '${filteredOffres.length}/${allOffres.length}',
                  ),
                  _OfferMetric(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Ouvertes',
                    value: '$openCount',
                  ),
                  _OfferMetric(
                    icon: Icons.schedule_rounded,
                    label: 'Urgentes',
                    value: '$expiringCount',
                  ),
                  _OfferMetric(
                    icon: isPublisher
                        ? Icons.manage_accounts_outlined
                        : Icons.group_outlined,
                    label: isPublisher ? 'Mes offres' : 'Candidatures',
                    value: '${isPublisher ? myOffers : totalCandidates}',
                  ),
                  if (isPublisher)
                    _OfferMetric(
                      icon: Icons.mark_email_unread_outlined,
                      label: 'Reçues',
                      value: '$myCandidates',
                    ),
                ],
              ),
              if (isPublisher) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AdButton(
                      onPressed: () => setState(() => _onlyMine = !_onlyMine),
                      leading: _onlyMine
                          ? Icons.public_rounded
                          : Icons.manage_accounts_outlined,
                      label: _onlyMine ? 'Toutes les offres' : 'Mes offres',
                      kind: AdButtonKind.outline,
                      size: AdButtonSize.compact,
                      expanded: false,
                    ),
                    AdButton(
                      onPressed: () {
                        _openCreateOfferForm();
                      },
                      leading: Icons.add_rounded,
                      label: 'Créer une offre',
                      size: AdButtonSize.compact,
                      expanded: false,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    dynamic currentUser, {
    required bool filteredOut,
    bool canLoadMore = false,
    bool isLoadingMore = false,
  }) {
    final isPublisher = isOpportunityPublisherRole(currentUser?.role);
    final shouldLoadMore = filteredOut && canLoadMore;
    final actionLabel = shouldLoadMore
        ? isLoadingMore
              ? 'Chargement...'
              : 'Charger plus d’offres'
        : filteredOut
        ? 'Réinitialiser les filtres'
        : isPublisher
        ? 'Créer une offre'
        : 'Explorer les vidéos';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AdStatePanel(
          icon: Icons.search_off,
          title: filteredOut ? 'Aucun résultat' : 'Aucune offre disponible',
          message: filteredOut
              ? 'Aucune offre ne correspond aux filtres actuels.'
              : isPublisher
              ? 'Publiez votre première offre pour démarrer.'
              : 'Revenez plus tard ou explorez les vidéos de talents.',
          action: AdButton(
            expanded: false,
            label: actionLabel,
            loading: shouldLoadMore && isLoadingMore,
            leading: shouldLoadMore ? Icons.expand_more_rounded : null,
            onPressed: isLoadingMore
                ? null
                : () {
                    if (shouldLoadMore) {
                      offreController.loadMoreOffres();
                      return;
                    }

                    if (filteredOut) {
                      _resetFilters();
                      return;
                    }

                    if (isPublisher) {
                      _openCreateOfferForm();
                      return;
                    }

                    Get.offAllNamed(AppRoutes.main, arguments: {'tab': 0});
                  },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadMoreFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
      child: Center(
        child: AdButton(
          expanded: false,
          kind: AdButtonKind.outline,
          size: AdButtonSize.compact,
          leading: Icons.expand_more_rounded,
          loading: offreController.isLoadingMore,
          label: offreController.isLoadingMore
              ? 'Chargement...'
              : 'Charger plus d’offres',
          onPressed: offreController.isLoadingMore
              ? null
              : () {
                  offreController.loadMoreOffres();
                },
        ),
      ),
    );
  }

  Widget _buildFilters(AppUser? currentUser) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: const BoxDecoration(
        color: AdColors.surfaceAlt,
        border: Border(bottom: BorderSide(color: AdColors.divider)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: 'Rechercher titre, poste, lieu, recruteur...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer la recherche',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  // Keep theme-driven input styling.
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Toutes',
                      selected: _selectedStatus == 'tous',
                      onTap: () => setState(() => _selectedStatus = 'tous'),
                    ),
                    _FilterChip(
                      label: 'Ouvertes',
                      selected: _selectedStatus == 'ouverte',
                      onTap: () => setState(() => _selectedStatus = 'ouverte'),
                    ),
                    _FilterChip(
                      label: 'Fermées',
                      selected: _selectedStatus == 'fermee',
                      onTap: () => setState(() => _selectedStatus = 'fermee'),
                    ),
                    _FilterChip(
                      label: 'Archivées',
                      selected: _selectedStatus == 'archivee',
                      onTap: () => setState(() => _selectedStatus = 'archivee'),
                    ),
                    if (currentUser != null) ...[
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Mes offres',
                        selected: _onlyMine,
                        onTap: () => setState(() => _onlyMine = !_onlyMine),
                      ),
                    ],
                    _FilterChip(
                      label: 'Expire bientôt',
                      selected: _onlyExpiringSoon,
                      onTap: () => setState(
                        () => _onlyExpiringSoon = !_onlyExpiringSoon,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AdColors.surfaceCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AdColors.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _sort,
                          underline: const SizedBox.shrink(),
                          dropdownColor: AdColors.surfaceCard,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'recentes',
                              child: Text('Plus récentes'),
                            ),
                            DropdownMenuItem(
                              value: 'fin',
                              child: Text('Se terminant bientôt'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _sort = v);
                          },
                        ),
                      ),
                    ),
                    if (_hasActiveFilters)
                      TextButton.icon(
                        onPressed: _resetFilters,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Réinitialiser'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: cs.primary),
      label: Text(label, style: TextStyle(color: cs.onSurface)),
      backgroundColor: AdColors.surfaceCard,
      side: const BorderSide(color: AdColors.divider),
    );
  }

  Widget _buildAlertChip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }

  Widget _buildValidityRow(Offre offre) {
    final expired = _isExpired(offre);
    final expiringSoon = _isExpiringSoon(offre);
    final color = expired
        ? AdColors.error
        : expiringSoon
        ? AdColors.warning
        : AdColors.onSurfaceMuted;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdColors.divider),
      ),
      child: Row(
        children: [
          Icon(
            expired ? Icons.timer_off_outlined : Icons.event,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "Valide jusqu’au : ${DateFormat('dd MMM yyyy').format(offre.dateFin)} · ${_expirySummary(offre)}",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: expired || expiringSoon ? FontWeight.w700 : null,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailTile(IconData icon, String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AdColors.brand),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdColors.onSurfaceMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdColors.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AdColors.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  bool _isValidPhotoUrl(String? url) {
    if (url == null) return false;
    final t = url.trim();
    return t.isNotEmpty &&
        (t.startsWith('http://') || t.startsWith('https://'));
  }

  Widget _buildRecruteurSection(BuildContext context, Offre offre) {
    final cs = Theme.of(context).colorScheme;
    final bool valid = _isValidPhotoUrl(offre.recruteur.photoProfil);

    return Row(
      children: [
        GestureDetector(
          onTap: () {
            Get.to(
              () => ProfileScreen(uid: offre.recruteur.uid, isReadOnly: true),
            );
          },
          child: CircleAvatar(
            radius: 25,
            backgroundColor: AdColors.surfaceCardAlt,
            backgroundImage: valid
                ? NetworkImage(offre.recruteur.photoProfil)
                : null,
            child: valid
                ? null
                : const Icon(Icons.person, color: Colors.white70),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                offre.recruteur.nom,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              Text(
                offre.recruteur.role,
                style: const TextStyle(
                  fontSize: 14,
                  color: AdColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    Offre offre,
    bool isOwner,
    bool isPostulable,
    AppUser? currentUser,
  ) {
    if (isOwner) {
      final normalizedStatus = _normalizeStatus(offre.statut);
      final statusPending = _isOfferActionPending(offre, 'status');
      final deletePending = _isOfferActionPending(offre, 'delete');
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: normalizedStatus,
            dropdownColor: AdColors.surfaceCard,
            items: const [
              DropdownMenuItem(value: 'brouillon', child: Text('Brouillon')),
              DropdownMenuItem(value: 'ouverte', child: Text('Ouverte')),
              DropdownMenuItem(value: 'fermee', child: Text('Fermée')),
              DropdownMenuItem(value: 'archivee', child: Text('Archivée')),
            ],
            onChanged: statusPending
                ? null
                : (v) async {
                    if (v != null) {
                      if (v == normalizedStatus) return;
                      if (currentUser == null) {
                        AdFeedback.error(
                          'Erreur',
                          'Utilisateur introuvable. Merci de vous reconnecter.',
                        );
                        return;
                      }
                      final response = await _runOfferAction(
                        offre: offre,
                        action: 'status',
                        task: () => offreController.changerStatut(
                          offre,
                          v,
                          currentUser,
                        ),
                      );
                      if (response != null) {
                        _handleActionResponse(
                          response,
                          successTitle: 'Statut mis à jour',
                        );
                      }
                    }
                  },
          ),
          if (statusPending)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          TextButton.icon(
            onPressed: () => _openEditOfferForm(offre),
            icon: const Icon(Icons.edit),
            label: const Text('Modifier'),
          ),
          TextButton.icon(
            onPressed: deletePending
                ? null
                : () => _confirmDelete(context, offre),
            icon: deletePending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete, color: Colors.red),
            label: Text(deletePending ? 'Suppression...' : 'Supprimer'),
          ),
          AdButton(
            onPressed: () => _showCandidats(context, offre),
            leading: Icons.group,
            label: 'Voir candidats',
            size: AdButtonSize.compact,
            expanded: false,
          ),
        ],
      );
    }

    if (isPostulable) {
      final bool inscrit = offre.candidats.any(
        (c) => c.uid == currentUser?.uid,
      );
      final expired = _isExpired(offre);
      final candidatePending = _isOfferActionPending(offre, 'candidate');
      final canSubmitCandidateAction =
          !candidatePending && (inscrit || _isOfferOpenForApplications(offre));

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AdButton(
            onPressed: canSubmitCandidateAction
                ? () async {
                    if (currentUser == null) {
                      AdFeedback.error(
                        'Erreur',
                        'Utilisateur introuvable. Merci de vous reconnecter.',
                      );
                      return;
                    }

                    final response = await _runOfferAction(
                      offre: offre,
                      action: 'candidate',
                      task: () => inscrit
                          ? offreController.seDesinscrireOffre(
                              currentUser,
                              offre,
                            )
                          : offreController.postulerOffre(currentUser, offre),
                    );

                    if (response != null) {
                      _handleActionResponse(
                        response,
                        successTitle: inscrit
                            ? 'Candidature retirée'
                            : 'Candidature envoyée',
                      );
                    }
                  }
                : null,
            loading: candidatePending,
            leading: inscrit
                ? Icons.person_remove_outlined
                : Icons.send_outlined,
            label: inscrit
                ? 'Se désinscrire'
                : expired
                ? 'Offre expirée'
                : 'Postuler',
            kind: inscrit ? AdButtonKind.outline : AdButtonKind.primary,
            size: AdButtonSize.compact,
            expanded: false,
          ),
          AdButton(
            onPressed: () => _openOfferChat(offre.recruteur, offre),
            leading: Icons.chat_bubble_outline,
            label: 'Contacter',
            kind: AdButtonKind.tonal,
            size: AdButtonSize.compact,
            expanded: false,
          ),
        ],
      );
    }

    if (currentUser != null && currentUser.uid != offre.recruteur.uid) {
      return AdButton(
        onPressed: () => _openOfferChat(offre.recruteur, offre),
        leading: Icons.chat_bubble_outline,
        label: 'Contacter',
        kind: AdButtonKind.tonal,
        size: AdButtonSize.compact,
        expanded: false,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFloatingButton() {
    final currentUser = userController.user;
    if (isOpportunityPublisherRole(currentUser?.role)) {
      return FloatingActionButton(
        onPressed: () {
          _openCreateOfferForm();
        },
        backgroundColor: AdColors.brand,
        foregroundColor: AdColors.brandOn,
        child: const Icon(Icons.add),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _confirmDelete(BuildContext context, Offre offre) async {
    if (_isOfferActionPending(offre, 'delete')) return;

    final confirmed = await AdDialogs.confirm(
      context: context,
      title: 'Supprimer cette offre',
      message: 'Voulez-vous vraiment supprimer cette offre ?',
      confirmLabel: 'Supprimer',
      cancelLabel: 'Annuler',
      danger: true,
    );
    if (!confirmed) return;

    final currentUser = userController.user;
    if (currentUser == null) {
      AdFeedback.error(
        'Erreur',
        'Utilisateur introuvable. Merci de vous reconnecter.',
      );
      return;
    }

    final response = await _runOfferAction(
      offre: offre,
      action: 'delete',
      task: () => offreController.supprimerOffre(offre.id, currentUser, offre),
    );
    if (response == null) return;

    if (response.success) {
      if (Get.isBottomSheetOpen ?? false) {
        Get.back();
      }
      _showSystemNotice(
        title: 'Offre supprimée',
        message: response.message.trim().isEmpty
            ? 'L’offre a été supprimée avec succès.'
            : response.message,
      );
    } else if (response.toast == ToastLevel.none) {
      return;
    } else {
      AdFeedback.error('Erreur', response.message);
    }
  }

  Future<void> _openOfferChat(
    AppUser otherUser,
    Offre offre, {
    String sourceLabel = 'Offre',
  }) async {
    final current = userController.user;
    if (current == null) {
      AdFeedback.error(
        'Erreur',
        'Utilisateur introuvable. Merci de vous reconnecter.',
      );
      return;
    }

    if (current.uid == otherUser.uid) {
      await Get.to(() => ProfileScreen(uid: current.uid, isReadOnly: false));
      return;
    }

    if (!current.allowMessages || !otherUser.allowMessages) {
      AdFeedback.warning(
        'Messages indisponibles',
        !current.allowMessages
            ? 'Vous avez désactivé les messages.'
            : 'Cet utilisateur a désactivé les messages.',
      );
      return;
    }

    try {
      final existingConversationId = await chatController
          .findExistingConversationId(
            currentUserId: current.uid,
            otherUserId: otherUser.uid,
          );

      if (existingConversationId != null && existingConversationId.isNotEmpty) {
        await Get.to(
          () => ChatScreen(
            conversationId: existingConversationId,
            otherUser: otherUser,
          ),
        );
        return;
      }

      final draft = await Get.bottomSheet<GuidedContactDraft>(
        ContactIntakeSheet(
          currentUser: current,
          otherUser: otherUser,
          context: ContactContext.offer(
            offerId: offre.id,
            title: offre.titre,
            sourceLabel: sourceLabel,
          ),
        ),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );

      if (draft == null) {
        return;
      }

      final result = await chatController.startGuidedConversation(
        currentUser: current,
        otherUser: otherUser,
        context: draft.context,
        contactReason: draft.reasonCode,
        introMessage: draft.introMessage,
      );

      if (result.createdIntake) {
        AdFeedback.info(
          'Contact enregistré',
          'Le premier contact a été cadré et transmis via Adfoot.',
        );
      }

      final conversationId = result.conversationId.trim();
      if (conversationId.isEmpty) {
        AdFeedback.error('Erreur', 'Conversation indisponible pour le moment.');
        return;
      }

      await Get.to(
        () => ChatScreen(conversationId: conversationId, otherUser: otherUser),
      );
    } on ChatFlowException catch (error) {
      AdFeedback.error('Erreur', error.message);
    } catch (_) {
      AdFeedback.error(
        'Erreur',
        'Impossible de démarrer la conversation pour le moment.',
      );
    }
  }

  void _showOfferDetails(
    BuildContext context,
    Offre offre,
    bool isOwner,
    bool isPostulable,
    AppUser? currentUser,
  ) {
    final validPhoto = _isValidPhotoUrl(offre.recruteur.photoProfil);
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    Get.bottomSheet(
      SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: AdColors.surfaceAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: AdColors.divider)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AdColors.onSurfaceMuted.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(AdRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Get.back();
                        Get.to(
                          () => ProfileScreen(
                            uid: offre.recruteur.uid,
                            isReadOnly: true,
                          ),
                        );
                      },
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: AdColors.surfaceCardAlt,
                        backgroundImage: validPhoto
                            ? NetworkImage(offre.recruteur.photoProfil)
                            : null,
                        child: validPhoto
                            ? null
                            : const Icon(Icons.person, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offre.recruteur.nom,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AdColors.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            offre.recruteur.role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AdColors.onSurfaceMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: offre.statut),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  offre.titre,
                  style: const TextStyle(
                    color: AdColors.onSurface,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                _buildValidityRow(offre),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (offre.posteRecherche?.isNotEmpty ?? false)
                      _buildDetailTile(
                        Icons.sports_soccer,
                        'Poste',
                        offre.posteRecherche!,
                      ),
                    if (offre.niveau?.isNotEmpty ?? false)
                      _buildDetailTile(
                        Icons.leaderboard_outlined,
                        'Niveau',
                        offre.niveau!,
                      ),
                    if (offre.localisation?.isNotEmpty ?? false)
                      _buildDetailTile(
                        Icons.place_outlined,
                        'Lieu',
                        offre.localisation!,
                      ),
                    if (offre.remuneration?.isNotEmpty ?? false)
                      _buildDetailTile(
                        Icons.payments_outlined,
                        'Rémunération',
                        offre.remuneration!,
                      ),
                    _buildDetailTile(
                      Icons.event_available_outlined,
                      'Début',
                      DateFormat('dd MMM yyyy').format(offre.dateDebut),
                    ),
                    _buildDetailTile(
                      Icons.group_outlined,
                      'Candidatures',
                      '${offre.candidats.length}',
                    ),
                    _buildDetailTile(
                      Icons.remove_red_eye_outlined,
                      'Vues',
                      '${offre.vues ?? 0}',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildDetailSectionTitle('Description'),
                const SizedBox(height: 8),
                Text(
                  offre.description,
                  style: const TextStyle(
                    color: AdColors.onSurfaceMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: AdColors.divider, height: 1),
                const SizedBox(height: 16),
                _buildDetailSectionTitle('Actions'),
                const SizedBox(height: 10),
                _buildActionButtons(
                  context,
                  offre,
                  isOwner,
                  isPostulable,
                  currentUser,
                ),
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  void _showCandidats(BuildContext context, Offre offre) {
    String sort = 'nom';

    Get.bottomSheet(
      StatefulBuilder(
        builder: (context, setState) {
          final sorted = [...offre.candidats];
          if (sort == 'role') {
            sorted.sort((a, b) => a.role.compareTo(b.role));
          } else {
            sorted.sort((a, b) => a.nom.compareTo(b.nom));
          }

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AdColors.surfaceAlt,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Liste des candidats',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    DropdownButton<String>(
                      value: sort,
                      dropdownColor: AdColors.surfaceCard,
                      items: const [
                        DropdownMenuItem(value: 'nom', child: Text('Par nom')),
                        DropdownMenuItem(
                          value: 'role',
                          child: Text('Par rôle'),
                        ),
                      ],
                      onChanged: (v) => setState(() => sort = v ?? 'nom'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (sorted.isEmpty)
                  const Text('Aucun candidat pour l’instant')
                else
                  ListView.separated(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const Divider(height: 12),
                    itemBuilder: (_, i) {
                      final candidat = sorted[i];
                      final valid = _isValidPhotoUrl(candidat.photoProfil);

                      return Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AdColors.surfaceCardAlt,
                            backgroundImage: valid
                                ? NetworkImage(candidat.photoProfil)
                                : null,
                            child: valid ? null : const Icon(Icons.person),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  candidat.nom,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  candidat.role,
                                  style: const TextStyle(
                                    color: AdColors.onSurfaceMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline),
                            onPressed: () => _openOfferChat(
                              candidat,
                              offre,
                              sourceLabel: 'Candidats',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }
}
