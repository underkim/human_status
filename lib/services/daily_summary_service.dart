import '../models/quest.dart';
import 'xp_service.dart';

/// 오늘(로컬 달력 기준) 완료한 퀘스트 개수와 실지급 XP 합계.
class DailySummary {
  final int completedCount;
  final double xp;

  const DailySummary({required this.completedCount, required this.xp});
}

/// 같은 로컬 달력 날짜(연/월/일)인지 비교한다 — 24시간 경과가 아니라 자정
/// 기준으로 "오늘"을 판단하므로 자정 근처에서도 안정적이다.
bool isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// [now]가 속한 로컬 날짜에 완료된 퀘스트만 골라 개수와 XP 합을 낸다.
/// XP는 [XpService.effectiveRewards]를 그대로 사용해 목표 연결 보너스가 실제
/// 지급액과 항상 일치하도록 한다. [now]를 주입할 수 있어 벽시계에 기대지
/// 않고도 테스트할 수 있다.
DailySummary computeTodaySummary(List<Quest> quests, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final completedToday = quests.where(
    (q) =>
        q.status == QuestStatus.completed &&
        q.completedAt != null &&
        !q.completedAt!.isAfter(today) &&
        isSameLocalDay(q.completedAt!, today),
  );

  double xp = 0;
  var count = 0;
  for (final q in completedToday) {
    count++;
    for (final reward in XpService.effectiveRewards(q).values) {
      xp += reward;
    }
  }
  return DailySummary(completedCount: count, xp: xp);
}

/// [xp]를 사용자에게 보여줄 문자열로 만든다 — 정수면 소수점 없이("10"),
/// 소수라면 실제 지급액이 뭉개지지 않도록 소수점을 살리되("1.5") 부동소수점
/// 연산의 잡음(예: 14.999999999999998)은 걷어낸다. [XpService.effectiveRewards]가
/// 만들어내는 값과 화면 표시가 항상 일치해야 하므로, 반올림으로 실제 지급액을
/// 감추지 않는다.
String formatXp(double xp) {
  final rounded = double.parse(xp.toStringAsFixed(2));
  if (rounded == rounded.roundToDouble()) {
    return rounded.toInt().toString();
  }
  var text = rounded.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
