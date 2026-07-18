import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/backup_service.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

void main() {
  late StorageService storage;

  setUp(() async {
    storage = await createTestStorage();
  });

  Map<String, Object?> minimalBackup() => <String, Object?>{
    'schemaVersion': BackupService.currentSchemaVersion,
    'stats': <Object?>[],
    'quests': <Object?>[],
  };

  test('rejects a backup over the UTF-8 byte limit before parsing', () {
    final oversized = List.filled(BackupService.maxBackupBytes + 1, 'a').join();
    expect(
      () => BackupService(storage: storage).inspect(oversized),
      throwsA(isA<FormatException>()),
    );
  });

  test('measures multibyte input by UTF-8 bytes rather than code units', () {
    final oversized = '한' * ((BackupService.maxBackupBytes ~/ 3) + 1);
    expect(
      utf8.encode(oversized).length,
      greaterThan(BackupService.maxBackupBytes),
    );
    expect(
      () => BackupService(storage: storage).inspect(oversized),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects excessive domain records before model construction', () {
    final backup = minimalBackup()
      ..['transactions'] = List<Object?>.filled(
        BackupService.maxTransactions + 1,
        null,
      );
    expect(
      () => BackupService(storage: storage).inspect(jsonEncode(backup)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects oversized strings in nested domain fields', () {
    final backup = minimalBackup()
      ..['goals'] = <Object?>[
        <String, Object?>{'title': 'x' * (BackupService.maxStringLength + 1)},
      ];
    expect(
      () => BackupService(storage: storage).inspect(jsonEncode(backup)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects JSON nested beyond the supported depth', () {
    Object? nested = 'leaf';
    for (var i = 0; i <= BackupService.maxNestingDepth; i++) {
      nested = <Object?>[nested];
    }
    final backup = minimalBackup()..['extra'] = nested;

    expect(
      () => BackupService(storage: storage).inspect(jsonEncode(backup)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('nested too deeply'),
        ),
      ),
    );
  });

  test('accepts exactly the supported nesting depth', () {
    Object? nested = 'leaf';
    for (var i = 0; i < BackupService.maxNestingDepth; i++) {
      nested = <Object?>[nested];
    }
    final backup = minimalBackup()..['extra'] = nested;

    expect(
      () => BackupService(storage: storage).inspect(jsonEncode(backup)),
      returnsNormally,
    );
  });

  test('rejects excessive nesting before JSON decoding', () {
    final nested = '${'[' * 10000}null${']' * 10000}';
    final json = '{"schemaVersion":1,"stats":[],"quests":[],"extra":$nested}';

    expect(
      () => BackupService(storage: storage).inspect(json),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('nested too deeply'),
        ),
      ),
    );
  });
}
