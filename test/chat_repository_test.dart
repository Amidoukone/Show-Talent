import 'dart:io';

import 'package:adfoot/l10n/video_ui_translations.dart';
import 'package:adfoot/models/contact_intake.dart';
import 'package:adfoot/services/chat/chat_repository.dart';
import 'package:adfoot/services/users/block_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  // buildGuidedFirstMessage resolves reason/context labels through GetX's
  // `.tr`, which needs Get.locale/Get.translations populated -- set
  // directly (no widget to pump in a pure test) so the assertions below
  // check real French text, not `.tr` silently falling back to the bare key.
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(VideoUiTranslations().keys);
    Get.locale = const Locale('fr');
    Get.fallbackLocale = const Locale('fr');
  });
  tearDown(() {
    Get.clearTranslations();
    Get.reset();
  });

  test('conversation id is deterministic and order-independent', () {
    final first = ChatRepository.buildConversationId('user_b', 'user_a');
    final second = ChatRepository.buildConversationId('user_a', 'user_b');

    expect(first, equals('user_a__user_b'));
    expect(second, equals('user_a__user_b'));
    expect(first, equals(second));
  });

  test('guided first contact message keeps context and reason explicit', () {
    final message = ChatRepository.buildGuidedFirstMessage(
      context: ContactContext.event(
        eventId: 'event-1',
        title: 'Tournoi Détection',
      ),
      reasonCode: ContactReasonCode.trial,
      introMessage: 'Nous souhaitons vous observer samedi.',
    );

    expect(message, contains('Premier contact Adfoot.'));
    expect(message, contains('Essai / Évaluation'));
    expect(message, contains('Tournoi Détection'));
    expect(message, contains('observer samedi'));
  });

  // Ce garde-fou interdisait tout `get()` direct sur la conversation, parce
  // qu'un document inexistant etait *refuse* par les regles au lieu de
  // repondre « introuvable » : `resource` est null et la regle lisait
  // `resource.data`. La cause est corrigee a la source (regle `get` de
  // `conversations`, meme correction que pour `blocks`), donc la lecture
  // directe redevient legitime -- elle evite de telecharger toutes les
  // conversations du lecteur a chaque appui sur « Message ».
  //
  // Ce que ce test exige desormais : la lecture directe doit rester une
  // optimisation repliable. Elle precede le balayage, et son echec ne doit
  // jamais faire echouer la recherche -- un deploiement de regles peut
  // toujours arriver apres un build publie.
  test('chat repository falls back when the direct conversation read fails', () {
    final repository = File(
      'lib/services/chat/chat_repository.dart',
    ).readAsStringSync();
    final lookupStart = repository.indexOf(
      'Future<String?> findExistingConversationId',
    );
    final lookupEnd = repository.indexOf(
      'Future<GuidedConversationStartResult>',
    );

    expect(lookupStart, greaterThanOrEqualTo(0));
    expect(lookupEnd, greaterThan(lookupStart));

    final lookupSnippet = repository.substring(lookupStart, lookupEnd);

    expect(repository, contains(".where('readableBy', arrayContains:"));
    expect(
      repository,
      contains(
        'final existingConversationId = await findExistingConversationId(',
      ),
    );
    expect(
      repository,
      contains("await conversationRef.set({...newConversation.toMap(), 'readableBy': ids});"),
    );
    expect(lookupSnippet, contains('_normalizeParticipantIds(doc.data())'));
    expect(lookupSnippet, contains('legacyConversationId'));
    expect(repository, isNot(contains('.limit(100)')));
    expect(lookupSnippet, contains('.doc(conversationId).get()'));
    // La lecture directe est tentee dans un try, et le balayage reste
    // atteignable apres son echec : sans cela, une regle non encore deployee
    // rendrait la recherche impossible au lieu de la ralentir.
    final directReadIndex = lookupSnippet.indexOf('.doc(conversationId).get()');
    final tryIndex = lookupSnippet.lastIndexOf('try {', directReadIndex);
    final catchIndex = lookupSnippet.indexOf('} catch (', directReadIndex);
    final scanIndex = lookupSnippet.indexOf(
      ".where('readableBy', arrayContains:",
    );
    expect(tryIndex, greaterThanOrEqualTo(0));
    expect(catchIndex, greaterThan(directReadIndex));
    expect(scanIndex, greaterThan(catchIndex));
    expect(
      lookupSnippet,
      isNot(contains('final snap = await txn.get(conversationRef);')),
    );
  });

  test(
    'chat repository keeps delete-message summary and unread state coherent',
    () {
      final repository = File(
        'lib/services/chat/chat_repository.dart',
      ).readAsStringSync();

      expect(repository, contains('await messageRef.delete();'));
      expect(
        repository,
        contains("patch['lastMessage'] = FieldValue.delete();"),
      );
      expect(
        repository,
        contains("patch['lastMessageDate'] = null;"),
      );
      expect(
        repository,
        contains(
          "patch['unreadCountByUser.\${deletedMessage.destinataireId}']",
        ),
      );
    },
  );

  test('chat repository chunks large message mutations below batch limits', () {
    final repository = File(
      'lib/services/chat/chat_repository.dart',
    ).readAsStringSync();

    expect(repository, contains('_messageWriteBatchLimit = 450'));
    expect(repository, contains('.limit(_messageWriteBatchLimit)'));
    expect(repository, contains('while (true)'));
    expect(repository, contains('await batch.commit();'));
    expect(repository, contains('await conversationRef.delete();'));
  });

  test('chat repository stores admin-readable user snapshots', () {
    final repository = File(
      'lib/services/chat/chat_repository.dart',
    ).readAsStringSync();

    expect(repository, contains("'displayName': user.nom"));
    expect(repository, contains("'email': user.email.trim()"));
    expect(repository, contains("'organisation': ?organization"));
    expect(repository, contains('_resolveUserOrganization(AppUser user)'));
  });

  group('isBlockedPair', () {
    test('true once either side has blocked the other', () async {
      final firestore = FakeFirebaseFirestore();
      final chatRepository = ChatRepository(
        firestore: firestore,
        blockRepository: BlockRepository(firestore: firestore),
      );

      expect(
        await chatRepository.isBlockedPair(uidA: 'player', uidB: 'recruiter'),
        isFalse,
      );

      await BlockRepository(
        firestore: firestore,
      ).blockUser(blockerUid: 'recruiter', blockedUid: 'player');

      // Symmetric: it doesn't matter which side is asked first.
      expect(
        await chatRepository.isBlockedPair(uidA: 'player', uidB: 'recruiter'),
        isTrue,
      );
      expect(
        await chatRepository.isBlockedPair(uidA: 'recruiter', uidB: 'player'),
        isTrue,
      );
    });

    test(
      'canSendMessage stays about allowMessages alone, not blocking',
      () async {
        // Deliberate separation of concerns: ChatController checks
        // isBlockedPair itself (to throw a distinct "blocked" message)
        // before ever calling canSendMessage, which stays a pure
        // allowMessages check.
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('public_profiles').doc('player').set({
          'allowMessages': true,
        });
        await firestore.collection('public_profiles').doc('recruiter').set({
          'allowMessages': true,
        });
        await BlockRepository(
          firestore: firestore,
        ).blockUser(blockerUid: 'recruiter', blockedUid: 'player');

        final chatRepository = ChatRepository(firestore: firestore);

        expect(
          await chatRepository.canSendMessage(
            senderId: 'player',
            recipientId: 'recruiter',
          ),
          isTrue,
        );
      },
    );
  });
}
