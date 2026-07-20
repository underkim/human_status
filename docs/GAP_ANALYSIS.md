# 소프트웨어 갭 분석 (Gap Analysis)

작성일: 2026-07-20 · 분석 대상: 저장소 전체 (`lib/` 약 15,400줄, `test/` 약 19,800줄)

## 요약

Human Status는 전반적으로 성숙한 코드베이스입니다. 테스트 코드가 소스 코드보다
많고(81개 테스트 파일), 에러 처리가 133곳에 걸쳐 촘촘하며, `lib/` 전체에
TODO/FIXME 주석이 하나도 없습니다. 보안 측면에서도 API 키의 OS 보안 저장소
보관, 서명 시크릿 gitignore 처리 등 기본기가 잘 갖춰져 있습니다.

그럼에도 아래 영역에서 뚜렷한 공백이 확인되었습니다. 우선순위는 사용자 영향과
개선 비용을 함께 고려해 매겼습니다.

| # | 항목 | 우선순위 |
|---|------|----------|
| 1 | 관측성(로깅·크래시 리포팅) 전무 | 높음 |
| 2 | 전역 에러 경계 부재 | 높음 |
| 3 | 릴리스 준비 미완 (iOS·실기기·서명 릴리스 CI) | 높음 |
| 4 | 국제화(i18n) 부재 | 높음 |
| 5 | CI 품질 게이트 공백 (커버리지·포맷·의존성 스캔) | 중간 |
| 6 | 분석기(analyzer) 설정 느슨함 | 중간 |
| 7 | 테스트 종류 편중 (golden·E2E·접근성 없음) | 중간 |
| 8 | Claude API 연동 견고성 부족 | 중간 |
| 9 | 오픈소스/협업 문서 부재 | 낮음 |
| 10 | 웹 플랫폼 키 저장 취약 | 낮음 |

---

## 우선순위 높음

### 1. 관측성(Observability) 전무

로깅 프레임워크, 크래시 리포팅(Sentry, Firebase Crashlytics 등), 사용 분석
도구가 전혀 없습니다. `lib/` 전체에서 진단 출력은 `debugPrint` 2곳
(`lib/screens/banksalad_import_screen.dart:141,171`)뿐입니다.

문제는 이 앱의 설계가 **의도적인 silent fallback**에 크게 의존한다는 점입니다:

- 알림 스케줄링 실패를 통째로 삼킴 — `lib/main.dart:287`의 `catch (_) {}`
- 일일 갱신의 3개 단계(반복 퀘스트 재생성·추천 갱신·재정 조언 갱신)가 각각
  실패를 삼킴 — `lib/services/daily_refresh_controller.dart:146,151,156`
- Claude API 호출 실패 시 조용히 로컬 규칙 엔진으로 폴백 — 사용자는 유료 AI
  기능이 동작하지 않는다는 사실 자체를 인지할 수 없음

폴백 설계 자체는 합리적이지만, 실패가 **어디에도 기록되지 않아** 현장에서
어떤 기능이 왜 죽었는지 알 방법이 없습니다.

**권고**: 최소한 로컬 링버퍼 로그(설정 화면에서 열람/내보내기 가능한 수준)
도입. `catch (_) {}` 지점마다 로그 한 줄 추가. AI 폴백 발생 시 사용자에게
비침습적 안내(스낵바/배지) 표시.

### 2. 전역 에러 경계 부재

`lib/main.dart`에 `FlutterError.onError`, `PlatformDispatcher.instance.onError`,
zone guard가 설정되어 있지 않습니다. 부트스트랩 실패는 전용 복구 화면으로
처리되지만(`lib/main.dart:106-153`), 그 이후 발생하는 잡히지 않은 위젯·비동기
에러는 어디에도 라우팅되지 않습니다.

**권고**: `main()`에서 두 핸들러를 설정하고 1번 항목의 로그 시스템에 연결.

### 3. 릴리스 준비 미완

- iOS 빌드는 한 번도 검증되지 않았고, Android도 로컬 SDK 부재로 미확인
  (`README.md:65-69`). 실기기 검증은 `docs/RELEASE_CHECKLIST.md`에 미완 게이트로
  남아 있습니다.
- CI(`.github/workflows/ci.yml`)는 Ubuntu(web + debug APK)와 Windows 스모크만
  빌드합니다. macOS/iOS/Linux 빌드 잡이 없고, APK는 debug 전용이라 서명 릴리스
  구성이 CI에서 검증되지 않습니다.
- 애플리케이션/번들 ID, 서명 구성이 placeholder 상태이며
  `tool/check_release_readiness.dart`가 이를 차단 중입니다.

**권고**: CI에 macOS 러너 기반 iOS `--no-codesign` 빌드 잡과 Linux 빌드 잡
추가. 서명 자격 증명은 GitHub secrets로 주입해 릴리스 서명 검증 잡 구성.

### 4. 국제화(i18n) 부재

`flutter_localizations`/`AppLocalizations`/l10n 설정이 전혀 없고 모든 UI
문자열이 한국어로 하드코딩되어 있습니다. 날짜/통화 포맷도 한국 기준
고정입니다. 다국어 지원이 목표가 아니라면 수용 가능하지만, 스토어 출시를
고려한다면 구조적 차단 요인입니다.

**권고**: 신규 화면부터라도 `AppLocalizations` 경유로 문자열을 추가하는 규칙
도입. 전면 마이그레이션은 별도 작업으로 분리.

---

## 우선순위 중간

### 5. CI 품질 게이트 공백

- 커버리지 측정 없음 — `flutter test --coverage` 및 리포팅/게이트 미구성.
  테스트 양은 많지만 어느 영역이 비어 있는지 수치로 알 수 없습니다.
- `dart format` 게이트 없음 — 의도적 제외(`README.md:101-104`)이지만, 전체
  일괄 포맷 + 게이트 도입을 한 번 치르면 이후 비용이 사라집니다.
- Dependabot / `dart pub outdated` / secret scanning 등 의존성·보안 자동화 없음.

**권고**: `--coverage` + Codecov(또는 아티팩트 업로드)부터 도입, Dependabot
설정 파일 추가.

### 6. 분석기 설정 느슨함

`analysis_options.yaml`이 `flutter_lints` 기본값만 포함하며 `rules:` 블록이
비어 있습니다. `strict-casts`/`strict-inference`/`strict-raw-types` 언어 모드도
미적용입니다.

**권고**: `analyzer: language:` 3종 strict 모드 활성화 후 위반 정리. 규모가
크면 `strict-raw-types`부터 단계 도입.

### 7. 테스트 종류 편중

단위/위젯 테스트는 매우 강력하지만(인메모리 Hive 하니스, DST/원자성 엣지
케이스까지 포함) 다음이 없습니다:

- golden(스크린샷) 테스트 — UI 회귀 감지 불가
- `integration_test` 기반 E2E — 실제 플랫폼 채널(알림, 보안 저장소, 파일
  선택)이 걸린 흐름은 검증되지 않음
- 접근성 테스트 — 시맨틱 라벨, 대비, 큰 글꼴 스케일 검증 없음

**권고**: 핵심 화면(대시보드, 퀘스트 목록) golden 테스트부터 도입.

### 8. Claude API 연동 견고성 부족

- 재시도/백오프/레이트리밋 처리 없음 — 일시적 네트워크 오류도 즉시 로컬
  폴백으로 빠집니다(타임아웃 20초 고정,
  `lib/services/claude_request_defaults.dart:4`).
- 모델 ID가 3개 소스에 하드코딩(`lib/services/claude_quest_suggestion_source.dart:32`,
  `claude_goal_decomposition_source.dart:30`, `claude_financial_advice_source.dart:26`)되어
  있고 설정 UI에서 변경할 수 없습니다. 모델 지원 종료 시 앱 업데이트 없이는
  대응 불가합니다.
- 사용자 입력(퀘스트 제목·설명, 목표 텍스트)이 길이 제한 없이 프롬프트에
  그대로 삽입됩니다(`claude_quest_suggestion_source.dart:48-92`). 응답 측
  검증(stat-id/난이도/XP 범위 체크)이 있어 실질 위험은 낮지만, 입력 길이
  상한은 두는 것이 안전합니다.

**권고**: 지수 백오프 1~2회 재시도, 설정 화면에 모델 선택(또는 서버 목록)
추가, 프롬프트 삽입 입력에 길이 상한.

---

## 우선순위 낮음

### 9. 오픈소스/협업 문서 부재

LICENSE, CONTRIBUTING, CHANGELOG, CODE_OF_CONDUCT, 이슈/PR 템플릿, 아키텍처
문서, dartdoc이 없습니다. README와 `docs/RELEASE_CHECKLIST.md`는 매우
충실하지만 한국어 전용입니다. 개인 프로젝트라면 LICENSE 정도만 추가해도
충분합니다.

### 10. 웹 플랫폼 키 저장 취약

웹에서는 API 키가 브라우저 저장소에 낮은 보호 수준으로 저장됩니다. README
경고와 설정 화면 경고는 이미 존재합니다(`README.md:185-187`). 백업 JSON도
평문이지만, 로컬 단일 사용자 앱 설계상 수용 가능한 트레이드오프입니다.

---

## 참고: 결함이 아닌 것으로 확인된 항목

- `claude-sonnet-5` 모델 ID — 분석 중 유효하지 않은 ID일 가능성이 제기되었으나
  확인 결과 유효한 Anthropic 모델 식별자입니다.
- silent fallback 설계 자체 — 일일 갱신·알림에서 예외를 삼키는 것은 앱
  생명주기 콜백으로 예외가 새어나가지 않게 하려는 의도적 설계입니다
  (`daily_refresh_controller.dart:134-139` 주석 참조). 문제는 설계가 아니라
  기록(로그)의 부재입니다.
