import '../models/quest.dart';

/// 홈 허브에서 강조할 "다음 퀘스트"를 결정하는 순수 규칙.
///
/// 스키마 변경 없이 결정적으로 하나만 고르기 위한 우선순위:
/// 1) 목표에 연결된(goalId != null) 진행중 퀘스트
/// 2) 반복(isRecurring) 퀘스트
/// 3) 그 외 진행중 퀘스트
///
/// 각 그룹 안에서는 난이도가 쉬운 순(easy < medium < hard) → createdAt이
/// 오래된 순 → id 사전순으로 정렬해, 입력이 같으면 항상 같은 퀘스트를 고른다.
Quest? selectNextQuest(List<Quest> activeQuests) {
  if (activeQuests.isEmpty) return null;
  final sorted = [...activeQuests]..sort(_compareQuests);
  return sorted.first;
}

int _priorityClass(Quest q) {
  if (q.goalId != null) return 0;
  if (q.isRecurring) return 1;
  return 2;
}

int _compareQuests(Quest a, Quest b) {
  final classCompare = _priorityClass(a).compareTo(_priorityClass(b));
  if (classCompare != 0) return classCompare;
  final difficultyCompare = a.difficulty.index.compareTo(b.difficulty.index);
  if (difficultyCompare != 0) return difficultyCompare;
  final createdCompare = a.createdAt.compareTo(b.createdAt);
  if (createdCompare != 0) return createdCompare;
  return a.id.compareTo(b.id);
}
