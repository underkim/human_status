import 'package:hive/hive.dart';

/// A point-in-time snapshot of assets/liabilities, typically imported from a
/// Banksalad "현황.csv" export. Totals are computed at import time from the
/// per-category breakdown rather than trusted from the source file's own
/// summary row (see AssetSnapshotImportService for why).
class AssetSnapshot {
  final String id;
  DateTime importedAt;
  Map<String, double> assetsByCategory;
  Map<String, double> liabilitiesByCategory;
  double totalAssets;
  double totalLiabilities;

  AssetSnapshot({
    required this.id,
    required this.importedAt,
    required this.assetsByCategory,
    required this.liabilitiesByCategory,
    required this.totalAssets,
    required this.totalLiabilities,
  });

  double get netWorth => totalAssets - totalLiabilities;

  Map<String, dynamic> toJson() => {
        'id': id,
        'importedAt': importedAt.toIso8601String(),
        'assetsByCategory': assetsByCategory,
        'liabilitiesByCategory': liabilitiesByCategory,
        'totalAssets': totalAssets,
        'totalLiabilities': totalLiabilities,
      };

  factory AssetSnapshot.fromJson(Map<String, dynamic> json) => AssetSnapshot(
        id: json['id'] as String,
        importedAt: DateTime.parse(json['importedAt'] as String),
        assetsByCategory: (json['assetsByCategory'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        liabilitiesByCategory: (json['liabilitiesByCategory'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        totalAssets: (json['totalAssets'] as num).toDouble(),
        totalLiabilities: (json['totalLiabilities'] as num).toDouble(),
      );
}

class AssetSnapshotAdapter extends TypeAdapter<AssetSnapshot> {
  @override
  final int typeId = 5;

  @override
  AssetSnapshot read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AssetSnapshot(
      id: fields[0] as String,
      importedAt: fields[1] as DateTime,
      assetsByCategory: Map<String, double>.from(fields[2] as Map),
      liabilitiesByCategory: Map<String, double>.from(fields[3] as Map),
      totalAssets: fields[4] as double,
      totalLiabilities: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, AssetSnapshot obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.importedAt)
      ..writeByte(2)
      ..write(obj.assetsByCategory)
      ..writeByte(3)
      ..write(obj.liabilitiesByCategory)
      ..writeByte(4)
      ..write(obj.totalAssets)
      ..writeByte(5)
      ..write(obj.totalLiabilities);
  }
}
