import 'package:hive/hive.dart';

class UserProfile {
  DateTime? lastQuestRefresh;
  String? claudeApiKey;
  int? reminderMinutesSinceMidnight;
  DateTime? lastAdviceRefresh;
  // [{'category': String, 'message': String}, ...] — see AdviceItem in
  // financial_advice_source.dart for the typed wrapper around these.
  List<Map<String, dynamic>> cachedAdvice;

  UserProfile({
    this.lastQuestRefresh,
    this.claudeApiKey,
    this.reminderMinutesSinceMidnight,
    this.lastAdviceRefresh,
    List<Map<String, dynamic>>? cachedAdvice,
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
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.lastQuestRefresh)
      ..writeByte(1)
      ..write(obj.claudeApiKey)
      ..writeByte(2)
      ..write(obj.reminderMinutesSinceMidnight)
      ..writeByte(3)
      ..write(obj.lastAdviceRefresh)
      ..writeByte(4)
      ..write(obj.cachedAdvice);
  }
}
