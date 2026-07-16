import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android 릴리즈 서명에 쓰이는 keystore/키 정보가 실수로 커밋되지 않도록
/// .gitignore가 실제로 이 파일들을 막고 있는지 검증한다. docs/RELEASE_CHECKLIST.md
/// 의 "시크릿을 안전하게 다루는 서명 체크리스트" 항목이 문서상 약속으로만
/// 남지 않고 저장소 설정으로도 강제되는지 확인하는 회귀 테스트다.
void main() {
  late String gitignore;

  setUpAll(() {
    gitignore = File('.gitignore').readAsStringSync();
  });

  test('android/key.properties를 무시한다', () {
    expect(gitignore.contains('android/key.properties'), isTrue);
  });

  test('*.jks 키스토어 파일을 무시한다', () {
    expect(gitignore.contains('*.jks'), isTrue);
  });

  test('*.keystore 파일을 무시한다', () {
    expect(gitignore.contains('*.keystore'), isTrue);
  });
}
