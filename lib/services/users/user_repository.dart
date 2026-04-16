import 'package:adfoot/models/user.dart';
import 'package:adfoot/utils/account_role_policy.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum UserAccessIssue {
  missingProfile,
  adminPortalOnly,
  disabledAccount,
}

class UserAccessDecision {
  const UserAccessDecision({
    required this.exists,
    required this.issue,
    this.user,
    this.message,
    this.title,
  });

  final bool exists;
  final UserAccessIssue? issue;
  final AppUser? user;
  final String? message;
  final String? title;

  bool get isAllowed => exists && issue == null;
}

class UserSettingsSnapshot {
  const UserSettingsSnapshot({
    required this.role,
    required this.profilePublic,
    required this.allowMessages,
  });

  final String role;
  final bool profilePublic;
  final bool allowMessages;
}

class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const String _missingProfileMessage =
      'Ce compte n est plus disponible. Si vous pensez qu il s agit d une erreur, contactez le support Adfoot.';
  static const String _adminPortalOnlyMessage =
      'Ce compte est reserve au portail d administration Adfoot.';
  static const String _disabledFallbackMessage =
      'L acces a ce compte a ete desactive. Contactez le support Adfoot.';
  static const String _missingProfileTitle = 'Compte indisponible';
  static const String _adminPortalOnlyTitle = 'Acces refuse';
  static const String _disabledTitle = 'Compte desactive';

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  static Map<String, dynamic> _legacyFieldCleanupPatch() {
    return <String, dynamic>{
      'authDisabled': false,
      'authDisabledAt': FieldValue.delete(),
      'authDisabledBy': FieldValue.delete(),
      'authDisabledReason': FieldValue.delete(),
      'estBloque': FieldValue.delete(),
      'blockedAt': FieldValue.delete(),
      'blockedBy': FieldValue.delete(),
      'blockedReason': FieldValue.delete(),
      'blockMode': FieldValue.delete(),
      'blockedUntil': FieldValue.delete(),
    };
  }

  static UserAccessDecision evaluateUserData(Map<String, dynamic>? data) {
    if (data == null) {
      return const UserAccessDecision(
        exists: false,
        issue: UserAccessIssue.missingProfile,
        message: _missingProfileMessage,
        title: _missingProfileTitle,
      );
    }

    final user = AppUser.fromMap(data);
    if (isAdminPortalOnlyRole(data['role'])) {
      return UserAccessDecision(
        exists: true,
        issue: UserAccessIssue.adminPortalOnly,
        user: user,
        message: _adminPortalOnlyMessage,
        title: _adminPortalOnlyTitle,
      );
    }

    if (user.authDisabled) {
      return UserAccessDecision(
        exists: true,
        issue: UserAccessIssue.disabledAccount,
        user: user,
        message: _buildDisabledAccountMessage(user),
        title: _disabledTitle,
      );
    }

    return UserAccessDecision(
      exists: true,
      issue: null,
      user: user,
    );
  }

  static AppUser buildPublicSignupUser({
    required String uid,
    required String nom,
    required String email,
    required String role,
    String? phone,
    DateTime? now,
  }) {
    final normalizedRole = normalizeUserRole(role);
    if (!isPublicSelfSignupRole(normalizedRole)) {
      throw ArgumentError.value(
        role,
        'role',
        'Le role doit etre joueur ou fan pour une inscription publique.',
      );
    }

    final createdAt = now ?? DateTime.now();

    return AppUser(
      uid: uid,
      nom: nom,
      email: email,
      role: normalizedRole,
      photoProfil: '',
      estActif: false,
      emailVerified: false,
      followers: 0,
      followings: 0,
      dateInscription: createdAt,
      dernierLogin: createdAt,
      phone: phone != null && phone.trim().isNotEmpty ? phone.trim() : null,
      emailVerifiedAt: null,
      bio: null,
      position: null,
      clubActuel: null,
      nombreDeMatchs: null,
      buts: null,
      assistances: null,
      videosPubliees: const [],
      performances: const {},
      nomClub: null,
      ligue: null,
      offrePubliees: const [],
      eventPublies: const [],
      entreprise: null,
      nombreDeRecrutements: null,
      team: null,
      joueursSuivis: const [],
      clubsSuivis: const [],
      videosLikees: const [],
      cvUrl: null,
      followersList: const [],
      followingsList: const [],
      profilePublic: true,
      allowMessages: true,
    );
  }

  Stream<List<AppUser>> watchAllUsers() {
    return _usersCollection.snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => AppUser.fromMap(doc.data()))
              .toList(growable: false),
        );
  }

  Stream<UserAccessDecision> watchUserAccess(String uid) {
    return _usersCollection.doc(uid).snapshots().map((doc) {
      if (!doc.exists) {
        return const UserAccessDecision(
          exists: false,
          issue: UserAccessIssue.missingProfile,
          message: _missingProfileMessage,
          title: _missingProfileTitle,
        );
      }

      return evaluateUserData(doc.data());
    });
  }

  Future<AppUser?> fetchUserById(String uid) async {
    final doc = await _usersCollection.doc(uid).get();
    if (!doc.exists) {
      return null;
    }

    return AppUser.fromMap(doc.data()!);
  }

  Future<UserAccessDecision> fetchUserAccess(
    String uid, {
    bool waitForDocument = false,
    int attempts = 20,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    final doc = waitForDocument
        ? await _waitForUserDoc(uid, attempts: attempts, delay: delay)
        : await _usersCollection.doc(uid).get();

    if (doc == null || !doc.exists) {
      return const UserAccessDecision(
        exists: false,
        issue: UserAccessIssue.missingProfile,
        message: _missingProfileMessage,
        title: _missingProfileTitle,
      );
    }

    return evaluateUserData(doc.data());
  }

  Future<AppUser> upsertPublicSignupUser({
    required String uid,
    required String nom,
    required String email,
    required String role,
    String? phone,
  }) async {
    final normalizedRole = normalizeUserRole(role);
    if (!isPublicSelfSignupRole(normalizedRole)) {
      throw ArgumentError.value(
        role,
        'role',
        'Le role doit etre joueur ou fan pour une inscription publique.',
      );
    }

    final appUser = buildPublicSignupUser(
      uid: uid,
      nom: nom,
      email: email,
      role: normalizedRole,
      phone: phone,
    );

    await _usersCollection.doc(uid).set(
      <String, dynamic>{
        ..._legacyFieldCleanupPatch(),
        ...appUser.toMap(),
      },
      SetOptions(merge: true),
    );

    return appUser;
  }

  Future<AppUser?> markEmailVerifiedAndActivate(
    String uid, {
    bool updateLastLogin = false,
  }) async {
    final docRef = _usersCollection.doc(uid);
    final existing = await docRef.get();
    if (!existing.exists) {
      return null;
    }

    final decision = evaluateUserData(existing.data());
    final user = decision.user;
    if (user == null || decision.issue != null) {
      return user;
    }

    final updates = <String, dynamic>{};
    updates.addAll(_legacyFieldCleanupPatch());
    if (!user.emailVerified) {
      updates['emailVerified'] = true;
    }
    if (!user.estActif) {
      updates['estActif'] = true;
    }
    if (user.emailVerifiedAt == null) {
      updates['emailVerifiedAt'] = FieldValue.serverTimestamp();
    }
    if (updateLastLogin) {
      updates['dernierLogin'] = DateTime.now();
    }

    if (updates.isNotEmpty) {
      await docRef.set(updates, SetOptions(merge: true));
    }

    final refreshed = await docRef.get();
    if (!refreshed.exists) {
      return null;
    }

    return AppUser.fromMap(refreshed.data()!);
  }

  Future<UserSettingsSnapshot?> fetchUserSettings(String uid) async {
    final user = await fetchUserById(uid);
    if (user == null) {
      return null;
    }

    return UserSettingsSnapshot(
      role: user.role,
      profilePublic: user.profilePublic,
      allowMessages: user.allowMessages,
    );
  }

  Future<void> updatePrivacySettings(
    String uid, {
    bool? profilePublic,
    bool? allowMessages,
  }) async {
    final patch = <String, dynamic>{};
    if (profilePublic != null) {
      patch['profilePublic'] = profilePublic;
    }
    if (allowMessages != null) {
      patch['allowMessages'] = allowMessages;
    }
    if (patch.isEmpty) {
      return;
    }

    await _usersCollection.doc(uid).update(patch);
  }

  Future<void> saveFcmToken(String uid, String token) async {
    await _usersCollection.doc(uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _waitForUserDoc(
    String uid, {
    int attempts = 20,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    DocumentSnapshot<Map<String, dynamic>>? doc;
    for (int i = 0; i < attempts; i++) {
      doc = await _usersCollection.doc(uid).get();
      if (doc.exists) {
        return doc;
      }
      await Future.delayed(delay);
    }

    return doc;
  }

  static String _buildDisabledAccountMessage(AppUser user) {
    final authDisabledReason = _normalizeReason(user.authDisabledReason);
    if (authDisabledReason != null) {
      return 'L acces a ce compte a ete desactive. Motif : $authDisabledReason';
    }

    return _disabledFallbackMessage;
  }

  static String? _normalizeReason(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }
}
