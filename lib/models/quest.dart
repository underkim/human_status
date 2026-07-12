import 'package:hive/hive.dart';

enum QuestDifficulty { easy, medium, hard }

enum QuestStatus { active, completed, dismissed, suggested }

enum QuestSource { manual, suggested }

class Quest {
  final String id;
  String title;
  String description;
  // statId -> xp awarded to that stat on completion
  Map<String, double> statRewards;
  QuestDifficulty difficulty;
  bool isRecurring;
  QuestStatus status;
  QuestSource source;
  DateTime createdAt;
  DateTime? completedAt;

  Quest({
    required this.id,
    required this.title,
    required this.description,
    required this.statRewards,
    this.difficulty = QuestDifficulty.easy,
    this.isRecurring = false,
    this.status = QuestStatus.active,
    this.source = QuestSource.manual,
    required this.createdAt,
    this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'statRewards': statRewards,
        'difficulty': difficulty.index,
        'isRecurring': isRecurring,
        'status': status.index,
        'source': source.index,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        statRewards: (json['statRewards'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        difficulty: QuestDifficulty.values[json['difficulty'] as int],
        isRecurring: json['isRecurring'] as bool,
        status: QuestStatus.values[json['status'] as int],
        source: QuestSource.values[json['source'] as int],
        createdAt: DateTime.parse(json['createdAt'] as String),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );
}

class QuestAdapter extends TypeAdapter<Quest> {
  @override
  final int typeId = 1;

  @override
  Quest read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Quest(
      id: fields[0] as String,
      title: fields[1] as String,
      description: fields[2] as String,
      statRewards: Map<String, double>.from(fields[3] as Map),
      difficulty: QuestDifficulty.values[fields[4] as int],
      isRecurring: fields[5] as bool,
      status: QuestStatus.values[fields[6] as int],
      source: QuestSource.values[fields[7] as int],
      createdAt: fields[8] as DateTime,
      completedAt: fields[9] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Quest obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.statRewards)
      ..writeByte(4)
      ..write(obj.difficulty.index)
      ..writeByte(5)
      ..write(obj.isRecurring)
      ..writeByte(6)
      ..write(obj.status.index)
      ..writeByte(7)
      ..write(obj.source.index)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.completedAt);
  }
}
