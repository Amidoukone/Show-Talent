import 'dart:async';
import 'dart:io';

import 'package:adfoot/controller/chat_controller.dart';
import 'package:adfoot/models/user.dart';
import 'package:adfoot/services/auth/auth_session_service.dart';
import 'package:adfoot/services/chat/chat_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class TestAuthSessionService extends AuthSessionService {
  TestAuthSessionService(User? user)
      : _currentUser = user,
        _idTokenController = StreamController<User?>.broadcast() {
    _idTokenController.add(user);
  }

  final StreamController<User?> _idTokenController;
  User? _currentUser;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<User?> idTokenChanges() => _idTokenController.stream;

  void emit(User? user) {
    _currentUser = user;
    _idTokenController.add(user);
  }

  Future<void> dispose() async {
    await _idTokenController.close();
  }
}

class ChatTestHarness {
  ChatTestHarness._({
    required this.firestore,
    required this.auth,
    required this.chatRepository,
    required this.authSessionService,
    required this.chatController,
    required this.currentUser,
    required this.otherUser,
    required this.projectRulesEnforced,
    required this.sentNotifications,
  });

  final FakeFirebaseFirestore firestore;
  final MockFirebaseAuth auth;
  final ChatRepository chatRepository;
  final TestAuthSessionService authSessionService;
  final ChatController chatController;
  final AppUser currentUser;
  final AppUser otherUser;
  final bool projectRulesEnforced;
  final List<Map<String, String>> sentNotifications;

  static Future<void> ensureFirebaseInitialized() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();

    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'test-api-key',
          appId: '1:1234567890:android:test',
          messagingSenderId: '1234567890',
          projectId: 'test-project',
          storageBucket: 'test-project.appspot.com',
        ),
      );
    } on FirebaseException catch (error) {
      if (error.code != 'duplicate-app') {
        rethrow;
      }
    }
  }

  static Future<ChatTestHarness> create({
    ChatNotificationSender? notificationSender,
    bool enforceProjectRules = false,
  }) async {
    await ensureFirebaseInitialized();
    Get.testMode = true;

    final currentUser = _buildUser(
      uid: 'user_a',
      name: 'Alice Scout',
      email: 'alice@test.dev',
      role: 'recruteur',
    );
    final otherUser = _buildUser(
      uid: 'user_b',
      name: 'Bob Joueur',
      email: 'bob@test.dev',
      role: 'joueur',
    );

    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: currentUser.uid,
        email: currentUser.email,
        displayName: currentUser.nom,
        isEmailVerified: true,
      ),
    );
    final firestore = FakeFirebaseFirestore(
      authObject: auth.authForFakeFirestore,
    );
    await Future<void>.delayed(Duration.zero);
    await firestore.collection('users').doc(currentUser.uid).set(
          currentUser.toMap(),
        );
    await firestore.collection('users').doc(otherUser.uid).set(
          otherUser.toMap(),
        );
    if (enforceProjectRules) {
      firestore.securityRules = FakeFirebaseFirestore(
        authObject: auth.authForFakeFirestore,
        securityRules: _buildSupportedChatRules(),
      ).securityRules;
    }

    final sentNotifications = <Map<String, String>>[];
    final authSessionService = TestAuthSessionService(auth.currentUser);
    final chatRepository = ChatRepository(firestore: firestore);
    final chatController = ChatController(
      authSessionService: authSessionService,
      chatRepository: chatRepository,
      notificationSender: notificationSender ??
          ({
            required String title,
            required String body,
            required String recipientUid,
            required String contextType,
            required String contextData,
          }) async {
            sentNotifications.add(<String, String>{
              'title': title,
              'body': body,
              'recipientUid': recipientUid,
              'contextType': contextType,
              'contextData': contextData,
            });
          },
      protectedAccessDeniedHandler: () async {},
      currentUidResolver: () => auth.currentUser?.uid,
    );

    chatController.onInit();
    await Future<void>.delayed(Duration.zero);

    return ChatTestHarness._(
      firestore: firestore,
      auth: auth,
      chatRepository: chatRepository,
      authSessionService: authSessionService,
      chatController: chatController,
      currentUser: currentUser,
      otherUser: otherUser,
      projectRulesEnforced: enforceProjectRules,
      sentNotifications: sentNotifications,
    );
  }

  Future<void> dispose() async {
    chatController.onClose();
    await authSessionService.dispose();
    Get.reset();
  }

  static AppUser _buildUser({
    required String uid,
    required String name,
    required String email,
    required String role,
  }) {
    final now = DateTime(2026, 5, 12, 12);
    return AppUser(
      uid: uid,
      nom: name,
      email: email,
      role: role,
      photoProfil: '',
      estActif: true,
      emailVerified: true,
      followers: 0,
      followings: 0,
      dateInscription: now,
      dernierLogin: now,
      followersList: <String>[],
      followingsList: <String>[],
      profilePublic: true,
      allowMessages: true,
    );
  }

  static String _buildSupportedChatRules() {
    final projectRules = File('firestore.rules').readAsStringSync();
    if (!projectRules.contains('activeConversationId') ||
        !projectRules.contains('contact_intakes') ||
        !projectRules.contains('match /conversations/{conversationId}')) {
      throw StateError(
        'Les regles Firestore du projet ont change; mettez a jour le harness chat.',
      );
    }

    return '''
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    match /conversations/{conversationId} {
      allow read, write: if request.auth != null;
    }

    match /conversations/{conversationId}/messages/{messageId} {
      allow read, write: if request.auth != null;
    }

    match /contact_intakes/{intakeId} {
      allow read, write: if request.auth != null;
    }

    match /{document=**} {
      allow read, write: if false;
    }
  }
}''';
  }
}
