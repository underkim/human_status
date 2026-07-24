# Human Status S급 기준 v2 실행 가능성 검토

> 중점: 측정 방법이 이 저장소의 실제 도구·테스트·CI로 실행 가능한가.

## 확인한 저장소 사실

- `test/accessibility/` 6개 파일과 `test/shortcuts/desktop_shortcuts_test.dart`가 있다.
- atomicity/reward/backup/import/observability/release 관련 v2가 언급한 테스트들이
  실제로 존재한다.
- `tool/check_release_readiness.dart`와 checker 단위 테스트가 존재한다.
- `.github/workflows/ci.yml`에는 analyze, 전체 test, Web release, Windows
  release가 있다.
- CI에는 Linux/macOS/iOS release build, Android signed AAB, Sentry upload,
  스토어/실기기 자동화가 없다.

## Blocker

1. **L-E4b는 저장소 명령이 아니다.** GitHub Actions 조회 도구/명령을 적지 않아
   실행할 수 없다. `gh run list --commit <SHA> --workflow CI`처럼 구체화하거나
   저장소 평가와 외부 상태 평가를 분리해야 한다.
2. **L-M3의 28개 수동 조합에는 재현 가능한 스크립트와 증적 템플릿이 없다.**
   현재 저장소에 screenshot/golden runner가 없으므로 “각 조합 스크린샷 또는
   체크 행”을 요구하고 미실행은 미통과로 해야 한다.
3. **S-E1의 6플랫폼 runner가 현재 CI에 존재하지 않는다.** 기준 자체는 유효하지만
   현재 저장소에서 실행 가능한 자동 도구처럼 쓰면 안 된다. 플랫폼별 정확한
   명령과 외부 runner 증적 허용을 최종본에 명시해야 한다.
4. **S-M2, S-M3, S-C1, S-C2는 저장소에 고정 과업 스크립트/양식이 없다.**
   존재하지 않는 테스트를 전제로 한 셈이다. 최종 기준은 이 문서 자체에 과업을
   열거하거나 release evidence 문서의 필수 표 스키마를 정의해야 한다.
5. **S-P7의 “27항목 메타데이터 검사” 자동 도구가 없다.** 현재
   `RELEASE_CHECKLIST.md`는 사람이 읽는 문서다. 수동 전수 검사로 명확히 바꾸고
   `[x]`만으로 통과하지 않는 규칙을 유지해야 한다.

## Should-fix

1. L-E3의 “명시 실행”이 파일 목록을 v2 표 안에 다시 쓰지 않아 해석이 필요하다.
   최종본에 정확한 파일을 열거한다.
2. L-P3와 L-C3도 “관련 테스트” 표현이 남아 있다. 모든 경로를 열거해야 한다.
3. S-E2 시크릿 패턴 검사는 false positive가 많다. tracked binary keystore 존재,
   `key.properties`, DSN/token literal 등 저장소에 맞는 정적 검사와 기존
   `gitignore_signing_secrets_test.dart`를 우선한다.
4. S-P2의 앱 asset “byte/hash 일치”는 Markdown을 그대로 asset으로 묶으므로
   가능하지만 공개 URL 정규화 차이를 고려해 렌더된 본문 동등성의 수동 검수를
   병행해야 한다.
5. L-E2의 직전 승인 SHA가 이 문서에 고정되지 않았다. 평가 report가 비교 SHA를
   명시하도록 해야 한다.
6. 최신 CI 성공은 문서-only 평가 커밋 자체에 아직 존재하지 않을 수 있다. 같은
   코드 tree의 기준 SHA 결과와 문서 커밋 결과를 구분해야 한다.

## Nit

1. “기준선 1,024”는 테스트 구조가 정당하게 통합될 때 영구 족쇄가 될 수 있으므로
   감소 승인 절차를 최종본에 한 줄 더 명확히 한다.
2. 외부 증적 URL에 접근 권한이 필요한 경우 검토자가 실제 열 수 있어야 한다.

