import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// Hive's binary reader/writer implementations aren't exported from the
// public `hive.dart` barrel — this is the only way to drive
// UserProfileAdapter.read/write through the real Hive binary format instead
// of constructing a UserProfile object directly and asserting on its
// constructor defaults.
import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/binary/binary_writer_impl.dart';
import 'package:human_status/models/user_profile.dart';

void main() {
  group('UserProfileAdapter — 실제 Hive 바이너리 왕복', () {
    test(
      '필드 6/7이 없는 legacy payload는 onboardingCompleted=true, preferredStatId=null로 읽힌다',
      () {
        // 지금의 UserProfileAdapter.write가 아니라, 온보딩 필드가 추가되기
        // 전 버전의 실제 동작(6개 필드만 씀)을 그대로 재현한다.
        final writer = BinaryWriterImpl(Hive);
        writer
          ..writeByte(6)
          ..writeByte(0)
          ..write(null) // lastQuestRefresh
          ..writeByte(1)
          ..write('sk-legacy') // claudeApiKey
          ..writeByte(2)
          ..write(540) // reminderMinutesSinceMidnight
          ..writeByte(3)
          ..write(null) // lastAdviceRefresh
          ..writeByte(4)
          ..write(<Map<String, dynamic>>[]) // cachedAdvice
          ..writeByte(5)
          ..write(true); // weeklyReportReminderEnabled
        final bytes = writer.toBytes();

        final reader = BinaryReaderImpl(bytes, Hive);
        final profile = UserProfileAdapter().read(reader);

        expect(profile.onboardingCompleted, isTrue);
        expect(profile.preferredStatId, isNull);
        // 다른 필드는 정상적으로 읽혀야 한다 — 필드 인덱스가 밀리지 않았는지 확인.
        expect(profile.claudeApiKey, 'sk-legacy');
        expect(profile.reminderMinutesSinceMidnight, 540);
        expect(profile.weeklyReportReminderEnabled, isTrue);
      },
    );

    test('필드 6/7이 있는 현재 payload를 실제로 쓰고 읽으면 그대로 왕복한다', () {
      final adapter = UserProfileAdapter();
      final original = UserProfile(
        claudeApiKey: 'sk-current',
        onboardingCompleted: false,
        preferredStatId: 'mental',
      );

      final writer = BinaryWriterImpl(Hive);
      adapter.write(writer, original);
      final bytes = writer.toBytes();

      final reader = BinaryReaderImpl(bytes, Hive);
      final roundTripped = adapter.read(reader);

      expect(roundTripped.onboardingCompleted, isFalse);
      expect(roundTripped.preferredStatId, 'mental');
      expect(roundTripped.claudeApiKey, 'sk-current');
    });

    test('필드 6은 있지만 필드 7(preferredStatId)이 없는 중간 버전 payload도 안전하게 읽힌다', () {
      final writer = BinaryWriterImpl(Hive);
      writer
        ..writeByte(7)
        ..writeByte(0)
        ..write(null)
        ..writeByte(1)
        ..write(null)
        ..writeByte(2)
        ..write(null)
        ..writeByte(3)
        ..write(null)
        ..writeByte(4)
        ..write(<Map<String, dynamic>>[])
        ..writeByte(5)
        ..write(false)
        ..writeByte(6)
        ..write(
          false,
        ); // onboardingCompleted 명시적으로 false — 아직 미완료 온보딩 중 저장된 레코드
      final bytes = writer.toBytes();

      final reader = BinaryReaderImpl(bytes, Hive);
      final profile = UserProfileAdapter().read(reader);

      expect(profile.onboardingCompleted, isFalse);
      expect(profile.preferredStatId, isNull);
    });
  });
}
