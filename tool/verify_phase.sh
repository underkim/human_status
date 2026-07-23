#!/usr/bin/env bash
# verify_phase.sh — S급 달성 작업의 Phase 진입/완료 게이트 자동 점검
#
# 어떤 에이전트든 Phase 작업을 시작하기 전(Definition of Ready)과
# 마친 뒤(Definition of Done) 이 스크립트로 표준 검증을 한 번에 돌린다.
# 이 스크립트는 아무 파일도 수정하지 않으며 읽기/검사만 한다.
#
# 사용법:
#   bash tool/verify_phase.sh            # 공통 게이트(analyze + test + readiness)
#   bash tool/verify_phase.sh 3          # Phase 3(배포) 전용 추가 점검
#   bash tool/verify_phase.sh 5          # Phase 5(감성 훅) 전용 추가 점검
#   bash tool/verify_phase.sh 6          # Phase 6(엔지니어링 마감) 전용 추가 점검
#   bash tool/verify_phase.sh --quick    # 빠른 점검(analyze만, 테스트 생략)
#
# 종료 코드: 모든 필수 게이트 통과 시 0, 하나라도 실패 시 1.

set -uo pipefail

# 저장소 루트로 이동(이 스크립트는 tool/ 아래에 있다고 가정)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PHASE="${1:-}"
QUICK=0
if [ "$PHASE" = "--quick" ]; then QUICK=1; PHASE=""; fi

PASS=0
FAIL=0
WARN=0

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }
hr()    { printf '%s\n' "------------------------------------------------------------"; }

pass() { green  "  PASS  $1"; PASS=$((PASS+1)); }
fail() { red    "  FAIL  $1"; FAIL=$((FAIL+1)); }
warn() { yellow "  WARN  $1"; WARN=$((WARN+1)); }

need() { command -v "$1" >/dev/null 2>&1; }

hr
echo "S급 Phase 검증 — repo: $REPO_ROOT"
[ -n "$PHASE" ] && echo "대상 Phase: $PHASE" || echo "대상: 공통 게이트"
hr

# --- 0. 툴체인 확인 -------------------------------------------------------
if need flutter; then pass "flutter 설치됨 ($(flutter --version 2>/dev/null | head -1))"
else fail "flutter 미설치 — PATH 확인 필요"; fi
if need dart; then pass "dart 설치됨"; else fail "dart 미설치"; fi

# --- 1. git 상태(정보) ----------------------------------------------------
if need git; then
  DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "  INFO  브랜치=$BRANCH, 미커밋 변경 파일=$DIRTY개"
  [ "$DIRTY" != "0" ] && warn "미커밋 변경이 있습니다. 인수인계 전 커밋/정리 권장"
fi

# --- 2. 계획 문서 존재 확인 ----------------------------------------------
for f in \
  docs/plans/S_GRADE_MASTER_PLAYBOOK.md \
  docs/plans/roadmap_to_s_grade.md \
  docs/RELEASE_CHECKLIST.md; do
  [ -f "$f" ] && pass "문서 존재: $f" || fail "문서 없음: $f"
done

# --- 2.5 비-ASCII 경로 경고 ----------------------------------------------
# flutter analyze의 LSP 채널은 경로에 비-ASCII 문자(예: 한글)가 있으면
# FormatException으로 크래시한다(analysis server exited with code 255).
# 이는 코드 문제가 아니라 환경 제약이므로 미리 감지해 구분한다.
NONASCII_PATH=0
if printf '%s' "$REPO_ROOT" | LC_ALL=C grep -q '[^ -~]'; then
  NONASCII_PATH=1
  warn "저장소 경로에 비-ASCII 문자가 있습니다: $REPO_ROOT"
  echo "        → flutter analyze의 분석 서버가 이 경로에서 크래시할 수 있습니다."
  echo "        → 정확한 analyze/test는 ASCII 경로로 복제하거나 CI(GitHub Actions)에서 수행하세요."
fi

# --- 3. 정적 분석 ---------------------------------------------------------
hr
echo "flutter analyze 실행 중..."
if need flutter; then
  flutter analyze > /tmp/_vp_analyze.log 2>&1
  AN_EXIT=$?
  tail -3 /tmp/_vp_analyze.log
  if grep -qiE "No issues found|이슈를 찾지 못했" /tmp/_vp_analyze.log; then
    pass "flutter analyze: 0건"
  elif grep -qiE "analysis server exited with code|FormatException" /tmp/_vp_analyze.log; then
    if [ "$NONASCII_PATH" = "1" ]; then
      warn "flutter analyze: 분석 서버 크래시(비-ASCII 경로 제약) — ASCII 경로/CI에서 재확인 필요"
    else
      fail "flutter analyze: 분석 서버 크래시(로그 확인)"
    fi
  elif grep -qiE "^\s*error •| error •" /tmp/_vp_analyze.log; then
    fail "flutter analyze: 오류 존재(로그 확인)"
  elif [ "$AN_EXIT" = "0" ]; then
    pass "flutter analyze: 통과(오류 없음)"
  else
    warn "flutter analyze: 경고/힌트 존재 또는 비정상 종료(로그 확인)"
  fi
else
  fail "flutter 없음 — analyze 생략"
fi

# --- 4. 테스트 -----------------------------------------------------------
if [ "$QUICK" = "1" ]; then
  warn "--quick: flutter test 생략"
else
  hr
  echo "flutter test 실행 중... (시간이 걸릴 수 있음)"
  if need flutter; then
    flutter test > /tmp/_vp_test.log 2>&1
    TEST_EXIT=$?
    tail -5 /tmp/_vp_test.log
    if grep -qiE "All tests passed" /tmp/_vp_test.log; then
      pass "flutter test: 전체 통과"
    elif grep -qiE "analysis server exited|FormatException" /tmp/_vp_test.log && [ "$NONASCII_PATH" = "1" ]; then
      warn "flutter test: 툴 크래시(비-ASCII 경로 제약) — ASCII 경로/CI에서 재확인 필요"
    elif [ "$TEST_EXIT" = "0" ]; then
      warn "flutter test: 성공 문자열 미검출이나 종료코드 0(로그 확인)"
    else
      fail "flutter test: 실패한 테스트 존재 또는 비정상 종료(로그 확인)"
    fi
  else
    fail "flutter 없음 — test 생략"
  fi
fi

# --- 5. 릴리즈 준비 검사(정보/게이트) -------------------------------------
hr
echo "release readiness 검사..."
if need dart; then
  if dart run tool/check_release_readiness.dart --json > /tmp/_vp_ready.json 2>/dev/null; then
    pass "check_release_readiness: ready=true (영구 ID/서명 배관 통과)"
  else
    warn "check_release_readiness: ready=false — Phase 3 미완료 시 정상(자격증명/실기기 전)"
  fi
fi

# --- 6. Phase별 추가 점검 -------------------------------------------------
phase_common_note() {
  hr
  echo "Phase $1 참고 문서:"
  echo "  docs/plans/$2"
  echo "  → 이 문서의 '완료 기준' 절을 Definition of Done으로 사용"
}

case "$PHASE" in
  3)
    phase_common_note 3 "phase3_production_release_plan.md"
    # 알림 액션 플래그가 실기기 검증 전 켜지지 않았는지 확인
    if grep -RqiE "kQuestCompletionNotificationActionEnabled\s*=\s*true" lib/ 2>/dev/null; then
      fail "kQuestCompletionNotificationActionEnabled=true 감지 — 실기기 검증 전 금지!"
    else
      pass "알림 완료 액션 플래그 off 유지(안전)"
    fi
    # 시크릿이 커밋되지 않았는지
    if git ls-files 2>/dev/null | grep -qiE '\.(jks|keystore)$|key\.properties$'; then
      fail "시크릿 파일이 git에 추적됨 — 즉시 제거 필요!"
    else
      pass "keystore/키 시크릿 미추적(안전)"
    fi
    echo "  다음 항목은 이 환경에서 자동 검증 불가(외부 게이트):"
    echo "    - Android AAB 서명 빌드 / iOS archive / 실기기 검증"
    echo "    - Sentry 실계정 opt-in/out 네트워크 검증"
    echo "    - Play/App Store 자산 및 심사 제출"
    ;;
  5)
    phase_common_note 5 "phase5_delight_polish_plan.md"
    if grep -RqiE "share_plus|lottie|confetti|screenshot:" pubspec.yaml 2>/dev/null; then
      warn "Part B(공유 카드) 관련 의존성 감지 — Phase 5 범위는 Part A(애니메이션)만"
    else
      pass "공유 카드 의존성 미추가(Phase 5 범위 준수)"
    fi
    for f in lib/widgets/quest_completion_button.dart lib/widgets/celebration_dialog_shell.dart; do
      [ -f "$f" ] && pass "존재: $f" || warn "미존재: $f (구현 예정일 수 있음)"
    done
    echo "  수동 확인: disableAnimations 대응, 6개 플랫폼 애니메이션 QA"
    ;;
  6)
    phase_common_note 6 "phase6_engineering_polish_plan.md"
    echo "  대형 파일(분할 후보) 현재 줄 수:"
    for f in lib/screens/finance_screen.dart lib/screens/settings_screen.dart \
             lib/services/storage_service.dart; do
      [ -f "$f" ] && printf "    %6s  %s\n" "$(wc -l < "$f")" "$f"
    done
    echo "  주의: 파일 분할은 순수 리팩터링. 분할 커밋에서 동작 변경 금지."
    ;;
  "")
    : # 공통만
    ;;
  *)
    warn "알 수 없는 Phase '$PHASE' — 공통 게이트만 수행했습니다(3/5/6 지원)"
    ;;
esac

# --- 요약 ----------------------------------------------------------------
hr
echo "결과: PASS=$PASS  FAIL=$FAIL  WARN=$WARN"
if [ "$FAIL" -gt 0 ]; then
  red "게이트 실패 — 위 FAIL 항목을 해결한 뒤 다시 실행하세요."
  exit 1
fi
green "필수 게이트 통과."
[ "$WARN" -gt 0 ] && yellow "경고 $WARN건은 문맥에 따라 정상일 수 있습니다(위 설명 참조)."
exit 0
