# Phase 5 감성적 훅 강화 구현 계획

## 0. 결론

- **Part A — 마이크로 애니메이션: 이번 Phase에서 구현한다.** 외부 애니메이션 패키지나 에셋 없이 Flutter SDK의 `AnimatedScale`, `AnimatedSwitcher`, `FadeTransition`, `ScaleTransition`, `AnimationController`만 사용한다. 퀘스트 완료 버튼은 누르는 즉시 짧게 축소·복원되고 처리 중 표시로 전환되며, 성공 시 나타나는 레벨업/업적 다이얼로그는 페이드·스케일 등장 효과를 갖는다.
- **Part B — 완료/레벨업 공유 카드: 이번 Phase에서 제외하고 별도 Phase로 미룬다.** 카드 캡처 자체는 순수 Flutter API로 가능하지만, 6개 플랫폼에서 이미지 파일을 OS 공유 대상으로 넘기는 일은 새 플러그인, 플랫폼별 동작 차이, 실제 OS/브라우저 검증을 요구한다. 특히 Linux 이미지 파일 공유 미지원과 Web Share API의 제한 때문에 현재 세션에서 안전하게 완결할 수 없다.
- 이번 Phase의 제품 성과는 “완료 탭 직후 반응”과 “성공 결과의 시각적 강조”에 한정한다. 공유 버튼, 공유 카드 UI, 캡처 코드, `share_plus` 의존성은 추가하지 않는다.

## 1. 현재 구조와 변경 원칙

현재 `lib/widgets/level_up_dialog.dart`의 `showLevelUpDialog`와 `lib/widgets/achievement_dialog.dart`의 `showAchievementDialog`는 각각 정적 `AlertDialog`를 연다. 퀘스트 완료 성공 흐름은 다음 세 곳에서 `SnackBar → showLevelUpDialog → showAchievementDialog` 순서로 직렬 실행된다.

1. `lib/screens/quests_screen.dart`의 `_ActiveTabState._completeQuest`
2. `lib/widgets/action_hub_card.dart`의 `_ActionHubCardState._completeHighlighted`
3. `lib/screens/dashboard_screen.dart`의 `_RemainingActiveQuestsState._completeQuest`

또한 동일 공개 함수는 `lib/screens/goals_screen.dart`와 `lib/screens/goal_form_screen.dart`에서도 호출한다. 따라서 공개 함수명과 인자 형식은 유지해 기존 목표 완료 흐름까지 자동으로 같은 개선을 얻도록 한다. `QuestCompletionResult.didComplete == false`는 현재처럼 조용한 무결과로 취급하고 성공 애니메이션을 내보내지 않는다.

완료 버튼은 현재 `QuestCard.actions`에 호출자가 `FilledButton`을 주입하는 구조다. `QuestCard` 자체에 비즈니스 로직을 넣지 않고 재사용 버튼 위젯을 만들어 세 퀘스트 완료 진입점에서 사용한다. 추천 채택, 수정, 삭제 버튼은 Phase 범위 밖이다.

## 2. Part A — 마이크로 애니메이션

### 2.1 범위

포함:

- 완료 버튼 탭 직후 짧은 펄스와 처리 중 상태로의 부드러운 전환
- 레벨업 다이얼로그의 페이드·스케일 등장
- 업적 다이얼로그의 페이드·스케일 등장
- 모션 감소 설정 대응
- Android, iOS, Windows, macOS, Linux, Web에서 동일 Flutter 코드 경로 사용
- 위젯 테스트와 정적 분석

제외:

- Lottie, Rive, confetti, 진동/햅틱, 사운드
- 파티클처럼 매 프레임 많은 객체를 그리는 효과
- 앱 전역 애니메이션 큐 또는 영속 “축하 상태”
- 공유 카드 및 공유 버튼

### 2.2 파일별 작업

#### 신규: `lib/widgets/quest_completion_button.dart`

`QuestCompletionButton extends StatefulWidget`를 만든다.

- 입력:
  - `VoidCallback? onPressed`
  - `bool isCompleting`
- 평상시에는 기존과 동일한 `FilledButton`과 “완료” 텍스트를 렌더링한다.
- 탭 직후 부모의 비동기 작업 시작과 별개로 로컬 `AnimationController`를 `forward().then(reverse)`하여 짧은 `ScaleTransition` 펄스를 실행한다. 콜백은 한 번만 즉시 호출한다.
- `isCompleting == true`가 되면 `AnimatedSwitcher`로 `pendingActionIndicator('완료 처리 중')`를 표시한다. 로딩 중 `onPressed`는 `null`이며 기존 중복 완료 방지 의미를 보존한다.
- 성공 여부가 확정되기 전에 체크마크를 낙관적으로 보여주지 않는다. 현재 `completeQuest`가 provider 목록을 즉시 갱신하여 성공한 `QuestCard`가 사라지거나 다른 카드로 바뀔 수 있으므로, 버튼 내부 성공 체크 애니메이션은 오히려 실패/경합 시 거짓 피드백 또는 보이지 않는 프레임이 된다. 이번 Phase의 성공 체크 역할은 뒤이어 표시되는 레벨업/업적 콘텐츠의 아이콘이 담당한다.
- `didUpdateWidget`에서 `isCompleting` 변화에 따라 별도 컨트롤러를 돌리지 않는다. 탭 펄스와 `AnimatedSwitcher`만 사용해 경합과 재빌드에 강하게 유지한다.
- `dispose`에서 `AnimationController.dispose()`를 호출하고, `TickerFuture` 완료 후 `mounted`를 확인한 뒤 로컬 상태를 변경한다.
- `MediaQuery.disableAnimationsOf(context)`가 true이면 컨트롤러를 실행하지 않고 최종 처리 중 상태를 즉시 표시한다.

#### 수정: `lib/screens/quests_screen.dart`

- `_ActiveTabState.build`의 완료용 `FilledButton`을 `QuestCompletionButton(onPressed: ..., isCompleting: completing)`으로 교체한다.
- `_completingQuests`, `_pendingDeletes`, `_isBusy`, `_completeQuest`의 Riverpod 호출 및 중복 방지 로직은 유지한다.
- 현재 직접 만든 16×16 `CircularProgressIndicator` 대신 공용 `pendingActionIndicator('완료 처리 중')`를 버튼 내부에서 사용하여 semantics를 홈과 통일한다.
- `didComplete == false`, 예외, `mounted` 가드, 다이얼로그 호출 순서는 바꾸지 않는다.

#### 수정: `lib/widgets/action_hub_card.dart`

- “다음 퀘스트”의 완료용 `FilledButton`만 `QuestCompletionButton`으로 교체한다.
- `_completingIds`와 `_completeHighlighted`는 유지한다.
- 추천 퀘스트의 “채택하고 시작” 버튼은 완료 액션이 아니므로 변경하지 않는다.

#### 수정: `lib/screens/dashboard_screen.dart`

- `_RemainingActiveQuestsState.build`의 완료용 `FilledButton`을 `QuestCompletionButton`으로 교체한다.
- `_completingIds`와 `_completeQuest`는 그대로 둔다.
- 상단 `ActionHubCard`와 하단 최대 3개 목록 모두 같은 완료 피드백을 갖는지 확인한다.

#### 신규: `lib/widgets/celebration_dialog_shell.dart`

레벨업과 업적 다이얼로그가 공유하는 표현 계층을 만든다.

- `CelebrationDialogShell extends StatelessWidget`는 `Dialog`를 바탕으로 `title`, `icon`, `children`, 확인 액션을 배치한다.
- `AlertDialog`의 기본 레이아웃을 복제하지 않고, `Dialog` 안의 `Padding`, `Column`, `SingleChildScrollView`로 작은 화면과 텍스트 확대에 대응한다.
- `Dialog` 자체의 shape/background는 `AppTheme`의 `dialogTheme`를 그대로 상속한다.
- 제목 아이콘은 `context.appColors.celebration`, 강조 전경은 `context.appColors.onCelebration`, 일반 본문과 버튼은 `Theme.of(context).colorScheme` 및 text theme를 사용한다.
- 모든 여백, 간격, radius, 아이콘 크기는 `AppSpacing`, `AppRadius`, `AppIconSize`, `AppDimens`만 사용한다. `4`, `6`, `8`, `24` 같은 임의 UI 수치를 새로 넣지 않는다.
- `Semantics(namesRoute: true, scopesRoute: true)`와 의미 있는 제목을 제공한다. 장식용 중복 아이콘은 `ExcludeSemantics`로 감싼다.

#### 수정: `lib/widgets/level_up_dialog.dart`

- 공개 함수 `Future<void> showLevelUpDialog(BuildContext context, List<Stat> stats, Map<String, LevelUpResult> results)`와 빈 결과 조기 반환을 유지한다.
- 별도 공개 또는 파일 내부 `LevelUpDialog extends StatelessWidget`로 콘텐츠를 분리해 직접 위젯 테스트할 수 있게 한다.
- `stats`를 id 기준 map으로 한 번 변환하여 현재의 `where(...).isNotEmpty` 후 `firstWhere` 이중 순회를 제거한다.
- `showGeneralDialog<void>`를 사용하고 `CelebrationDialogShell`을 builder 결과로 제공한다.
- 기본 경로 전환은 `FadeTransition`과 `ScaleTransition` 조합으로 제한한다. 화면 전체 blur, shadow 애니메이션, 반복 애니메이션은 사용하지 않는다.
- `MediaQuery.disableAnimationsOf(context)`가 true이면 `transitionDuration: Duration.zero`를 사용하고 transition builder는 최종 상태를 즉시 반환한다.
- 여러 stat이 동시에 레벨업하면 현재처럼 한 다이얼로그 안에 모두 표시한다. 목록은 `SingleChildScrollView`로 overflow를 방지한다.

#### 수정: `lib/widgets/achievement_dialog.dart`

- 공개 함수 `Future<void> showAchievementDialog(BuildContext context, List<AchievementDefinition> newAchievements)`와 빈 목록 조기 반환을 유지한다.
- `AchievementDialog extends StatelessWidget`로 콘텐츠를 분리한다.
- `showGeneralDialog<void>`와 `CelebrationDialogShell`을 사용한다.
- 업적별 아이콘·제목·설명은 기존 정보를 모두 유지한다. 여러 업적은 한 다이얼로그의 스크롤 가능한 목록으로 표시한다.
- 모션 감소 시 레벨업과 동일하게 즉시 최종 상태를 렌더링한다.

#### 수정: `test/helpers/test_app.dart`

- 기존 `pumpApp`의 기본 동작은 바꾸지 않는다.
- 테스트별 시스템 모션 설정을 명시할 수 있도록 선택 인자 `bool disableAnimations = false`를 추가하고 `MaterialApp`의 `builder`에서 `MediaQuery.copyWith(disableAnimations: disableAnimations)`를 적용한다. 기존 호출부는 기본값으로 영향받지 않는다.
- Flutter 테스트 API에서 뷰 접근 방식이 더 적합하면 테스트 자체에서 `tester.platformDispatcher.accessibilityFeaturesTestValue`를 설정하는 방안을 우선 검토하고, 안정적이면 헬퍼 변경 없이 사용한다. 어떤 방식이든 tear-down에서 값을 원복한다.

#### 신규: `test/delight_animation_test.dart`

다이얼로그와 버튼의 프레임, semantics, dispose 안전성을 집중 검증한다.

#### 수정: 기존 흐름 테스트

- `test/quests_screen_flow_test.dart`
- `test/dashboard_remaining_quest_test.dart`
- 필요 시 `test/dashboard_screen_test.dart`

기존 완료 흐름 단언이 위젯 타입 변경으로 깨지는 부분만 최소 수정한다. 완료 처리, 재시도, 경합, 다이얼로그 순서에 관한 기존 의미는 보존한다.

### 2.3 상태관리와 Riverpod 통합

애니메이션 상태는 도메인 상태가 아니므로 새 Riverpod provider를 만들지 않는다.

- 퀘스트 완료의 진실 소스: 기존 `questsProvider`와 `QuestCompletionResult`
- 요청 중/중복 방지: 기존 `_completingQuests` 또는 `_completingIds`
- 버튼 펄스 프레임: `QuestCompletionButton`의 로컬 `AnimationController`
- 다이얼로그 전환 프레임: `showGeneralDialog`의 route animation

이 구분으로 Hive에 일시적 UI 상태가 저장되지 않고, 다른 화면의 완료와 경합해도 기존 `didComplete` 계약이 유지된다. 애니메이션 때문에 `completeQuest` 호출을 지연하지 않는다. 펄스 시작과 콜백 호출은 같은 탭 이벤트에서 일어나며, 데이터 처리가 우선이다.

### 2.4 디자인 토큰

- 색상: `context.appColors.celebration`, `onCelebration`, `success`, `surfaceAlt`와 Material `ColorScheme`만 사용한다.
- 간격/패딩: `AppSpacing.xs`~`AppSpacing.xxxl`
- radius: `AppRadius.sm`~`AppRadius.full`
- 아이콘: `AppIconSize.sm`~`AppIconSize.xl`
- 터치 영역: 기존 `AppTheme.filledButtonTheme`와 `AppDimens.minTouchTarget`
- typography: `Theme.of(context).textTheme`

`AppColors`, `AppSpacing`, `AppTheme`에는 새 토큰을 추가하지 않는다. 애니메이션 duration과 curve는 색상/간격 토큰이 아니므로 해당 위젯 파일의 명명된 `static const`로 두되, 버튼과 다이얼로그 각각 한 곳에서만 정의한다.

### 2.5 접근성

- `MediaQuery.disableAnimationsOf(context)`를 모든 새 모션의 단일 판단 기준으로 사용한다. Flutter API는 이 값이 플랫폼의 애니메이션 비활성화 요청을 반영한다고 설명한다: [MediaQueryData.disableAnimations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html).
- 모션 감소 시 펄스, 페이드, 스케일을 생략하고 버튼의 처리 중 상태와 다이얼로그 최종 화면을 즉시 표시한다. 정보나 조작은 사라지지 않는다.
- 진행 중 표시는 기존 `pendingActionIndicator`의 “완료 처리 중” semantics를 재사용한다.
- 다이얼로그 제목은 route 이름으로 읽히고, “확인”은 최소 터치 영역을 유지하며 키보드/스크린리더로 닫을 수 있어야 한다.
- 장식용 이모지와 아이콘은 본문과 중복 낭독되지 않게 한다. 업적 아이콘이 고유 정보를 전달한다면 업적 제목과 묶인 한 개의 semantic label로 제공한다.
- 텍스트 배율이 커져도 내용이 화면을 넘치지 않도록 콘텐츠 영역을 스크롤 가능하게 한다.
- barrier에는 현지화 가능한 닫기 의미를 제공하고, 확인 버튼 외에 Android back, Escape 등 표준 route dismiss 동작을 유지한다.

### 2.6 6개 플랫폼 성능·호환성 조사와 검증 기준

이번 Part A의 `Transform.scale`과 opacity는 Flutter 프레임워크/엔진의 공통 primitive라 플랫폼별 네이티브 플러그인이 필요 없다. 플랫폼별 기능 차이보다는 GPU/CPU 성능, 창 크기, Web 렌더러와 브라우저 조합이 실제 차이다.

| 플랫폼 | 예상 차이와 계획 |
|---|---|
| Android | 저사양 기기와 60Hz 환경에서 첫 shader/프레임 지연 가능성을 profile build로 확인한다. 반복 파티클과 큰 blur를 쓰지 않고 단일 버튼 및 dialog subtree만 애니메이션한다. |
| iOS | 동일 Flutter transition을 사용한다. iOS “동작 줄이기”가 `disableAnimations`로 전달되는지 실제 기기에서 확인한다. |
| Windows | 데스크톱 창 크기와 키보드 Escape dismiss를 확인한다. 단일 scale/opacity라 별도 네이티브 설정은 없다. |
| macOS | macOS “동작 줄이기” 반영, 키보드 포커스와 다이얼로그 dismiss를 확인한다. |
| Linux | 데스크톱 환경별 접근성 설정 전달 여부가 다를 수 있으므로 Flutter가 제공한 `disableAnimations` 값만 신뢰하고 수동 QA도 한다. |
| Web | 브라우저/Flutter 웹 렌더러 조합에서 opacity와 scale 결과가 같아야 한다. 렌더러 구현 차이를 전제로 Chrome과 Safari/Firefox 계열에서 기능·프레임을 확인하고, 저사양 환경에서는 DevTools performance overlay로 jank를 본다. |

Flutter의 성능 지침에 따라 비싼 opacity/saveLayer 남용과 매 프레임 복잡한 clip을 피한다: [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices). `RepaintBoundary`는 Part A에 무조건 추가하지 않고 profile 측정에서 dialog 외부까지 불필요하게 repaint되는 근거가 있을 때만 고려한다. Flutter Web은 빌드/렌더링 모드에 차이가 있으므로 브라우저 QA를 별도 항목으로 둔다: [Flutter web support](https://docs.flutter.dev/platform-integration/web).

성능 승인 기준:

- profile mode에서 애니메이션 중 지속적인 jank가 없을 것
- 완료 버튼 한 개의 탭이 다른 `QuestCard` 전체에 반복 애니메이션을 만들지 않을 것
- 애니메이션 종료 후 ticker가 남지 않을 것
- Web에서 기능 차이가 생기면 시각 효과를 더 단순화하고 데이터 흐름은 유지할 것

### 2.7 구체적 테스트 계획

`test/delight_animation_test.dart`의 테스트 설명 문구와 핵심 단언:

1. **`완료 버튼을 누르면 즉시 한 번만 콜백하고 펄스 중 처리 중 표시로 전환한다`**
   - `QuestCompletionButton`을 pump하고 탭한다.
   - 콜백 횟수가 1인지 확인한다.
   - `tester.pump(const Duration(milliseconds: ...))`로 중간 프레임을 전진시켜 scale이 1보다 작은 구간이 존재하는지 확인한다.
   - 부모을 `isCompleting: true`로 rebuild하고 “완료 처리 중” semantics와 비활성 버튼을 확인한다.

2. **`완료 버튼 연타와 rebuild는 완료 콜백을 중복 실행하지 않는다`**
   - 첫 탭 직후 pending으로 전환하고 다시 탭한다.
   - 콜백이 한 번인지 확인한다.

3. **`모션 감소 설정에서는 완료 버튼이 중간 scale 없이 즉시 최종 상태가 된다`**
   - `disableAnimations: true`로 pump한다.
   - 탭 후 `tester.pump()`만으로 scale 1과 처리 중 UI를 확인한다.

4. **`레벨업 다이얼로그는 페이드와 스케일 중간 프레임 후 최종 내용을 표시한다`**
   - leveled-up `LevelUpResult`를 전달한다.
   - 최초, 중간 `pump(duration)`, 종료 프레임에서 transition 값을 비교한다.
   - “🎉 레벨업!”, stat 이름, `Lv.{newLevel}`, “확인”을 확인한다.

5. **`레벨업 결과가 없으면 route를 열지 않는다`**
   - 빈 map 또는 `leveledUp == false`만 있는 map을 전달하고 다이얼로그가 없는지 확인한다.

6. **`여러 stat 레벨업은 한 다이얼로그에 모두 표시한다`**
   - 두 개 이상의 entry를 넣고 route 수가 하나이며 각 stat 텍스트가 존재하는지 확인한다.

7. **`업적 다이얼로그는 여러 업적을 한 번만 열고 모두 읽을 수 있다`**
   - 여러 `AchievementDefinition`의 아이콘, 제목, 설명과 스크롤 가능성을 확인한다.

8. **`모션 감소 설정에서는 레벨업과 업적 다이얼로그가 첫 pump에 최종 상태다`**
   - transition 중간 상태가 없고 opacity/scale이 최종값인지 확인한다.

9. **`다이얼로그는 확인, back 또는 route 전환으로 닫혀도 미완료 ticker를 남기지 않는다`**
   - 애니메이션 중 pop하고 `tester.takeException()`이 null인지 확인한다.

10. **`텍스트 확대와 작은 화면에서도 축하 다이얼로그가 overflow하지 않는다`**
    - 작은 logical size와 큰 text scaler를 설정하고 render exception이 없는지 확인한다.

기존 흐름 회귀:

11. **`퀘스트 완료 성공은 스낵바 후 레벨업과 업적 다이얼로그를 순서대로 보여준다`**
12. **`didComplete가 false이면 펜딩 상태를 해제하고 성공 다이얼로그를 열지 않는다`**
13. **`완료 실패는 성공 다이얼로그를 열지 않고 재시도 가능한 상태로 돌아간다`**
14. **`홈 상단 ActionHubCard와 남은 퀘스트 목록은 동일한 완료 버튼 피드백을 사용한다`**

프레임 검증은 `pumpAndSettle()`만 쓰지 않고 `tester.pump(duration)`으로 시작/중간/끝을 나누어 실제 tween 진행을 검사한다. 전체 검증 명령은 `flutter analyze`, 관련 테스트 파일, 마지막으로 `flutter test` 순서다.

### 2.8 엣지 케이스

- **다이얼로그가 열린 상태에서 화면 전환:** `showGeneralDialog`가 소유한 route animation만 사용한다. 호출자 state를 transition listener가 참조하지 않게 하며, pop 후 각 호출자의 기존 `if (!mounted) return`을 유지한다.
- **여러 레벨업 동시 발생:** `results.entries.where((e) => e.value.leveledUp)`를 한 `LevelUpDialog`에 모은다. 각각 별도 route를 열지 않는다.
- **여러 업적 동시 발생:** 한 `AchievementDialog`에 모으고 스크롤한다.
- **레벨업과 업적 동시 발생:** 현재 계약대로 레벨업 dialog await 후 업적 dialog를 연다. 겹치는 route나 병렬 애니메이션을 만들지 않는다.
- **여러 퀘스트 동시 완료:** 기존 id별 set이 각 버튼 pending을 격리한다. 완료 결과 dialog 호출은 각 요청의 기존 흐름을 따르되, 실제 QA에서 두 dialog 체인이 겹칠 수 있음을 확인한다. 겹침이 재현되면 별도 전역 큐를 즉흥 도입하지 않고 후속 이슈로 분리한다.
- **애니메이션 중 dispose:** 모든 controller를 dispose하고 비동기 callback 뒤 `mounted`를 확인한다. controller 종료 future에 무조건 `setState`하지 않는다.
- **완료 경합:** `didComplete == false`에서 성공 체크, 레벨업, 업적 dialog를 표시하지 않는다.
- **빠른 연타:** 기존 pending set이 첫 await 전에 동기적으로 설정되고 버튼이 disable된다. 로컬 버튼도 콜백을 한 번만 전달한다.
- **긴 제목/설명, 큰 글꼴:** dialog 내용은 유연한 폭과 스크롤을 사용하고 고정 높이를 두지 않는다.
- **알 수 없는 stat id:** 현재처럼 id 문자열을 fallback 이름으로 보여준다.

### 2.9 리스크와 롤백

| 리스크 | 완화 | 롤백 |
|---|---|---|
| custom dialog가 `AlertDialog`의 접근성/키보드 동작을 빠뜨림 | route semantics, focus, barrier, back/Escape 테스트 | 공개 `show*Dialog` 함수는 유지한 채 builder만 기존 `AlertDialog`로 복원 |
| provider rebuild로 버튼 펄스가 중간에 사라짐 | 성공 체크를 버튼에 의존하지 않고 탭 즉시 짧은 펄스만 제공 | `QuestCompletionButton`을 기존 `FilledButton`으로 교체 |
| 모션 감소 설정이 플랫폼에서 전달되지 않음 | Flutter의 `MediaQuery.disableAnimations`를 단일 소스로 사용하고 6개 플랫폼 수동 QA | 모든 duration을 zero로 바꾸어 기능은 그대로 유지 |
| Web/저사양 기기 jank | scale/opacity만 사용하고 반복·blur·파티클 금지 | dialog scale 제거, fade만 유지하거나 transition 제거 |
| 여러 완료 체인의 dialog 중첩 | 기존 직렬 await와 id별 중복 가드 유지, 동시 완료 테스트 | 이번 Phase 변경만 되돌리며 데이터 로직은 영향 없음 |

롤백은 UI 계층에 한정된다. Hive schema, provider 타입, `QuestCompletionResult`, XP/업적 계산을 변경하지 않으므로 데이터 마이그레이션이나 저장소 롤백은 필요 없다.

## 3. Part B — 완료/레벨업 공유 카드 사전 조사

### 3.1 이미지 캡처

순수 Flutter로 가능하다.

1. 공유 카드 widget을 `RepaintBoundary`와 `GlobalKey`로 감싼다.
2. key의 render object를 `RenderRepaintBoundary`로 얻는다.
3. 프레임이 paint된 뒤 `toImage(pixelRatio: ...)`를 호출한다.
4. `ui.Image.toByteData(format: ui.ImageByteFormat.png)`로 PNG bytes를 얻는다.

`RenderRepaintBoundary.toImage`는 boundary가 이미 paint된 상태여야 하며 반환 이미지 크기는 logical size × pixel ratio다: [Flutter `RenderRepaintBoundary.toImage`](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html). `RepaintBoundary` 자체도 Flutter SDK widget이므로 캡처를 위해 `screenshot` 패키지가 필수는 아니다: [Flutter `RepaintBoundary`](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html).

다만 실제 구현에는 오프스크린 카드의 레이아웃/paint 완료 시점, PNG 메모리 사용량, emoji/font 렌더링 차이, Web의 브라우저 메모리와 다운로드 동작을 검증해야 한다. `screenshot` 같은 패키지는 편의 계층일 뿐 최소 기술 요건은 아니다.

### 3.2 OS 공유

Flutter SDK만으로 6개 플랫폼의 OS 공유 UI를 통일해서 호출하는 API는 없다. 현재 `pubspec.yaml`에는 `share_plus`, `screenshot`, `lottie`, `confetti`가 없다. 이미지 bytes 또는 임시 PNG를 공유하려면 일반적으로 `share_plus` 같은 플러그인이 필요하다.

2026-07-23 조사 시점의 `share_plus` 문서는 Android/iOS/macOS/Web/Windows에서 파일 공유를 지원하지만 Linux 파일 공유는 지원하지 않는다고 명시한다. Web에서는 Web Share API가 있으면 사용하고 아니면 파일 다운로드로 fallback한다. iPad는 `sharePositionOrigin`이 없으면 동작 실패나 UI 정지가 가능하며, 동적 `XFile.fromData`는 일부 플랫폼에서 임시 파일을 생성하므로 정리 정책도 필요하다: [`share_plus` 플랫폼 지원 및 제약](https://pub.dev/packages/share_plus).

Web Share API는 일부 주요 브라우저에서 동작하지 않아 Baseline이 아니고, HTTPS secure context, 사용자 activation, 플랫폼이 허용하는 유효 데이터가 필요하다. `navigator.canShare()` 확인과 fallback 설계가 필요하다: [MDN Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API).

### 3.3 플랫폼별 현실성

| 플랫폼 | 이미지 캡처 | 이미지 공유 | 현실적 검증 항목 |
|---|---|---|---|
| Android | `RepaintBoundary.toImage` 가능 | `share_plus`의 `ACTION_SEND` 계열로 가능 | 여러 Android 버전, 설치된 target app별 이미지 수신, 이미지+텍스트 조합 |
| iOS | 가능 | `UIActivityViewController` 계열로 가능 | iPhone/iPad 실기기, iPad popover origin, target app별 수신 |
| Windows | 가능 | `share_plus` 문서상 파일 지원 | 지원 Windows 버전, 설치 앱, 결과 status와 취소 |
| macOS | 가능 | native share UI 파일 지원 | 최소 OS, 권한/로컬라이제이션, target app |
| Linux | 가능 | `share_plus`에서 파일 미지원 | “OS 공유” 대신 저장/다운로드/clipboard 같은 별도 UX 결정 필요 |
| Web | 가능하나 브라우저 메모리·폰트 차이 검증 필요 | 지원 브라우저+HTTPS+user activation에서만 Web Share API; 그 외 다운로드 fallback | `canShare(files)`, Chrome/Safari/Firefox 및 모바일/데스크톱, HTTPS 배포 |

### 3.4 이번 Phase 제외 판단

**Part B는 이번 Phase 범위에서 제외하고 별도 Phase로 미룬다.**

근거:

- 새 `share_plus` 의존성과 그 transitive/native 요구사항 검토가 필요하다.
- 최신 `share_plus` 요구사항은 현재 Flutter/Dart와는 맞지만 Android Gradle Plugin, Gradle, Kotlin, Java, Apple 최소 OS 등 실제 프로젝트 설정과의 호환성 감사가 별도로 필요하다.
- Linux에는 동일한 이미지 파일 공유 기능이 없어 6개 플랫폼 공통 UX를 먼저 결정해야 한다.
- Web은 “공유”와 “다운로드 fallback”이 사용자에게 서로 다른 동작이며 HTTPS 배포와 실제 브라우저 검증이 필요하다.
- iPad popover 위치와 mobile target app별 이미지 수신은 widget test나 현재 개발 머신만으로 보증할 수 없다.
- 공유 카드에 포함할 개인정보, 사용자 이름, streak/stat 수치, 워터마크, 앱 링크와 opt-in 정책이 아직 정의되지 않았다.

별도 Phase의 진입 조건:

1. 카드 3종(레벨업/업적/스트릭)의 정보 정책과 1개 공통 aspect ratio 확정
2. Linux는 파일 저장 CTA로 대체할지, 기능 미지원으로 표시할지 제품 결정
3. Web은 native share 우선 + 다운로드 fallback 여부 확정
4. `share_plus` 버전 고정 및 6개 플랫폼 빌드 설정 감사
5. Android/iOS/iPad/macOS/Windows/Linux 실기기 또는 VM과 HTTPS Web 브라우저 매트릭스 확보
6. 생성 PNG 임시 파일 수명, 실패/취소 UX, 개인정보 노출 테스트 정의

## 4. 구현 순서와 완료 조건

1. `QuestCompletionButton`과 단위 위젯 테스트를 추가한다.
2. 퀘스트 탭, `ActionHubCard`, 대시보드 남은 퀘스트에 버튼을 연결하고 기존 흐름 테스트를 갱신한다.
3. `CelebrationDialogShell`, `LevelUpDialog`, `AchievementDialog`를 구현하고 공개 함수 호환성을 유지한다.
4. 모션 감소, semantics, 작은 화면/큰 글꼴 테스트를 추가한다.
5. `flutter analyze`와 전체 `flutter test`를 통과시킨다.
6. 6개 플랫폼 build smoke test를 수행하고 가능한 플랫폼에서 수동 애니메이션 QA를 한다.

완료 조건:

- 외부 패키지 및 애니메이션 에셋이 추가되지 않는다.
- 완료 탭 즉시 피드백이 있고 중복 완료가 발생하지 않는다.
- 레벨업/업적의 기존 텍스트와 호출 순서가 유지된다.
- `disableAnimations`에서 의미 손실 없이 모션이 제거된다.
- 기존 및 신규 테스트와 정적 분석이 통과한다.
- Part B 코드나 UI가 들어가지 않는다.

## 5. 순차 커밋 제안

1. `feat(delight): add accessible quest completion micro-interaction`
   - `QuestCompletionButton`, 세 완료 진입점 연결, 버튼 테스트
2. `feat(delight): animate level-up and achievement dialogs`
   - `CelebrationDialogShell`, 두 dialog 콘텐츠/route 전환, 디자인 토큰 적용
3. `test(delight): cover reduced motion and dialog lifecycle`
   - 프레임 단위, semantics, overflow, dispose, 기존 완료 흐름 회귀 테스트
4. `docs(delight): record share-card feasibility and deferral`
   - 실제 구현 Phase에서는 Part B 별도 이슈/Phase 링크만 추가

각 커밋은 독립적으로 `flutter analyze`와 관련 테스트를 통과시킨다. 1번은 버튼만, 2번은 공개 dialog 함수 호환성을 유지하므로 문제가 생기면 데이터 계층에 영향 없이 개별 revert할 수 있다.
