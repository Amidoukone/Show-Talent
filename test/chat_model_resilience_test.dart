import 'package:adfoot/models/message_converstion.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chat model resilience', () {
    test('message parser tolerates legacy scalar values', () {
      final message = Message.fromMap(<String, dynamic>{
        'id': 42,
        'expediteurId': 1001,
        'destinataireId': 1002,
        'contenu': 'Bonjour',
        'dateEnvoi': '2026-06-02T12:30:00.000Z',
        'estLu': true,
      });

      expect(message.id, '42');
      expect(message.expediteurId, '1001');
      expect(message.destinataireId, '1002');
      expect(message.contenu, 'Bonjour');
      expect(message.dateEnvoi, DateTime.parse('2026-06-02T12:30:00.000Z'));
      expect(message.estLu, isTrue);
    });

    test('message parser keeps a safe fallback date when timestamp is missing',
        () {
      final message = Message.fromMap(<String, dynamic>{
        'expediteurId': 'sender',
        'destinataireId': 'recipient',
        'contenu': 'Message historique',
      });

      expect(message.dateEnvoi, DateTime.fromMillisecondsSinceEpoch(0));
      expect(message.estLu, isFalse);
    });

    test('conversation parser recovers legacy participant fields', () {
      final conversation = Conversation.fromMap(<String, dynamic>{
        'id': 'legacy-conv',
        'utilisateur1Id': ' user_a ',
        'utilisateur2Id': ' user_b ',
        'lastMessageDate': Timestamp.fromDate(
          DateTime.utc(2026, 6, 2, 12),
        ),
      });

      expect(conversation.utilisateur1Id, 'user_a');
      expect(conversation.utilisateur2Id, 'user_b');
      expect(conversation.utilisateurIds, <String>['user_a', 'user_b']);
      expect(conversation.lastMessage, isNull);
      expect(conversation.lastMessageDate, DateTime(2026, 6, 2, 12));
    });
  });
}
