import 'package:flutter_test/flutter_test.dart';
import 'package:farmora_app/core/app.dart';
import 'package:farmora_app/core/models.dart';
import 'package:farmora_app/shared/widgets.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('Unconfigured app explains setup without fake listings', (
    tester,
  ) async {
    await tester.pumpWidget(const FarmoraApp());
    expect(find.text('Welcome to Farmora'), findsOneWidget);
    expect(find.textContaining('Connect Firebase'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
  testWidgets(
    'Async action prevents duplicate submissions and recovers from failure',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncAction(
              label: 'Publish',
              action: () async {
                calls++;
                await Future<void>.delayed(const Duration(milliseconds: 100));
                throw Exception('Connection unavailable');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Publish'));
      await tester.pump();
      await tester.tap(find.text('Please wait…'));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.text('Publish'), findsOneWidget);
      expect(find.textContaining('Connection unavailable'), findsOneWidget);
    },
  );
  test('Quantity validation rejects invalid or unsafe values', () {
    for (final value in ['', '-1', '0', 'NaN', 'Infinity', 'hello']) {
      expect(() => positiveNumber(value), throwsFormatException);
    }
    expect(positiveNumber('2.5'), 2.5);
  });
  test('Road cost formula includes base fee and additional charges', () {
    expect(transportEstimate(roadKm: 120, baseFee: 0, rate: 0.8), 96);
    expect(
      transportEstimate(roadKm: 120, baseFee: 10, rate: 0.8, additional: 5),
      111,
    );
    expect(
      () => transportEstimate(roadKm: -1, baseFee: 0, rate: 1),
      throwsArgumentError,
    );
  });
  test('Every way of writing a phone number reaches the same account', () {
    for (final value in [
      '0771234567',
      '077 123 4567',
      '771234567',
      '+263 77 123 4567',
      '+263 (0)77-123-4567',
      '263771234567',
      '00263771234567',
    ]) {
      expect(normalizePhone(value), '263771234567', reason: value);
    }
    expect(normalizePhone('+27 82 123 4567'), '27821234567');
    for (final value in ['', '12345', 'hello', '077abc4567', '+1234567890123456']) {
      expect(normalizePhone(value), isNull, reason: value);
    }
    expect(phoneLoginEmail('263771234567'), '263771234567@phone.farmora.invalid');
  });
  test('Unknown account roles cannot silently become buyers', () {
    expect(() => AccountRole.parse('admin'), throwsStateError);
  });
}
