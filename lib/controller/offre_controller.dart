import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/offers/offer_repository.dart';

class OffreController extends GetxController {
  static OffreController instance = Get.find();
  static const int _offerPageSize = OfferRepository.defaultPageSize;

  OffreController({
    OfferRepository? offerRepository,
    AuthSessionService? authSessionService,
  })  : _offerRepository = offerRepository ?? OfferRepository(),
        _authSessionService = authSessionService ?? AuthSessionService();

  final OfferRepository _offerRepository;
  final AuthSessionService _authSessionService;

  final Rx<List<Offre>> _offres = Rx<List<Offre>>([]);
  List<Offre> get offres => _offres.value;

  final RxBool _isLoading = true.obs;
  bool get isLoading => _isLoading.value;

  final RxBool _isLoadingMore = false.obs;
  bool get isLoadingMore => _isLoadingMore.value;

  final RxBool _hasMoreOffres = false.obs;
  bool get hasMoreOffres => _hasMoreOffres.value;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<OfferLiveBatch>? _offresSubscription;
  OfferFeedCursor? _lastCursor;
  OfferQueryFilter _activeFilter = const OfferQueryFilter();
  String? _activeAuthUid;
  String? _activeOffersQueryKey;
  bool _hasLoadedAdditionalPages = false;

  bool _isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  Future<void> _handleProtectedAccessDenied() async {
    if (!Get.isRegistered<UserController>()) {
      return;
    }

    await Get.find<UserController>().handleProtectedAccessDenied(
      fallbackTitle: 'Accès indisponible',
      fallbackMessage:
          'Votre session a été fermée pour protéger votre compte. Veuillez vous reconnecter.',
    );
  }

  ActionResponse _sessionRevokedResponse() {
    return const ActionResponse(
      success: false,
      code: 'session_revoked',
      message: 'Votre session a été fermée. Veuillez vous reconnecter.',
      toast: ToastLevel.none,
    );
  }

  ActionResponse _offerRepositoryExceptionResponse(
    OfferRepositoryException exception,
  ) {
    return ActionResponse.failure(
      code: exception.code,
      message: exception.message,
      toast: switch (exception.code) {
        'offer_closed' || 'already_applied' || 'not_applied' => ToastLevel.info,
        _ => ToastLevel.error,
      },
    );
  }

  @override
  void onInit() {
    super.onInit();
    _authSub = _authSessionService.idTokenChanges().listen(
      (user) {
        if (user == null) {
          unawaited(_stopOffresStream(clearData: true));
          return;
        }

        _fetchOffres();
      },
      onError: (error) {
        developer.log(
          'Erreur écoute auth pour les offres: $error',
          name: 'OffreController.onInit',
          error: error,
        );
      },
    );

    if (_authSessionService.currentUser != null) {
      _fetchOffres();
    } else {
      _isLoading.value = false;
    }
  }

  @override
  void onClose() {
    _authSub?.cancel();
    _offresSubscription?.cancel();
    super.onClose();
  }

  void _fetchOffres() {
    final currentUid = _authSessionService.currentUser?.uid;
    final queryKey = _activeFilter.cacheKey;
    final hasActiveStream = _offresSubscription != null &&
        _activeAuthUid == currentUid &&
        _activeOffersQueryKey == queryKey;
    if (hasActiveStream) {
      return;
    }

    _activeAuthUid = currentUid;
    _activeOffersQueryKey = queryKey;
    _lastCursor = null;
    _hasLoadedAdditionalPages = false;
    _hasMoreOffres.value = false;
    _isLoadingMore.value = false;
    if (_offres.value.isEmpty) {
      _isLoading.value = true;
    }
    _offresSubscription?.cancel();

    _offresSubscription = _offerRepository
        .watchOffers(limit: _offerPageSize, filter: _activeFilter)
        .listen((batch) {
      _lastCursor = batch.cursor;
      _hasMoreOffres.value =
          batch.cursor != null && batch.fetchedCount >= _offerPageSize;
      if (_hasLoadedAdditionalPages) {
        final mergedById = <String, Offre>{
          for (final offer in _offres.value) offer.id: offer,
        };
        for (final offer in batch.offers) {
          mergedById[offer.id] = offer;
        }
        _offres.value = _sortOffers(mergedById.values);
      } else {
        _offres.value = _sortOffers(batch.offers);
      }
      update();
      _isLoading.value = false;
    }, onError: (error, stackTrace) {
      developer.log(
        'Erreur ecoute Firestore pour les offres: $error',
        name: 'OffreController._fetchOffres',
        error: error,
        stackTrace: stackTrace,
      );
      if (_isPermissionDenied(error)) {
        _offres.value = const <Offre>[];
        final hasResolvedSession = Get.isRegistered<UserController>() &&
            Get.find<UserController>().user != null;
        if (hasResolvedSession && _authSessionService.currentUser != null) {
          unawaited(_handleProtectedAccessDenied());
        }
      }
      _isLoading.value = false;
    });
  }

  Future<void> loadMoreOffres() async {
    if (_isLoadingMore.value || !_hasMoreOffres.value) {
      return;
    }

    final cursor = _lastCursor;
    if (cursor == null) {
      _hasMoreOffres.value = false;
      return;
    }

    _isLoadingMore.value = true;
    try {
      final page = await _offerRepository.fetchOffersPage(
        limit: _offerPageSize,
        startAfter: cursor,
        filter: _activeFilter,
      );

      final mergedById = <String, Offre>{
        for (final offer in _offres.value) offer.id: offer,
      };
      for (final offer in page.offers) {
        mergedById[offer.id] = offer;
      }

      _lastCursor = page.cursor;
      _hasMoreOffres.value =
          page.cursor != null && page.fetchedCount >= _offerPageSize;
      if (page.fetchedCount > 0) {
        _hasLoadedAdditionalPages = true;
      }
      _offres.value = _sortOffers(mergedById.values);
      update();
    } on FirebaseException catch (error, stackTrace) {
      developer.log(
        'Erreur pagination Firestore pour les offres: $error',
        name: 'OffreController.loadMoreOffres',
        error: error,
        stackTrace: stackTrace,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
      }
    } catch (error, stackTrace) {
      developer.log(
        'Erreur pagination offres: $error',
        name: 'OffreController.loadMoreOffres',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _isLoadingMore.value = false;
    }
  }

  Future<void> _stopOffresStream({bool clearData = false}) async {
    await _offresSubscription?.cancel();
    _offresSubscription = null;
    _activeAuthUid = null;
    _activeOffersQueryKey = null;
    _activeFilter = const OfferQueryFilter();
    _lastCursor = null;
    _hasLoadedAdditionalPages = false;
    _hasMoreOffres.value = false;
    _isLoadingMore.value = false;

    if (clearData) {
      _offres.value = const <Offre>[];
      _isLoading.value = false;
      update();
    }
  }

  Future<void> incrementVues({
    required Offre offre,
    required AppUser viewer,
  }) async {
    if (viewer.uid == offre.recruteur.uid) return;

    try {
      await _offerRepository.incrementViews(offer: offre, viewer: viewer);
    } catch (e, st) {
      developer.log(
        'Erreur incrementation vues: $e',
        name: 'OffreController.incrementVues',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<ActionResponse> publierOffre(Offre offre, AppUser utilisateur) async {
    if (!utilisateur.canPublishOpportunities) {
      return ActionResponse.failure(
        code: 'permission-denied',
        message:
            'Seuls les clubs, recruteurs ou agents peuvent publier des offres.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _offerRepository.publishOffer(offre);

      final fanoutResult = await _notifierJoueurs(offre, utilisateur);
      if (!fanoutResult.success) {
        return ActionResponse(
          success: true,
          message:
              'Offre publiée avec succès, mais les notifications sont temporairement indisponibles.',
          code: 'published_notification_failed',
          toast: ToastLevel.info,
        );
      }

      return const ActionResponse(
        success: true,
        code: 'published',
        message: 'Offre publiée avec succès.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors de la publication de l’offre: $error',
        name: 'OffreController.publierOffre',
        error: error,
        stackTrace: st,
      );
      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }
      return ActionResponse.failure(
        code: 'publish_failed',
        message: 'Impossible de publier l’offre pour le moment.',
      );
    } catch (e, st) {
      developer.log(
        'Erreur lors de la publication de l’offre: $e',
        name: 'OffreController.publierOffre',
        error: e,
        stackTrace: st,
      );
      return ActionResponse.failure(
        code: 'publish_failed',
        message: 'Impossible de publier l’offre pour le moment.',
      );
    }
  }

  Future<ActionResponse> _notifierJoueurs(
      Offre offre, AppUser recruteur) async {
    final response = await PushNotificationService.sendOfferFanout(
      offerId: offre.id,
      title: 'Nouvelle offre disponible',
      body: 'Une nouvelle offre a été publiée par ${recruteur.nom}.',
    );

    if (!response.success) {
      developer.log(
        'Erreur lors de l’envoi des notifications offre: ${response.message}',
        name: 'OffreController._notifierJoueurs',
      );
    }

    return response;
  }

  Future<ActionResponse> modifierOffre(Offre offre, AppUser utilisateur) async {
    if (utilisateur.uid != offre.recruteur.uid) {
      return ActionResponse.failure(
        code: 'permission-denied',
        message: 'Vous ne pouvez modifier que vos propres offres.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _offerRepository.updateOffer(offre);
      _replaceLocalOffer(offre);
      return const ActionResponse(
        success: true,
        code: 'updated',
        message: 'Offre modifiée avec succès.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors de la modification de l’offre: $error',
        name: 'OffreController.modifierOffre',
        error: error,
        stackTrace: st,
      );

      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }

      return ActionResponse.failure(
        code: 'update_failed',
        message: 'Impossible de modifier l’offre pour le moment.',
      );
    } catch (e, st) {
      developer.log(
        'Erreur lors de la modification de l’offre: $e',
        name: 'OffreController.modifierOffre',
        error: e,
        stackTrace: st,
      );

      return ActionResponse.failure(
        code: 'update_failed',
        message: 'Impossible de modifier l’offre pour le moment.',
      );
    }
  }

  Future<ActionResponse> changerStatut(
    Offre offre,
    String nouveauStatut,
    AppUser utilisateur,
  ) async {
    if (utilisateur.uid != offre.recruteur.uid) {
      return ActionResponse.failure(
        code: 'permission-denied',
        message: 'Vous ne pouvez modifier que vos propres offres.',
        toast: ToastLevel.info,
      );
    }

    final normalized = Offre.normalizeStatus(nouveauStatut);
    const allowed = <String>{'brouillon', 'ouverte', 'fermee', 'archivee'};
    if (!allowed.contains(normalized)) {
      return ActionResponse.failure(
        code: 'invalid-argument',
        message: 'Statut invalide.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _offerRepository.updateStatus(
        offerId: offre.id,
        status: normalized,
      );
      offre.statut = normalized;
      offre.lastUpdated = DateTime.now();
      _replaceLocalOffer(offre);

      return ActionResponse(
        success: true,
        code: 'status_updated',
        message: 'Le statut est maintenant "$normalized".',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors du changement de statut offre: $error',
        name: 'OffreController.changerStatut',
        error: error,
        stackTrace: st,
      );

      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }

      return ActionResponse.failure(
        code: 'status_update_failed',
        message: 'Impossible de modifier le statut pour le moment.',
      );
    } catch (e, st) {
      developer.log(
        'Erreur lors du changement de statut offre: $e',
        name: 'OffreController.changerStatut',
        error: e,
        stackTrace: st,
      );

      return ActionResponse.failure(
        code: 'status_update_failed',
        message: 'Impossible de modifier le statut pour le moment.',
      );
    }
  }

  Future<ActionResponse> supprimerOffre(
    String offreId,
    AppUser utilisateur,
    Offre offre,
  ) async {
    if (utilisateur.uid != offre.recruteur.uid) {
      return ActionResponse.failure(
        code: 'permission-denied',
        message: 'Vous ne pouvez supprimer que vos propres offres.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _offerRepository.deleteOffer(offreId);
      _removeLocalOffer(offreId);
      return const ActionResponse(
        success: true,
        code: 'deleted',
        message: 'Offre supprimée avec succès.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors de la suppression de l’offre: $error',
        name: 'OffreController.supprimerOffre',
        error: error,
        stackTrace: st,
      );

      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }

      return ActionResponse.failure(
        code: 'delete_failed',
        message: 'Impossible de supprimer l’offre pour le moment.',
      );
    } catch (e, st) {
      developer.log(
        'Erreur lors de la suppression de l’offre: $e',
        name: 'OffreController.supprimerOffre',
        error: e,
        stackTrace: st,
      );

      return ActionResponse.failure(
        code: 'delete_failed',
        message: 'Impossible de supprimer l’offre pour le moment.',
      );
    }
  }

  Future<ActionResponse> postulerOffre(AppUser joueur, Offre offre) async {
    if (joueur.role != 'joueur') {
      return ActionResponse.failure(
        code: 'permission-denied',
        message: 'Seuls les joueurs peuvent postuler à une offre.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _offerRepository.applyToOffer(player: joueur, offer: offre);
      if (!offre.candidats.any((candidate) => candidate.uid == joueur.uid)) {
        offre.candidats.add(joueur);
        _replaceLocalOffer(offre);
      }

      return const ActionResponse(
        success: true,
        code: 'applied',
        message: 'Vous avez postulé à l’offre.',
        toast: ToastLevel.success,
      );
    } on OfferRepositoryException catch (e) {
      return _offerRepositoryExceptionResponse(e);
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors de la postulation offre: $error',
        name: 'OffreController.postulerOffre',
        error: error,
        stackTrace: st,
      );

      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }

      return ActionResponse.failure(
        code: 'apply_failed',
        message: 'Impossible de postuler pour le moment.',
      );
    } catch (e, st) {
      developer.log(
        'Erreur lors de la postulation offre: $e',
        name: 'OffreController.postulerOffre',
        error: e,
        stackTrace: st,
      );

      return ActionResponse.failure(
        code: 'apply_failed',
        message: 'Impossible de postuler pour le moment.',
      );
    }
  }

  Future<ActionResponse> seDesinscrireOffre(AppUser joueur, Offre offre) async {
    if (joueur.role != 'joueur') {
      return ActionResponse.failure(
        code: 'permission-denied',
        message: 'Seuls les joueurs peuvent se désinscrire.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _offerRepository.withdrawFromOffer(player: joueur, offer: offre);
      offre.candidats.removeWhere((candidate) => candidate.uid == joueur.uid);
      _replaceLocalOffer(offre);

      return const ActionResponse(
        success: true,
        code: 'withdrawn',
        message: 'Vous vous êtes désinscrit de l’offre.',
        toast: ToastLevel.success,
      );
    } on OfferRepositoryException catch (e) {
      return _offerRepositoryExceptionResponse(e);
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors de la désinscription offre: $error',
        name: 'OffreController.seDesinscrireOffre',
        error: error,
        stackTrace: st,
      );

      if (_isPermissionDenied(error)) {
        unawaited(_handleProtectedAccessDenied());
        return _sessionRevokedResponse();
      }

      return ActionResponse.failure(
        code: 'withdraw_failed',
        message: 'Impossible de se désinscrire pour le moment.',
      );
    } catch (e, st) {
      developer.log(
        'Erreur lors de la désinscription offre: $e',
        name: 'OffreController.seDesinscrireOffre',
        error: e,
        stackTrace: st,
      );

      return ActionResponse.failure(
        code: 'withdraw_failed',
        message: 'Impossible de se désinscrire pour le moment.',
      );
    }
  }

  List<Offre> _sortOffers(Iterable<Offre> offers) {
    return offers.toList(growable: false)
      ..sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
  }

  void _replaceLocalOffer(Offre offer) {
    final existing = _offres.value;
    final index = existing.indexWhere((candidate) => candidate.id == offer.id);
    if (index == -1) {
      return;
    }

    final next = List<Offre>.from(existing);
    next[index] = offer;
    _offres.value = _sortOffers(next);
    update();
  }

  void _removeLocalOffer(String offerId) {
    final next = _offres.value
        .where((offer) => offer.id != offerId)
        .toList(growable: false);
    if (next.length == _offres.value.length) {
      return;
    }

    _offres.value = next;
    update();
  }
}
