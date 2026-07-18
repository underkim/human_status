import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';
import 'package:human_status/screens/onboarding_screen.dart';
import 'package:human_status/screens/home_shell.dart';
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

  testWidgets('초기화 실패 시 복구 화면을 보여주고 자동 재시도나 민감한 에러 내용 노출 없이 한 번만 시도한다', (
    tester,
  ) async {
    var callCount = 0;
    // 파일 경로처럼 사용자에게 그대로 노출되면 안 되는 진단 정보를 흉내낸다.
    const sensitiveSentinel = '/private/var/mobile/Containers/Data/secret.hive';

    await tester.pumpWidget(
      AppBootstrap(
        createStorage: () async {
          callCount++;
          throw Exception(sensitiveSentinel);
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    // 실패 화면이 뜨고, 사용자가 재시도를 누르기 전까지 initializer는 다시
    // 호출되지 않는다 (자동 재시도 없음).
    expect(callCount, 1);
    expect(find.text('로컬 데이터를 열 수 없습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.textContaining(sensitiveSentinel), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(callCount, 1);
  });

  testWidgets(
    'pending 상태에서 dispose된 뒤 initializer가 완료돼도 startup sequence가 실행되지 않고 '
    '예외 없이 무시된다',
    (tester) async {
      final completer = Completer<StorageService>();
      var runCount = 0;

      await tester.pumpWidget(
        AppBootstrap(
          createStorage: () => completer.future,
          startupSequenceRunner: (refreshController, storage) async {
            runCount++;
          },
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // pending인 채로 AppBootstrap을 트리에서 제거해 dispose시킨다.
      await tester.pumpWidget(const SizedBox.shrink());

      // dispose 이후에 늦게 완료되는 stale future — setState-after-dispose나
      // startup sequence 실행 없이 조용히 무시되어야 한다.
      final storage = await createTestStorage();
      completer.complete(storage);
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(runCount, 0);
      expect(find.byType(OnboardingScreen), findsNothing);
    },
  );

  testWidgets('처음 실패한 뒤 재시도가 성공하면 initializer가 정확히 두 번 호출되고 메인에 도달한다', (
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
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
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
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);

    // 이후 리빌드(예: 부모 상태 변경으로 인한 재빌드)로도 중복 스케줄되지 않는다.
    await tester.pump();
    await tester.pump();
    expect(runCount, 1);
  });
}
