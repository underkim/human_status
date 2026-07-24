// Phase 6 Part B 공통 접근성 테스트 하네스.
//
// 이 헬퍼들은 flutter_test의 widget 트리 안에서 확인 가능한 것만 검증한다
// (semantics tree 구조, 배율에 따른 overflow, Android/iOS tap-target
// guideline, 정적 대비 guideline). 실제 TalkBack/VoiceOver/Narrator/Orca
// 낭독 순서나 플랫폼별 accessibility bridge 변환은 이 하네스로 검증할 수
// 없다 — 그 부분은 6플랫폼 수동 QA가 필요하며 이 저장소 환경에서는
// 실행하지 못한다(docs/plans/S_GRADE_MASTER_PLAYBOOK.md 참고).
import 'package:flutter_test/flutter_test.dart';

/// [textScaleFactor] 아래에서 [pump]를 실행하고 첫 프레임에 레이아웃
/// overflow(FlutterError)가 없는지 확인한다. 1.0/1.3/2.0과, 더 큰 배율
/// 하나(플랫폼이 허용하는 상한에 가까운 3.0)를 기본으로 점검한다.
Future<void> expectNoOverflowAtTextScales(
  WidgetTester tester,
  Future<void> Function(double textScale) pump, {
  List<double> scales = const [1.0, 1.3, 2.0, 3.0],
}) async {
  for (final scale in scales) {
    await pump(scale);
    expect(
      tester.takeException(),
      isNull,
      reason: 'textScale=$scale에서 레이아웃 예외가 발생했다',
    );
  }
}

/// 현재 [tester]에 pump된 화면 전체의 semantics tree에서 탭 가능한 모든
/// 노드가 Android(48dp)·iOS(44pt) 최소 조작 영역 guideline을 만족하는지
/// 확인한다. `meetsGuideline`의 실제 대상은 특정 위젯이 아니라 tester
/// 자체다 — 현재 렌더된 semantics tree 전체를 훑는다.
Future<void> expectMeetsTapTargetGuidelines(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  } finally {
    handle.dispose();
  }
}

/// 현재 [tester]에 pump된 화면 전체가 텍스트 명도 대비 guideline(일반
/// 텍스트 4.5:1, 큰 텍스트 3:1)을 만족하는지 확인한다.
Future<void> expectMeetsContrastGuideline(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  } finally {
    handle.dispose();
  }
}

/// [label]이 현재 semantics tree에 존재하는지 — 즉 화면에 그려지고
/// 보조기술에 노출되는지 — 확인한다. `find.text`와 달리 페인트/hit-test에서
/// 제외된(IndexedStack의 비활성 탭 등) 위젯은 찾지 못한다.
Finder findBySemanticsLabelContaining(String label) =>
    find.bySemanticsLabel(RegExp(RegExp.escape(label)));
