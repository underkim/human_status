// Repository-local release readiness gate.
//
// Usage:
//   dart run tool/check_release_readiness.dart          # human-readable Korean report
//   dart run tool/check_release_readiness.dart --json    # machine-readable JSON
//
// Audits the actual platform project files (not just docs/checklists) for
// placeholder application/bundle IDs and debug release signing, and exits
// non-zero while any of those remain. This does not build anything and does
// not modify any file -- it only reads the current checkout.
import 'dart:convert';
import 'dart:io';

import 'release_readiness/checker.dart';

void main(List<String> arguments) {
  final jsonMode = arguments.contains('--json');
  final report = checkReleaseReadiness(Directory.current);

  if (jsonMode) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    exit(report.isReady ? 0 : 1);
  }

  if (report.isReady) {
    stdout.writeln('release-readiness: 모바일 스토어 출시를 막는 placeholder를 찾지 못했습니다.');
    stdout.writeln(
      '(단, 실제 서명 키/디바이스 테스트/스토어 등록 등 나머지 항목은 '
      'docs/RELEASE_CHECKLIST.md 를 직접 따라 확인해야 합니다.)',
    );
    exit(0);
  }

  stdout.writeln('release-readiness: 아래 항목 때문에 아직 모바일 스토어 출시 준비가 되지 않았습니다.');
  stdout.writeln('');
  for (final issue in report.issues) {
    stdout.writeln('- [${issue.category}] ${issue.message}');
  }
  stdout.writeln('');
  stdout.writeln(
    '자세한 절차는 docs/RELEASE_CHECKLIST.md 의 "영구 ID 이전 체크리스트"와 '
    '"서명 체크리스트"를 참고하세요. Windows/Web 배포는 이 검사와 무관하게 '
    'GitHub Actions release-artifacts 워크플로로 진행할 수 있습니다.',
  );
  exit(1);
}
