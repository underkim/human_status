/// 4px 기준 여백 스케일. 화면마다 임의의 여백 숫자를 새로 정하지 않도록
/// 모든 SizedBox/EdgeInsets는 이 상수를 통해서만 사용한다.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// 모서리 둥글기 스케일.
class AppRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double full = 999;
}

/// 아이콘 크기 스케일.
class AppIconSize {
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
}

/// 버튼·입력창 높이와 모바일 최소 터치 영역.
/// minTouchTarget(48)은 Android 접근성 가이드 기준(iOS는 44) 중 더 엄격한
/// 쪽을 채택해 둘 다 만족시킨다 — 작은 인라인 버튼도 시각적 높이와 별개로
/// 탭 가능 영역은 이 값 이상을 유지해야 한다.
class AppDimens {
  static const double buttonHeightStandard = 44;
  static const double buttonHeightLarge = 52;
  static const double inputHeightStandard = 52;
  static const double minTouchTarget = 48;
}

/// Material 3 어댑티브 브레이크포인트. 기존 구조 설계 문서(정보 구조 &
/// 반응형 내비게이션 설계안)의 Compact/Medium/Expanded 정의와 동일하다.
class AppBreakpoints {
  static const double compactMax = 600;
  static const double mediumMax = 840;

  static bool isCompact(double width) => width < compactMax;
  static bool isMedium(double width) => width >= compactMax && width < mediumMax;
  static bool isExpanded(double width) => width >= mediumMax;
}
