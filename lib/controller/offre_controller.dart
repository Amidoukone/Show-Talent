import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import 'package:adfoot/controller/push_notification.dart';
import 'package:adfoot/controller/user_controller.dart';
import 'package:adfoot/models/action_response.dart';
import 'package:adfoot/models/offre.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';

class _OffreFlowException implements Exception {
  const _OffreFlowException({
    required this.code,
    required this.message,
    this.toast = ToastLevel.error,
  });

  final String code;
  final String message;
  final ToastLevel toast;
}

class OffreController extends GetxController {
  static OffreController instance = Get.find();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthSessionService _authSessionService = AuthSessionService();

  final Rx<List<Offre>> _offres = Rx<List<Offre>>([]);
  List<Offre> get offres => _offres.value;

  final RxBool _isLoading = true.obs;
  bool get isLoading => _isLoading.value;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offresSubscription;
  String? _activeAuthUid;

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

  bool _isOpenStatus(String status) => _normalizeStatus(status) == 'ouverte';

  List<Map<String, dynamic>> _extractCandidateMaps(dynamic raw) {
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }

    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  List<Offre> _parseSnapshotDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    final fetched = <Offre>[];

    for (final doc in docs) {
      try {
        final offre = Offre.fromDoc(doc);
        final normalizedStatus = _normalizeStatus(offre.statut);
        if (offre.statut != normalizedStatus) {
          offre.statut = normalizedStatus;
        }

        if (offre.dateFin.isBefore(now) && _isOpenStatus(offre.statut)) {
          unawaited(
            doc.reference.update({
              'statut': 'fermee',
              'lastUpdated': FieldValue.serverTimestamp(),
            }).catchError((error, stackTrace) {
              developer.log(
                'Erreur lors de la mise a jour auto du statut offre: $error',
                name: 'OffreController._parseSnapshotDocs',
                error: error,
                stackTrace: stackTrace,
              );
            }),
          );

          offre.statut = 'fermee';
          offre.lastUpdated = now;
        }

        fetched.add(offre);
      } catch (error, stackTrace) {
        developer.log(
          'Offre ignoree car document invalide: ${doc.id}',
          name: 'OffreController._parseSnapshotDocs',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    fetched.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
    return fetched;
  }

  void _fetchOffres() {
    final currentUid = _authSessionService.currentUser?.uid;
    final hasActiveStream =
        _offresSubscription != null && _activeAuthUid == currentUid;
    if (hasActiveStream) {
      return;
    }

    _activeAuthUid = currentUid;
    if (_offres.value.isEmpty) {
      _isLoading.value = true;
    }
    _offresSubscription?.cancel();

    _offresSubscription =
        _firestore.collection('offres').snapshots().listen((snapshot) {
      _offres.value = _parseSnapshotDocs(snapshot.docs);
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

  Future<void> _stopOffresStream({bool clearData = false}) async {
    await _offresSubscription?.cancel();
    _offresSubscription = null;
    _activeAuthUid = null;

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
      final docRef = _firestore.collection('offres').doc(offre.id);

      await _firestore.runTransaction((txn) async {
        final snap = await txn.get(docRef);
        final data = snap.data();
        if (data == null) return;

        final rawRecruteur = data['recruteur'];
        final recruteurMap = rawRecruteur is Map
            ? Map<String, dynamic>.from(rawRecruteur)
            : null;
        final recruteurId = recruteurMap?['uid']?.toString();

        final viewedByRaw = data['viewedBy'];
        final viewedBy = viewedByRaw is List
            ? viewedByRaw.map((e) => e.toString()).toList()
            : <String>[];

        if (viewer.uid == recruteurId || viewedBy.contains(viewer.uid)) {
          return;
        }

        txn.update(docRef, {
          'vues': FieldValue.increment(1),
          'viewedBy': FieldValue.arrayUnion([viewer.uid]),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });
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
      final payload = offre.toMap();
      payload['statut'] = _normalizeStatus(offre.statut);
      payload['lastUpdated'] = FieldValue.serverTimestamp();

      await _firestore.collection('offres').doc(offre.id).set(payload);

      final fanoutResult = await _notifierJoueurs(offre, utilisateur);
      if (!fanoutResult.success) {
        return ActionResponse(
          success: true,
          message:
              'Offre publiee avec succes, mais les notifications sont temporairement indisponibles.',
          code: 'published_notification_failed',
          toast: ToastLevel.info,
        );
      }

      return const ActionResponse(
        success: true,
        code: 'published',
        message: 'Offre publiee avec succes.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors de la publication de l offre: $error',
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
        message: 'Impossible de publier l offre pour le moment.',
      );
    } catch (e, st) {
      developer.log(
        'Erreur lors de la publication de l offre: $e',
        name: 'OffreController.publierOffre',
        error: e,
        stackTrace: st,
      );
      return ActionResponse.failure(
        code: 'publish_failed',
        message: 'Impossible de publier l offre pour le moment.',
      );
    }
  }

  Future<ActionResponse> _notifierJoueurs(
      Offre offre, AppUser recruteur) async {
    final response = await PushNotificationService.sendOfferFanout(
      offerId: offre.id,
      title: 'Nouvelle offre disponible',
      body: 'Une nouvelle offre a ete publiee par ${recruteur.nom}.',
    );

    if (!response.success) {
      developer.log(
        'Erreur lors de l envoi des notifications offre: ${response.message}',
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
      final payload = offre.toMap();
      payload['statut'] = _normalizeStatus(offre.statut);
      payload['lastUpdated'] = FieldValue.serverTimestamp();

      await _firestore.collection('offres').doc(offre.id).update(payload);
      return const ActionResponse(
        success: true,
        code: 'updated',
        message: 'Offre modifiee avec succes.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors de la modification de l offre: $error',
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
        message: 'Impossible de modifier l offre pour le moment.',
      );
    } catch (e, st) {
      developer.log(
        'Erreur lors de la modification de l offre: $e',
        name: 'OffreController.modifierOffre',
        error: e,
        stackTrace: st,
      );

      return ActionResponse.failure(
        code: 'update_failed',
        message: 'Impossible de modifier l offre pour le moment.',
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

    final normalized = _normalizeStatus(nouveauStatut);
    const allowed = <String>{'brouillon', 'ouverte', 'fermee', 'archivee'};
    if (!allowed.contains(normalized)) {
      return ActionResponse.failure(
        code: 'invalid-argument',
        message: 'Statut invalide.',
        toast: ToastLevel.info,
      );
    }

    try {
      await _firestore.collection('offres').doc(offre.id).update({
        'statut': normalized,
        'lastUpdated': FieldValue.serverTimestamp(),
        if (normalized == 'archivee')
          'archivedAt': FieldValue.serverTimestamp()
        else
          'archivedAt': FieldValue.delete(),
      });

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
      await _firestore.collection('offres').doc(offreId).delete();
      return const ActionResponse(
        success: true,
        code: 'deleted',
        message: 'Offre supprimée avec succès.',
        toast: ToastLevel.success,
      );
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors de la suppression de l offre: $error',
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
        message: 'Impossible de supprimer l offre pour le moment.',
      );
    } catch (e, st) {
      developer.log(
        'Erreur lors de la suppression de l offre: $e',
        name: 'OffreController.supprimerOffre',
        error: e,
        stackTrace: st,
      );

      return ActionResponse.failure(
        code: 'delete_failed',
        message: 'Impossible de supprimer l offre pour le moment.',
      );
    }
  }

  Future<ActionResponse> postulerOffre(AppUser joueur, Offre offre) async {
    if (joueur.role != 'joueur') {
      return ActionResponse.failure(
        code: 'permission-denied',
        message: 'Seuls les joueurs peuvent postuler a une offre.',
        toast: ToastLevel.info,
      );
    }

    final docRef = _firestore.collection('offres').doc(offre.id);

    try {
      await _firestore.runTransaction((txn) async {
        final snap = await txn.get(docRef);
        if (!snap.exists) {
          throw const _OffreFlowException(
            code: 'not-found',
            message: 'Offre introuvable.',
          );
        }

        final data = snap.data() ?? <String, dynamic>{};
        final status =
            _normalizeStatus(data['statut']?.toString() ?? offre.statut);
        if (!_isOpenStatus(status)) {
          throw const _OffreFlowException(
            code: 'offer_closed',
            message: 'Vous ne pouvez pas postuler a cette offre.',
            toast: ToastLevel.info,
          );
        }

        final candidats = _extractCandidateMaps(data['candidats']);
        final dejaPostule = candidats
            .any((candidate) => candidate['uid']?.toString() == joueur.uid);
        if (dejaPostule) {
          throw const _OffreFlowException(
            code: 'already_applied',
            message: 'Vous avez deja postule a cette offre.',
            toast: ToastLevel.info,
          );
        }

        candidats.add(joueur.toEmbeddedMap());

        txn.update(docRef, {
          'candidats': candidats,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });

      return const ActionResponse(
        success: true,
        code: 'applied',
        message: 'Vous avez postule a l offre.',
        toast: ToastLevel.success,
      );
    } on _OffreFlowException catch (e) {
      return ActionResponse.failure(
        code: e.code,
        message: e.message,
        toast: e.toast,
      );
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

    final docRef = _firestore.collection('offres').doc(offre.id);

    try {
      await _firestore.runTransaction((txn) async {
        final snap = await txn.get(docRef);
        if (!snap.exists) {
          throw const _OffreFlowException(
            code: 'not-found',
            message: 'Offre introuvable.',
          );
        }

        final data = snap.data() ?? <String, dynamic>{};
        final candidats = _extractCandidateMaps(data['candidats']);
        final estCandidat = candidats
            .any((candidate) => candidate['uid']?.toString() == joueur.uid);

        if (!estCandidat) {
          throw const _OffreFlowException(
            code: 'not_applied',
            message: 'Vous n etes pas inscrit a cette offre.',
            toast: ToastLevel.info,
          );
        }

        final candidatsRestants = candidats
            .where((candidate) => candidate['uid']?.toString() != joueur.uid)
            .toList();

        txn.update(docRef, {
          'candidats': candidatsRestants,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      });

      return const ActionResponse(
        success: true,
        code: 'withdrawn',
        message: 'Vous vous etes desinscrit de l offre.',
        toast: ToastLevel.success,
      );
    } on _OffreFlowException catch (e) {
      return ActionResponse.failure(
        code: e.code,
        message: e.message,
        toast: e.toast,
      );
    } on FirebaseException catch (error, st) {
      developer.log(
        'Erreur lors de la desinscription offre: $error',
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
        'Erreur lors de la desinscription offre: $e',
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
}
