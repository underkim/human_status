import 'package:hive/hive.dart';

class UserProfile {
  DateTime? lastQuestRefresh;
  String? claudeApiKey;
  int? reminderMinutesSinceMidnight;

  UserProfile({
    this.lastQuestRefresh,
    this.claudeApiKey,
    this.reminderMinutesSinceMidnight,
  });
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
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.lastQuestRefresh)
      ..writeByte(1)
      ..write(obj.claudeApiKey)
      ..writeByte(2)
      ..write(obj.reminderMinutesSinceMidnight);
  }
}
