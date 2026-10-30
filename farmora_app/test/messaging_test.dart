import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:farmora_app/messaging/messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Read receipts require the recipient to read at or after the message',
    () {
      final message = {'senderId': 'supplier', 'createdAt': Timestamp(100, 0)};
      expect(messageWasRead(message, {}), false);
      expect(
        messageWasRead(message, {
          'participants': ['supplier', 'buyer'],
          'readAt': {'supplier': Timestamp(110, 0), 'buyer': Timestamp(99, 0)},
        }),
        false,
      );
      expect(
        messageWasRead(message, {
          'participants': ['supplier', 'buyer'],
          'readAt': {'buyer': Timestamp(100, 0)},
        }),
        true,
      );
      expect(
        messageWasRead(
          {'senderId': 'supplier'},
          {
            'participants': ['supplier', 'buyer'],
          },
        ),
        false,
      );
    },
  );
  testWidgets('Message receipt renders on narrow screens without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            data: {
              'text': 'Your maize is ready for collection.',
              'createdAt': Timestamp(100, 0),
            },
            mine: true,
            read: true,
          ),
        ),
      ),
    );
    expect(find.text('Read'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
