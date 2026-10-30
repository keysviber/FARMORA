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
  test('Unknown account roles cannot silently become buyers', () {
    expect(() => AccountRole.parse('admin'), throwsStateError);
  });
}
