class GoalIdea {
  final String title;
  final String description;
  final String statId;

  const GoalIdea({required this.title, required this.description, required this.statId});
}

/// Curated longer-term goal ideas per stat, used to suggest what goal to set
/// (as opposed to quest_templates.dart's short-term quest ideas). Surfaced
/// in goal_form_screen.dart, prioritized toward the user's weakest stat.
const goalIdeaBank = <GoalIdea>[
  // health
  GoalIdea(title: '체중 5kg 감량하기', description: '식단과 운동을 병행해 건강한 체중을 만들어보세요.', statId: 'health'),
  GoalIdea(title: '10km 완주하기', description: '꾸준한 러닝 훈련으로 10km 완주에 도전해보세요.', statId: 'health'),
  GoalIdea(title: '매일 만보 걷기 습관 만들기', description: '3개월 동안 매일 만보 걷기를 목표로 해보세요.', statId: 'health'),

  // intelligence (growth)
  GoalIdea(title: '관련 자격증 취득하기', description: '커리어에 도움이 되는 자격증 취득을 목표로 준비해보세요.', statId: 'intelligence'),
  GoalIdea(title: '책 50권 읽기', description: '1년 동안 다양한 분야의 책 50권 읽기에 도전해보세요.', statId: 'intelligence'),
  GoalIdea(title: '새로운 언어 기초 마스터하기', description: '외국어 하나를 정해 기초 회화까지 익혀보세요.', statId: 'intelligence'),

  // wealth
  GoalIdea(title: '비상금 모으기', description: '예상치 못한 지출에 대비할 비상금을 마련해보세요.', statId: 'wealth'),
  GoalIdea(title: '불필요한 지출 줄이기', description: '고정 지출을 점검하고 절약 습관을 만들어보세요.', statId: 'wealth'),
  GoalIdea(title: '투자 공부 시작하기', description: '기초부터 차근차근 투자 지식을 쌓아보세요.', statId: 'wealth'),

  // relationships
  GoalIdea(title: '가족과 여행 다녀오기', description: '소중한 사람들과 함께할 여행을 계획해보세요.', statId: 'relationships'),
  GoalIdea(title: '오랜 친구와 관계 회복하기', description: '한동안 소원했던 친구에게 먼저 연락해보세요.', statId: 'relationships'),
  GoalIdea(title: '한 달에 한 번 모임 만들기', description: '주변 사람들과 정기적으로 만나는 자리를 만들어보세요.', statId: 'relationships'),

  // mental
  GoalIdea(title: '매일 명상 습관 만들기', description: '하루 10분씩 명상하는 습관을 들여보세요.', statId: 'mental'),
  GoalIdea(title: '번아웃 없이 3개월 보내기', description: '휴식과 일의 균형을 관리하는 루틴을 만들어보세요.', statId: 'mental'),
  GoalIdea(title: '감정 일기 쓰기 습관 만들기', description: '매일 짧게라도 감정을 기록하는 습관을 만들어보세요.', statId: 'mental'),
];
