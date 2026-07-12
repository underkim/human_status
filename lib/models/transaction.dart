import 'package:hive/hive.dart';

enum TransactionType { income, expense }

class Transaction {
  final String id;
  TransactionType type;
  String category;
  String memo;
  double amount;
  DateTime date;
  // If set, this transaction's amount contributes to a financial Goal's
  // currentAmount (see FinanceService.addTransaction).
  String? linkedGoalId;
  DateTime createdAt;

  Transaction({
    required this.id,
    required this.type,
    required this.category,
    required this.memo,
    required this.amount,
    required this.date,
    this.linkedGoalId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'category': category,
        'memo': memo,
        'amount': amount,
        'date': date.toIso8601String(),
        'linkedGoalId': linkedGoalId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json['id'] as String,
        type: TransactionType.values[json['type'] as int],
        category: json['category'] as String,
        memo: json['memo'] as String,
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date'] as String),
        linkedGoalId: json['linkedGoalId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class TransactionAdapter extends TypeAdapter<Transaction> {
  @override
  final int typeId = 4;

  @override
  Transaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Transaction(
      id: fields[0] as String,
      type: TransactionType.values[fields[1] as int],
      category: fields[2] as String,
      memo: fields[3] as String,
      amount: fields[4] as double,
      date: fields[5] as DateTime,
      linkedGoalId: fields[6] as String?,
      createdAt: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Transaction obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type.index)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.memo)
      ..writeByte(4)
      ..write(obj.amount)
      ..writeByte(5)
      ..write(obj.date)
      ..writeByte(6)
      ..write(obj.linkedGoalId)
      ..writeByte(7)
      ..write(obj.createdAt);
  }
}
