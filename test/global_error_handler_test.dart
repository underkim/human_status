import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/main.dart';

import 'helpers/test_app.dart';

void main() {
  test(
    'FlutterError.onError가 오류를 reporter와 기존 handler에 각각 한 번 전달한다',
    () {
      final reporter = FakeCrashReporter();
      var previousHandlerCallCount = 0;
      final previous = FlutterError.onError;
      addTearDown(() => FlutterError.onError = previous);

      FlutterError.onError = (details) => previousHandlerCallCount++;
      installFlutterErrorReporting(reporter);

      FlutterError.reportError(
        FlutterErrorDetails(exception: Exception('boom')),
      );

      expect(reporter.flutterErrorCallCount, 1);
      expect(previousHandlerCallCount, 1);
    },
  );

  test('설치를 반복해도 새 handler가 이전 handler를 정확히 한 번만 감싼다', () {
    final reporter = FakeCrashReporter();
    var previousHandlerCallCount = 0;
    final previous = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previous);

    FlutterError.onError = (details) => previousHandlerCallCount++;
    installFlutterErrorReporting(reporter);
    installFlutterErrorReporting(reporter);

    FlutterError.reportError(
      FlutterErrorDetails(exception: Exception('boom')),
    );

    // Each install wraps whatever is currently installed, so reporting
    // fires once per install layer — this asserts the *observable*
    // contract (each layer reports once, the original handler still runs
    // exactly once) rather than assuming only one install ever happens in
    // practice (main() only calls it once).
    expect(reporter.flutterErrorCallCount, 2);
    expect(previousHandlerCallCount, 1);
  });

  test('reporter 자체가 던져도 재귀 오류 없이 기존 handler는 그대로 호출된다', () {
    final reporter = FakeCrashReporter()
      ..captureThrows = Exception('reporter exploded');
    var previousHandlerCallCount = 0;
    final previous = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previous);

    FlutterError.onError = (details) => previousHandlerCallCount++;
    installFlutterErrorReporting(reporter);

    expect(
      () => FlutterError.reportError(
        FlutterErrorDetails(exception: Exception('boom')),
      ),
      returnsNormally,
    );
    expect(reporter.flutterErrorCallCount, 1);
    expect(previousHandlerCallCount, 1);
  });

  test('zone의 처리되지 않은 Future 오류가 reporter에 한 번 전달되고 테스트가 계속 진행된다', () async {
    final reporter = FakeCrashReporter();
    final done = Completer<void>();

    runZonedGuarded(() {
      // Never awaited by the zone body on purpose — this is exactly the
      // "uncaught async error" shape runZonedGuarded's onError exists for.
      Future<void>.error(Exception('uncaught async error'));
      done.complete();
    }, zoneErrorHandler(reporter));

    await done.future;
    // Let the microtask queue actually deliver the zone error.
    await Future<void>.delayed(Duration.zero);

    expect(reporter.errorCallCount, 1);
  });

  test('zoneErrorHandler에서 reporter가 던져도 밖으로 새어나가지 않는다', () {
    final reporter = FakeCrashReporter()
      ..captureThrows = Exception('reporter exploded');

    expect(
      () => zoneErrorHandler(
        reporter,
      )(Exception('direct call'), StackTrace.current),
      returnsNormally,
    );
    expect(reporter.errorCallCount, 1);
  });
}
