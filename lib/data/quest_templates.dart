import '../models/quest.dart';

class QuestTemplate {
  final String title;
  final String description;
  final String statId;
  final QuestDifficulty difficulty;
  final double baseXp;

  const QuestTemplate({
    required this.title,
    required this.description,
    required this.statId,
    required this.difficulty,
    required this.baseXp,
  });
}

const questTemplateBank = <QuestTemplate>[
  // health
  QuestTemplate(
    title: '물 8잔 마시기',
    description: '오늘 하루 물 8잔(약 2L)을 채워 마셔보세요.',
    statId: 'health',
    difficulty: QuestDifficulty.easy,
    baseXp: 15,
  ),
  QuestTemplate(
    title: '30분 걷기',
    description: '가볍게 30분 이상 걸으며 몸을 움직여보세요.',
    statId: 'health',
    difficulty: QuestDifficulty.easy,
    baseXp: 20,
  ),
  QuestTemplate(
    title: '운동 세션 완료하기',
    description: '헬스, 홈트, 러닝 등 운동 세션을 하나 완료하세요.',
    statId: 'health',
    difficulty: QuestDifficulty.medium,
    baseXp: 35,
  ),
  QuestTemplate(
    title: '7시간 이상 수면하기',
    description: '오늘 밤 7시간 이상 충분히 잠을 자보세요.',
    statId: 'health',
    difficulty: QuestDifficulty.medium,
    baseXp: 30,
  ),

  // intelligence
  QuestTemplate(
    title: '책 20페이지 읽기',
    description: '읽고 있는 책을 20페이지 이상 읽어보세요.',
    statId: 'intelligence',
    difficulty: QuestDifficulty.easy,
    baseXp: 20,
  ),
  QuestTemplate(
    title: '새로운 개념 정리하기',
    description: '최근 배운 개념 하나를 노트에 정리해보세요.',
    statId: 'intelligence',
    difficulty: QuestDifficulty.easy,
    baseXp: 20,
  ),
  QuestTemplate(
    title: '온라인 강의 1개 수강하기',
    description: '관심 있는 분야의 강의를 하나 들어보세요.',
    statId: 'intelligence',
    difficulty: QuestDifficulty.medium,
    baseXp: 35,
  ),
  QuestTemplate(
    title: '배운 것으로 글쓰기',
    description: '최근 배운 내용을 짧은 글로 정리해 남겨보세요.',
    statId: 'intelligence',
    difficulty: QuestDifficulty.hard,
    baseXp: 50,
  ),

  // wealth
  QuestTemplate(
    title: '이번 주 지출 내역 정리하기',
    description: '이번 주 지출을 카테고리별로 정리해보세요.',
    statId: 'wealth',
    difficulty: QuestDifficulty.easy,
    baseXp: 20,
  ),
  QuestTemplate(
    title: '불필요한 구독 서비스 점검하기',
    description: '사용하지 않는 구독 서비스가 있는지 확인하고 정리해보세요.',
    statId: 'wealth',
    difficulty: QuestDifficulty.easy,
    baseXp: 15,
  ),
  QuestTemplate(
    title: '이번 달 예산 세우기',
    description: '이번 달 예산 계획을 세워보세요.',
    statId: 'wealth',
    difficulty: QuestDifficulty.medium,
    baseXp: 35,
  ),
  QuestTemplate(
    title: '저축/투자 자동이체 설정하기',
    description: '저축이나 투자를 위한 자동이체를 설정해보세요.',
    statId: 'wealth',
    difficulty: QuestDifficulty.hard,
    baseXp: 50,
  ),

  // relationships
  QuestTemplate(
    title: '오랜만에 안부 연락하기',
    description: '한동안 연락하지 못한 사람에게 안부를 물어보세요.',
    statId: 'relationships',
    difficulty: QuestDifficulty.easy,
    baseXp: 15,
  ),
  QuestTemplate(
    title: '가족과 대화하기',
    description: '가족과 10분 이상 대화를 나눠보세요.',
    statId: 'relationships',
    difficulty: QuestDifficulty.easy,
    baseXp: 20,
  ),
  QuestTemplate(
    title: '친구와 약속 잡기',
    description: '친구와 만날 약속을 잡아보세요.',
    statId: 'relationships',
    difficulty: QuestDifficulty.medium,
    baseXp: 35,
  ),
  QuestTemplate(
    title: '고마운 사람에게 감사 표현하기',
    description: '고마움을 느꼈던 사람에게 직접 감사를 표현해보세요.',
    statId: 'relationships',
    difficulty: QuestDifficulty.medium,
    baseXp: 30,
  ),

  // mental
  QuestTemplate(
    title: '10분 명상하기',
    description: '조용한 곳에서 10분간 명상해보세요.',
    statId: 'mental',
    difficulty: QuestDifficulty.easy,
    baseXp: 20,
  ),
  QuestTemplate(
    title: '오늘의 감사한 일 3가지 적기',
    description: '오늘 하루 감사했던 일 3가지를 적어보세요.',
    statId: 'mental',
    difficulty: QuestDifficulty.easy,
    baseXp: 15,
  ),
  QuestTemplate(
    title: '디지털 디톡스 1시간',
    description: '스마트폰/SNS 없이 1시간을 보내보세요.',
    statId: 'mental',
    difficulty: QuestDifficulty.medium,
    baseXp: 30,
  ),
  QuestTemplate(
    title: '스트레스 원인 정리하고 대응책 세우기',
    description: '요즘 스트레스의 원인을 정리하고 대응 방법을 생각해보세요.',
    statId: 'mental',
    difficulty: QuestDifficulty.hard,
    baseXp: 50,
  ),
];
