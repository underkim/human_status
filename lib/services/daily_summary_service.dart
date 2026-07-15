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
