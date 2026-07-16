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
  // Set when this quest was generated as part of breaking a Goal down into
  // actionable steps (see GoalService.decompose). Null for regular quests.
  String? goalId;

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
    this.goalId,
  });

  /// A detached clone of every field. Used to snapshot a quest (for
  /// rollback) or build a mutated candidate without touching the live
  /// Hive-boxed instance — see GoalsNotifier.deleteGoal.
  Quest copy() => Quest(
        id: id,
        title: title,
        description: description,
        statRewards: Map<String, double>.from(statRewards),
        difficulty: difficulty,
        isRecurring: isRecurring,
        status: status,
        source: source,
        createdAt: createdAt,
        completedAt: completedAt,
        goalId: goalId,
      );

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
        'goalId': goalId,
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
        goalId: json['goalId'] as String?,
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
      goalId: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Quest obj) {
    writer
      ..writeByte(11)
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
      ..write(obj.completedAt)
      ..writeByte(10)
      ..write(obj.goalId);
  }
}
