import 'package:hive/hive.dart';

class Stat {
  final String id;
  String name;
  String icon;
  int level;
  double currentXp;

  Stat({
    required this.id,
    required this.name,
    required this.icon,
    this.level = 1,
    this.currentXp = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'level': level,
        'currentXp': currentXp,
      };

  factory Stat.fromJson(Map<String, dynamic> json) => Stat(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        level: json['level'] as int,
        currentXp: (json['currentXp'] as num).toDouble(),
      );
}

class StatAdapter extends TypeAdapter<Stat> {
  @override
  final int typeId = 0;

  @override
  Stat read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Stat(
      id: fields[0] as String,
      name: fields[1] as String,
      icon: fields[2] as String,
      level: fields[3] as int,
      currentXp: fields[4] as double,
    );
  }

  @override
  void write(BinaryWriter writer, Stat obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.icon)
      ..writeByte(3)
      ..write(obj.level)
      ..writeByte(4)
      ..write(obj.currentXp);
  }
}
