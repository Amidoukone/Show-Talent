import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:adfoot/models/contact_intake.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

Matcher _deniedByFakeRules() {
  return throwsA(
    isA<Exception>().having(
      (error) => error.toString(),
      'message',
      contains('is not allowed'),
    ),
  );
}

void main() {
  test(
      'supported chat rules allow own chat presence updates and deny writes on another user doc',
      () async {
    final harness = await ChatTestHarness.create(
      enforceProjectRules: true,
    );
    addTearDown(harness.dispose);

    await harness.chatController.setActiveConversation(
      uid: harness.currentUser.uid,
      conversationId: 'conversation_secure_presence',
    );

    final ownUserDoc =
        await harness.firestore
            .collection('users')
            .doc(harness.currentUser.uid)
            .get();

    expect(
      ownUserDoc.data()?['activeConversationId'],
      'conversation_secure_presence',
    );

    await expectLater(
      harness.firestore.collection('users').doc(harness.otherUser.uid).update(
        <String, dynamic>{
          'activeConversationId': 'conversation_hijack',
          'activeAt': FieldValue.serverTimestamp(),
        },
      ),
      _deniedByFakeRules(),
    );
  });

  test(
      'supported chat rules keep guided contact intake readable and block access after sign-out',
      () async {
    final harness = await ChatTestHarness.create(
      enforceProjectRules: true,
    );
    addTearDown(harness.dispose);

    final result = await harness.chatController.startGuidedConversation(
      currentUser: harness.currentUser,
      otherUser: harness.otherUser,
      context: ContactContext.discovery(title: 'Annuaire'),
      contactReason: ContactReasonCode.information,
      introMessage: 'Je souhaite prendre contact.',
    );

    final intakeDoc =
        await harness.firestore
            .collection('contact_intakes')
            .doc(result.contactIntake!.id)
            .get();

    expect(intakeDoc.exists, isTrue);
    expect(intakeDoc.data()?['requesterUid'], harness.currentUser.uid);
    expect(intakeDoc.data()?['targetUid'], harness.otherUser.uid);

    await harness.auth.signOut();
    harness.authSessionService.emit(null);

    await expectLater(
      harness.firestore
          .collection('contact_intakes')
          .doc(result.contactIntake!.id)
          .get(),
      _deniedByFakeRules(),
    );

    await expectLater(
      harness.firestore.collection('users').doc(harness.currentUser.uid).update(
        <String, dynamic>{'activeConversationId': 'after_signout'},
      ),
      _deniedByFakeRules(),
    );
  });
}
