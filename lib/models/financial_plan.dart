import 'package:hive/hive.dart';

/// A single, revisitable long-term financial plan (retirement / home
/// purchase). Stored as one record per user, like UserProfile.
class FinancialPlan {
  DateTime updatedAt;
  double expectedAnnualReturnPercent;

  bool retirementEnabled;
  int? currentAge;
  int? retirementAge;
  double? monthlyLivingCostAfterRetirement;
  double retirementCurrentSavings;

  bool homePurchaseEnabled;
  DateTime? homePurchaseTargetDate;
  double? homePurchaseTargetAmount;
  double homePurchaseCurrentSaved;

  /// 이번 달 지출 한도. null이면 예산 기능을 쓰지 않는 상태.
  double? monthlyBudget;

  FinancialPlan({
    required this.updatedAt,
    this.expectedAnnualReturnPercent = 0,
    this.retirementEnabled = false,
    this.currentAge,
    this.retirementAge,
    this.monthlyLivingCostAfterRetirement,
    this.retirementCurrentSavings = 0,
    this.homePurchaseEnabled = false,
    this.homePurchaseTargetDate,
    this.homePurchaseTargetAmount,
    this.homePurchaseCurrentSaved = 0,
    this.monthlyBudget,
  });

  Map<String, dynamic> toJson() => {
        'updatedAt': updatedAt.toIso8601String(),
        'expectedAnnualReturnPercent': expectedAnnualReturnPercent,
        'retirementEnabled': retirementEnabled,
        'currentAge': currentAge,
        'retirementAge': retirementAge,
        'monthlyLivingCostAfterRetirement': monthlyLivingCostAfterRetirement,
        'retirementCurrentSavings': retirementCurrentSavings,
        'homePurchaseEnabled': homePurchaseEnabled,
        'homePurchaseTargetDate': homePurchaseTargetDate?.toIso8601String(),
        'homePurchaseTargetAmount': homePurchaseTargetAmount,
        'homePurchaseCurrentSaved': homePurchaseCurrentSaved,
        'monthlyBudget': monthlyBudget,
      };

  factory FinancialPlan.fromJson(Map<String, dynamic> json) => FinancialPlan(
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        expectedAnnualReturnPercent: (json['expectedAnnualReturnPercent'] as num?)?.toDouble() ?? 0,
        retirementEnabled: json['retirementEnabled'] as bool? ?? false,
        currentAge: json['currentAge'] as int?,
        retirementAge: json['retirementAge'] as int?,
        monthlyLivingCostAfterRetirement: (json['monthlyLivingCostAfterRetirement'] as num?)?.toDouble(),
        retirementCurrentSavings: (json['retirementCurrentSavings'] as num?)?.toDouble() ?? 0,
        homePurchaseEnabled: json['homePurchaseEnabled'] as bool? ?? false,
        homePurchaseTargetDate: json['homePurchaseTargetDate'] != null
            ? DateTime.parse(json['homePurchaseTargetDate'] as String)
            : null,
        homePurchaseTargetAmount: (json['homePurchaseTargetAmount'] as num?)?.toDouble(),
        homePurchaseCurrentSaved: (json['homePurchaseCurrentSaved'] as num?)?.toDouble() ?? 0,
        monthlyBudget: (json['monthlyBudget'] as num?)?.toDouble(),
      );
}

class FinancialPlanAdapter extends TypeAdapter<FinancialPlan> {
  @override
  final int typeId = 6;

  @override
  FinancialPlan read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FinancialPlan(
      updatedAt: fields[0] as DateTime,
      expectedAnnualReturnPercent: fields[1] as double,
      retirementEnabled: fields[2] as bool,
      currentAge: fields[3] as int?,
      retirementAge: fields[4] as int?,
      monthlyLivingCostAfterRetirement: fields[5] as double?,
      retirementCurrentSavings: fields[6] as double,
      homePurchaseEnabled: fields[7] as bool,
      homePurchaseTargetDate: fields[8] as DateTime?,
      homePurchaseTargetAmount: fields[9] as double?,
      homePurchaseCurrentSaved: fields[10] as double,
      // 필드 11은 나중에 추가됨 — 구버전 레코드에는 없으므로 null(예산 미설정).
      monthlyBudget: fields[11] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, FinancialPlan obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.updatedAt)
      ..writeByte(1)
      ..write(obj.expectedAnnualReturnPercent)
      ..writeByte(2)
      ..write(obj.retirementEnabled)
      ..writeByte(3)
      ..write(obj.currentAge)
      ..writeByte(4)
      ..write(obj.retirementAge)
      ..writeByte(5)
      ..write(obj.monthlyLivingCostAfterRetirement)
      ..writeByte(6)
      ..write(obj.retirementCurrentSavings)
      ..writeByte(7)
      ..write(obj.homePurchaseEnabled)
      ..writeByte(8)
      ..write(obj.homePurchaseTargetDate)
      ..writeByte(9)
      ..write(obj.homePurchaseTargetAmount)
      ..writeByte(10)
      ..write(obj.homePurchaseCurrentSaved)
      ..writeByte(11)
      ..write(obj.monthlyBudget);
  }
}
