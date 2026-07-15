import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';
import 'package:human_status/screens/onboarding_screen.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('초기화가 진행 중일 때는 로딩 화면을 보여준다', (tester) async {
    final completer = Completer<StorageService>();

    await tester.pumpWidget(
      AppBootstrap(createStorage: () => completer.future),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Human Status'), findsOneWidget);

    // 테스트가 끝나기 전에 완료시켜 dangling future를 남기지 않는다.
    completer.complete(await createTestStorage());
    await tester.pumpAndSettle();
  });

  testWidgets('초기화 실패 시 복구 화면을 보여주고 파괴적인 저장소 동작은 호출하지 않는다', (tester) async {
    var sawDestructiveCall = false;

    await tester.pumpWidget(
      AppBootstrap(
        createStorage: () async {
          throw Exception('corrupt hive file');
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('로컬 데이터를 열 수 없습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(sawDestructiveCall, isFalse);
  });

  testWidgets('처음 실패한 뒤 재시도가 성공하면 initializer가 정확히 두 번 호출되고 온보딩에 도달한다', (
    tester,
  ) async {
    var callCount = 0;

    await tester.pumpWidget(
      AppBootstrap(
        createStorage: () async {
          callCount++;
          if (callCount == 1) {
            throw Exception('corrupt hive file');
          }
          return createTestStorage();
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(callCount, 1);
    expect(find.text('다시 시도'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(callCount, 2);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('부트스트랩 성공 시 startup sequence는 최대 한 번만 실행된다', (tester) async {
    var runCount = 0;

    await tester.pumpWidget(
      AppBootstrap(
        createStorage: () => createTestStorage(),
        startupSequenceRunner: (refreshController, storage) async {
          runCount++;
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(runCount, 1);
    expect(find.byType(OnboardingScreen), findsOneWidget);

    // 이후 리빌드(예: 부모 상태 변경으로 인한 재빌드)로도 중복 스케줄되지 않는다.
    await tester.pump();
    await tester.pump();
    expect(runCount, 1);
  });
}
