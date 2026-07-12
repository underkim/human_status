import 'package:hive/hive.dart';

enum GoalStatus { active, completed, abandoned }

class Goal {
  final String id;
  String title;
  String description;
  String statId;
  DateTime? targetDate;
  // Non-null marks this as a financial goal, tracked by amount rather than
  // by linked-quest completion (see GoalService.progress).
  double? targetAmount;
  double currentAmount;
  GoalStatus status;
  DateTime createdAt;
  DateTime? completedAt;

  Goal({
    required this.id,
    required this.title,
    required this.description,
    required this.statId,
    this.targetDate,
    this.targetAmount,
    this.currentAmount = 0,
    this.status = GoalStatus.active,
    required this.createdAt,
    this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'statId': statId,
        'targetDate': targetDate?.toIso8601String(),
        'targetAmount': targetAmount,
        'currentAmount': currentAmount,
        'status': status.index,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        statId: json['statId'] as String,
        targetDate: json['targetDate'] != null
            ? DateTime.parse(json['targetDate'] as String)
            : null,
        targetAmount: (json['targetAmount'] as num?)?.toDouble(),
        currentAmount: (json['currentAmount'] as num).toDouble(),
        status: GoalStatus.values[json['status'] as int],
        createdAt: DateTime.parse(json['createdAt'] as String),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );
}

class GoalAdapter extends TypeAdapter<Goal> {
  @override
  final int typeId = 3;

  @override
  Goal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Goal(
      id: fields[0] as String,
      title: fields[1] as String,
      description: fields[2] as String,
      statId: fields[3] as String,
      targetDate: fields[4] as DateTime?,
      targetAmount: fields[5] as double?,
      currentAmount: fields[6] as double,
      status: GoalStatus.values[fields[7] as int],
      createdAt: fields[8] as DateTime,
      completedAt: fields[9] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Goal obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.statId)
      ..writeByte(4)
      ..write(obj.targetDate)
      ..writeByte(5)
      ..write(obj.targetAmount)
      ..writeByte(6)
      ..write(obj.currentAmount)
      ..writeByte(7)
      ..write(obj.status.index)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.completedAt);
  }
}
