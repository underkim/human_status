# Human Status

인생을 RPG처럼 관리하는 개인용 라이프 트래커입니다. 목표를 세우면 실행 가능한
퀘스트로 쪼개지고, 퀘스트를 완료할 때마다 건강·성장·재정·관계·마음 다섯 가지
스텟이 성장합니다. 뱅크샐러드 내보내기 파일을 가져와 재무 현황까지 한 앱에서
관리합니다.

## 주요 기능

- **스텟 & 레벨** — 퀘스트 완료로 XP를 얻고 스텟별 레벨이 오릅니다. 다섯 스텟의
  평균이 종합 레벨이 됩니다.
- **퀘스트** — 직접 추가하거나, 매일 갱신되는 추천 퀘스트를 채택합니다. Claude
  API 키를 설정하면 AI가 추천을 생성하고, 없으면 로컬 규칙 기반으로 동작합니다.
  '매일 반복'으로 표시한 퀘스트는 완료해도 다음 날 다시 나타납니다. 진행중인
  퀘스트는 카드 메뉴에서 수정·삭제할 수 있어요.
- **목표** — 장기 목표를 등록하면 연결된 퀘스트가 모두 끝날 때 자동 완료됩니다.
  금액 기반 재무 목표는 거래 입력으로 진도가 올라갑니다. 카드 메뉴에서
  목표를 수정·삭제할 수 있고, 삭제해도 연결된 진행중 퀘스트는 일반 퀘스트로
  남습니다.
- **재무** — 뱅크샐러드 `가계부.csv`/`.xlsx`(거래 내역)와 `현황.csv`(자산
  스냅샷)를 가져와 월별 수입·지출, 카테고리 분석, 순자산 추이를 보여줍니다.
  월 지출 예산(총액·카테고리별)을 정하면 남은 예산·초과 여부를 보여주고
  총 예산을 넘는 순간 알림을 보냅니다. 지난 3개월 지출을 바탕으로 카테고리
  예산을 자동으로 추천받을 수도 있어요. 은퇴·주택구입 장기 재무 설계 마법사와 AI 재무 코칭
  카드도 있습니다.
- **리포트 & 통계** — 주간/월간 리포트(퀘스트·스텟·목표·재무를 직전 기간과
  비교), 스트릭, 완료 기록 히트맵(잔디밭), 최근 7일 XP, 업적 목록.
- **알림 & 백업** — 매일 리마인더 알림, 일요일 저녁 주간 리포트 알림, JSON
  파일로 전체 데이터 내보내기/가져오기. Android에서는 별도 정확 알람 권한
  없이도 예약되도록 inexact 알람을 쓰므로, 설정한 시각보다 몇 분 늦게 올 수
  있어요.

## 화면 구성

600dp 미만에서는 하단 내비게이션, 이상에서는 NavigationRail을 씁니다.

| 탭 | 내용 |
| --- | --- |
| 홈 | 종합 레벨, 스텟 바, 진행중인 퀘스트/목표 요약 |
| 퀘스트 | 진행중 · 추천 · 완료 목록 |
| 목표 | 장기 목표와 진행률 |
| 재무 | 가계부 · 자산 탭, 차트, 가져오기 |
| 더보기 | 리포트 · 통계 · 설정 |

## 개발

Flutter 3.44.6(stable) / Dart 3.12.2 기준입니다.

```sh
flutter pub get
flutter test          # 단위 + 위젯 테스트
flutter analyze
flutter run           # 연결된 기기/에뮬레이터에서 실행
```

로컬 검증 명령(현재 확인된 결과):

```sh
flutter analyze              # 클린 (이슈 없음)
flutter test                 # 전체 테스트 통과
flutter build windows --release
flutter build web --release
```

Windows·Web 릴리즈 빌드는 2026-07-16에 로컬에서 검증되었습니다. Android는
로컬에 `ANDROID_HOME`/SDK가 없어 여전히 빌드를 확인하지 못했습니다(CI가
`flutter build apk --debug`로 Android 빌드 가능 여부를 대신 검증합니다).
애플리케이션/번들 ID, 서명 구성, 최종 아이콘은 아직 확정되지 않았고, 실제
배포 전 명시적으로 채워야 할 릴리즈 게이트로 남아 있습니다.

### 릴리즈 아티팩트 & 출시 준비 검사

배포 가능한 Windows/Web 아티팩트를 만드는 절차, 체크섬 검증, 백업 호환성
확인, 영구 ID/서명 이전 체크리스트, 실기기 게이트는
[docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md)에 정리되어 있습니다.
`.github/workflows/release-artifacts.yml`(`workflow_dispatch` 또는 `v*` 태그로
실행)이 Windows/Web 릴리즈 빌드를 체크섬과 함께 워크플로 아티팩트로만
업로드하며, GitHub Release 생성이나 외부 배포는 하지 않습니다.

placeholder 애플리케이션/번들 ID나 debug 릴리즈 서명이 남아 있는 동안
"모바일 스토어 출시 준비 완료"를 주장하지 않도록,
`tool/check_release_readiness.dart`가 실제 플랫폼 프로젝트 파일을 감사합니다:

```sh
dart run tool/check_release_readiness.dart          # 한글 리포트
dart run tool/check_release_readiness.dart --json    # JSON 출력
```

### CI

`.github/workflows/ci.yml`이 PR, `master` 푸시, 수동 실행(workflow_dispatch)에서
동작합니다.

- **quality (Ubuntu)** — checkout → Java 17(Temurin) → Flutter 설치 →
  `flutter pub get` → `flutter analyze` → `flutter test` →
  `flutter build web --release` → `flutter build apk --debug`.
  APK는 저장소에 릴리즈 서명 자격 증명이 없어 의도적으로 debug 빌드입니다.
- **windows-smoke (Windows)** — checkout → Flutter 설치 → `flutter pub get` →
  `flutter build windows --release`. quality 잡과 독립적으로 실행됩니다.

아티팩트 업로드나 배포 단계는 없으며 시크릿도 사용하지 않습니다. 별도의
`dart format` 게이트는 두지 않았습니다(기존 코드베이스 전체가 `dart format`
기준으로 정리되어 있지 않아, 82개 파일을 기계적으로 재포맷하는 작업은 이
변경 범위 밖입니다).

### 앱 아이콘

Android/iOS/macOS/Windows/Web 런처·파비콘 아이콘이 승인된 마스터 아트워크
(`assets/branding/human_status_icon_master.png`)로부터 `flutter_launcher_icons`
(pubspec.yaml에 버전 고정, 설정 커밋됨)로 생성되어 기본 Flutter
placeholder 아이콘을 대체했습니다. 마스터를 바꾼 뒤에는 재생성 명령
하나만 실행하면 됩니다(수동/Python 단계 없음):

```sh
dart run tool/generate_app_icons.dart
```

이 스크립트가 `flutter_launcher_icons`를 실행하고, flutter_launcher_icons
0.14.4가 iOS 프로젝트의 `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`
불리언 설정을 깨뜨리는 알려진 회귀를 복구하고(`ASSETCATALOG_COMPILER_APPICON_NAME`은
건드리지 않음), 마스터로부터 진짜 다중 크기 Windows `.ico`(16/32/48/64/128/256)를
재생성합니다. 재실행해도 항상 같은 산출물이 나오도록 결정적으로 동작하며,
프로젝트 구조가 예상과 다르면 조용히 넘어가지 않고 0이 아닌 코드로 종료합니다.
`test/app_icon_assets_test.dart`가 누락/placeholder 회귀와 iOS 설정 손상을
잡아줍니다. 이 아이콘은 시각적으로는 배포용이지만, 실제 배포 게이트는
여전히 아래의 영구 ID/서명 확정과 실기기(Android/iOS) 검증입니다.

### Android 릴리즈에 대한 참고

Android 릴리즈 빌드는 아직 debug 서명과 `com.example` 애플리케이션 ID를
그대로 사용합니다. 배포하려면 실제 패키지/번들 ID를 정하고 안전한 서명
구성(키스토어, CI 시크릿 등)을 별도로 마련해야 합니다. 이 변경에서는
애플리케이션 ID나 서명 설정을 수정하지 않았습니다.

로컬 데이터는 [hive](https://pub.dev/packages/hive)에 저장되며 서버가 없습니다.
상태 관리는 Riverpod(`StateNotifierProvider`), 차트는 fl_chart를 사용합니다.

### 코드 배치

```
lib/
  models/     Hive 모델 (Stat, Quest, Goal, Transaction, …)
  services/   순수 로직 (XP 계산, 리포트 집계, 가져오기 파서, 백업, …)
  providers/  Riverpod 프로바이더
  screens/    화면
  widgets/    공용 위젯 (QuestCard, EmptyState, …)
  theme/      디자인 토큰 (색·간격·타이포·브레이크포인트)
  data/       업적 정의, 퀘스트 템플릿 등 정적 데이터
```

### 테스트

`test/`의 위젯 테스트는 `test/helpers/test_app.dart`의 헬퍼를 사용합니다.
스토리지는 hive 인메모리 백엔드(`StorageService(inMemory: true)`)로 열어 실제
파일 IO 없이 앱과 동일한 경로를 지나갑니다.

## Claude API 키 (선택)

설정 → Claude API 키에 키를 넣으면 추천 퀘스트, 목표 분해, 재무 코칭이 Claude
로 생성됩니다. 키는 [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)를
통해 플랫폼 보안 저장소(Android Keystore, iOS/macOS Keychain, Windows DPAPI,
Linux libsecret)에만 저장되고 백업 파일에는 포함되지 않습니다.

플랫폼별 준비물:

- **Android** — minSdk 23 이상 필요(이미 기본 설정보다 낮지 않습니다).
- **Windows** — 빌드에 ATL(Visual Studio "C++를 사용한 Windows 데스크톱 개발"
  워크로드의 ATL 구성 요소)이 필요합니다.
- **Linux** — 빌드/런타임에 `libsecret`과 동작 중인 키링(gnome-keyring 등)이
  필요합니다.
- **Web** — 브라우저에 저장되는 값은 보호 수준이 낮습니다. HTTPS/로컬호스트
  환경, 신뢰할 수 있는 기기에서만 키를 입력하세요. 설정 화면에 이 경고가
  표시됩니다.
