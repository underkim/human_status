import 'package:hive/hive.dart';

class UserProfile {
  DateTime? lastQuestRefresh;
  String? claudeApiKey;
  int? reminderMinutesSinceMidnight;
  DateTime? lastAdviceRefresh;
  // [{'category': String, 'message': String}, ...] — see AdviceItem in
  // financial_advice_source.dart for the typed wrapper around these.
  List<Map<String, dynamic>> cachedAdvice;
  // 일요일 저녁 주간 리포트 알림 사용 여부.
  bool weeklyReportReminderEnabled;
  // 첫 미션 온보딩 완료 여부. 새 UserProfile()은 false(신규 사용자)지만,
  // 이 필드가 없는 구버전 레코드를 읽을 때는 true로 취급한다 — 이미 앱을
  // 쓰던 기존 사용자를 업데이트 후 강제로 온보딩에 가두지 않기 위해서다.
  bool onboardingCompleted;
  // 온보딩에서 고른 우선 성장 스탯 id. GoalFormScreen의 신규 목표 추천에
  // 우선 적용되고, 유효하지 않거나(존재하지 않는 스탯 id) 없으면 기존
  // weakest-stat 추천으로 폴백한다.
  String? preferredStatId;

  UserProfile({
    this.lastQuestRefresh,
    this.claudeApiKey,
    this.reminderMinutesSinceMidnight,
    this.lastAdviceRefresh,
    List<Map<String, dynamic>>? cachedAdvice,
    this.weeklyReportReminderEnabled = false,
    this.onboardingCompleted = false,
    this.preferredStatId,
  }) : cachedAdvice = cachedAdvice ?? [];
}

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 2;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile(
      lastQuestRefresh: fields[0] as DateTime?,
      claudeApiKey: fields[1] as String?,
      reminderMinutesSinceMidnight: fields[2] as int?,
      lastAdviceRefresh: fields[3] as DateTime?,
      cachedAdvice: (fields[4] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      // 필드 5는 나중에 추가됨 — 구버전 레코드에는 없으므로 기본값 false.
      weeklyReportReminderEnabled: fields[5] as bool? ?? false,
      // 필드 6/7도 나중에 추가됨 — 구버전 레코드엔 없으므로 이미 쓰던
      // 사용자로 간주해 onboardingCompleted는 true로 읽는다.
      onboardingCompleted: fields[6] as bool? ?? true,
      preferredStatId: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.lastQuestRefresh)
      ..writeByte(1)
      ..write(obj.claudeApiKey)
      ..writeByte(2)
      ..write(obj.reminderMinutesSinceMidnight)
      ..writeByte(3)
      ..write(obj.lastAdviceRefresh)
      ..writeByte(4)
      ..write(obj.cachedAdvice)
      ..writeByte(5)
      ..write(obj.weeklyReportReminderEnabled)
      ..writeByte(6)
      ..write(obj.onboardingCompleted)
      ..writeByte(7)
      ..write(obj.preferredStatId);
  }
}
