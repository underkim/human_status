import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/reward_transaction.dart';

void main() {
  test('rollback attempts every undo and reports all failures', () async {
    final scope = RollbackScope();
    final calls = <int>[];
    scope.addUndo(() async {
      calls.add(1);
      throw StateError('first');
    });
    scope.addUndo(() async {
      calls.add(2);
      throw StateError('second');
    });

    await expectLater(
      scope.rollback(),
      throwsA(
        isA<RollbackFailureException>().having(
          (error) => error.errors,
          'errors',
          hasLength(2),
        ),
      ),
    );
    expect(calls, [2, 1]);
  });

  test('rollbackAndThrow preserves the original and rollback errors', () async {
    final scope = RollbackScope()
      ..addUndo(() async => throw StateError('rollback'));
    final original = ArgumentError('original');

    await expectLater(
      scope.rollbackAndThrow(original, StackTrace.current),
      throwsA(
        isA<TransactionRollbackException>()
            .having((error) => error.error, 'error', same(original))
            .having(
              (error) => error.rollbackErrors,
              'rollbackErrors',
              hasLength(1),
            ),
      ),
    );
  });
}
