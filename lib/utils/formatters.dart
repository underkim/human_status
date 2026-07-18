import 'package:intl/intl.dart';

final _numberFormat = NumberFormat('#,##0');

/// 금액을 천 단위 콤마 + "원"으로 표시한다. 화면마다 `amount.toInt().toString()`로
/// raw 숫자를 그대로 찍던 걸 통일 — 콤마 없는 큰 숫자는 자릿수를 즉시 읽기 어렵다.
String formatWon(num amount) => '${_numberFormat.format(amount.round())}원';

/// "원" 접미사 없이 숫자만 콤마로 포맷(다른 단위·라벨과 조합할 때 사용).
String formatNumber(num amount) => _numberFormat.format(amount.round());

/// 차트 축처럼 좁은 자리에 쓰는 축약 표기 — 4,230만 / 1.2억 / 3,500.
/// 전체 자릿수(formatWon)는 본문·상세에, 이건 축·요약 라벨 전용.
String formatWonCompact(num amount) {
  final v = amount.round();
  final abs = v.abs();
  final sign = v < 0 ? '-' : '';
  if (abs >= 100000000) {
    final eok = abs / 100000000;
    final text = eok >= 10
        ? eok.round().toString()
        : eok.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return '$sign$text억';
  }
  if (abs >= 10000) {
    return '$sign${_numberFormat.format((abs / 10000).round())}만';
  }
  return '$sign${_numberFormat.format(abs)}';
}

/// 목표 기한까지 남은 일수를 "D-84"/"D-DAY"/"기한 12일 지남" 형태로 — 절대
/// 날짜(2026.10.04)보다 "얼마나 남았는지"가 더 즉각적으로 와닿는다.
String formatDday(DateTime target, {DateTime? now}) {
  final current = now ?? DateTime.now();
  // UTC is only a stable ordinal for these local calendar fields. Unlike
  // subtracting local midnights, it remains a whole day across DST changes.
  final todayOrdinal = DateTime.utc(current.year, current.month, current.day);
  final targetOrdinal = DateTime.utc(target.year, target.month, target.day);
  final days = targetOrdinal.difference(todayOrdinal).inDays;
  if (days == 0) return 'D-DAY';
  if (days < 0) return '기한 ${-days}일 지남';
  return 'D-$days';
}
