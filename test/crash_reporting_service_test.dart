import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/services/crash_reporting_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Builds a [CrashReportingService] whose SDK boundary (init/capture/close)
/// is entirely fake, so tests never touch a real Sentry transport.
CrashReportingService buildService({
  String dsn = 'https://fake@example.test/1',
  Future<void> Function(FlutterOptionsConfiguration)? sentryInit,
  Future<SentryId> Function(dynamic, {dynamic stackTrace, Hint? hint})?
  captureException,
  Future<void> Function()? sentryClose,
}) {
  return CrashReportingService(
    dsn: dsn,
    sentryInit: sentryInit ?? (_) async {},
    captureException:
        captureException ??
        (_, {stackTrace, hint}) async => SentryId.newId(),
    sentryClose: sentryClose ?? () async {},
  );
}

void main() {
  test('DSN이 비어있으면 initialize()가 SDK init을 절대 호출하지 않는다', () async {
    var initCallCount = 0;
    var captureCallCount = 0;
    final service = buildService(
      dsn: '',
      sentryInit: (_) async => initCallCount++,
      captureException: (_, {stackTrace, hint}) async {
        captureCallCount++;
        return SentryId.newId();
      },
    );

    await service.initialize();
    service.captureError(Exception('boom'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);

    expect(initCallCount, 0);
    expect(captureCallCount, 0);
  });

  test('DSN이 비어있으면 저장된 동의가 true여도 setConsent(true)가 SDK init을 호출하지 않는다', () async {
    var initCallCount = 0;
    final service = buildService(
      dsn: '',
      sentryInit: (_) async => initCallCount++,
    );

    await service.setConsent(true);

    expect(initCallCount, 0);
  });

  test('비동의(초기화 전) capture는 완전한 no-op이다', () async {
    var captureCallCount = 0;
    final service = buildService(
      captureException: (_, {stackTrace, hint}) async {
        captureCallCount++;
        return SentryId.newId();
      },
    );

    service.captureFlutterError(
      FlutterErrorDetails(exception: Exception('flutter error')),
    );
    service.captureError(Exception('zone error'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);

    expect(captureCallCount, 0);
  });

  test('동의 후 초기화는 병렬/반복 호출에도 한 번만 실행된다', () async {
    var initCallCount = 0;
    final initGate = Completer<void>();
    final service = buildService(
      sentryInit: (_) async {
        initCallCount++;
        await initGate.future;
      },
    );

    final parallelInits = [
      service.initialize(),
      service.initialize(),
      service.setConsent(true),
    ];
    initGate.complete();
    await Future.wait(parallelInits);
    // A later, sequential call must also be absorbed by the already-
    // completed cached init rather than calling the SDK again.
    await service.initialize();

    expect(initCallCount, 1);
  });

  test('끄기를 시작하면 close가 끝나기 전에도 신규 전송이 즉시 차단된다', () async {
    var captureCallCount = 0;
    var closeCallCount = 0;
    final closeGate = Completer<void>();
    final service = buildService(
      captureException: (_, {stackTrace, hint}) async {
        captureCallCount++;
        return SentryId.newId();
      },
      sentryClose: () async {
        closeCallCount++;
        await closeGate.future;
      },
    );

    await service.initialize();
    final disableFuture = service.setConsent(false);

    // Close hasn't resolved yet, but the gate must already be shut.
    service.captureError(Exception('during shutdown'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    expect(captureCallCount, 0);
    expect(closeCallCount, 1);

    closeGate.complete();
    await disableFuture;
    expect(captureCallCount, 0);
  });

  test('captureFlutterError/captureError는 동의+초기화 완료 후에만 전달된다', () async {
    var captureCallCount = 0;
    final service = buildService(
      captureException: (_, {stackTrace, hint}) async {
        captureCallCount++;
        return SentryId.newId();
      },
    );

    await service.initialize();
    service.captureFlutterError(
      FlutterErrorDetails(exception: Exception('flutter error')),
    );
    service.captureError(Exception('zone error'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);

    expect(captureCallCount, 2);
  });

  test('SDK init 실패는 다음 enable 시도에서 재시도할 수 있다', () async {
    var initCallCount = 0;
    var captureCallCount = 0;
    final service = buildService(
      sentryInit: (_) async {
        initCallCount++;
        if (initCallCount == 1) throw Exception('network unavailable');
      },
      captureException: (_, {stackTrace, hint}) async {
        captureCallCount++;
        return SentryId.newId();
      },
    );

    // The first attempt's failure now propagates (see the
    // "init 실패를 삼키지 않는다" group below) instead of being swallowed, so
    // the caller must observe it — but it must still be safe to retry right
    // after.
    await expectLater(service.initialize(), throwsException);
    service.captureError(Exception('during failed init'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    expect(captureCallCount, 0);

    await service.initialize();
    service.captureError(Exception('after retry'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);

    expect(initCallCount, 2);
    expect(captureCallCount, 1);
  });

  group('init 실패를 삼키지 않는다 (sessionInitFailed가 실제 경로에서 동작하려면 필요)', () {
    test(
      'initialize()/setConsent(true)는 init 실패를 삼키지 않고 호출자에게 그대로 전달한다',
      () async {
        final initError = Exception('SENTINEL_REAL_INIT_FAILURE');
        final service = buildService(sentryInit: (_) async => throw initError);

        // Not swallowed: the exact same error object reaches the caller,
        // proving _doEnable no longer catches-and-discards it internally.
        await expectLater(
          service.initialize(),
          throwsA(same(initError)),
        );

        // setConsent(true) goes through the same _enable() path.
        final service2 = buildService(
          sentryInit: (_) async => throw initError,
        );
        await expectLater(
          service2.setConsent(true),
          throwsA(same(initError)),
        );
      },
    );

    test('전파된 init 실패 이후에도 서비스는 안전한 no-op 상태로 남는다', () async {
      var captureCallCount = 0;
      final service = buildService(
        sentryInit: (_) async => throw Exception('boom'),
        captureException: (_, {stackTrace, hint}) async {
          captureCallCount++;
          return SentryId.newId();
        },
      );

      await expectLater(service.initialize(), throwsException);

      // A thrown init failure must never leave capture live, and must
      // never itself escape as an uncaught error from a capture call.
      expect(
        () => service.captureFlutterError(
          FlutterErrorDetails(exception: Exception('after failed init')),
        ),
        returnsNormally,
      );
      service.captureError(Exception('after failed init'), StackTrace.current);
      await Future<void>.delayed(Duration.zero);
      expect(captureCallCount, 0);
    });
  });

  test(
    'enable 진행 중에 disable이 들어오면, init이 끝난 뒤 SDK가 즉시 닫힌다',
    () async {
      var initCallCount = 0;
      var closeCallCount = 0;
      var captureCallCount = 0;
      final initGate = Completer<void>();
      final service = buildService(
        sentryInit: (_) async {
          initCallCount++;
          await initGate.future;
        },
        sentryClose: () async {
          closeCallCount++;
        },
        captureException: (_, {stackTrace, hint}) async {
          captureCallCount++;
          return SentryId.newId();
        },
      );

      final enableFuture = service.initialize();
      // The disable arrives while sentryInit is still awaiting initGate —
      // _initialized is still false at this point.
      final disableFuture = service.setConsent(false);

      // Nothing to close yet: init hasn't actually finished starting up.
      expect(closeCallCount, 0);
      service.captureError(
        Exception('during in-flight disable'),
        StackTrace.current,
      );
      await Future<void>.delayed(Duration.zero);
      expect(captureCallCount, 0);

      initGate.complete();
      await Future.wait([enableFuture, disableFuture]);

      // Init ran exactly once, and the moment it finished it noticed the
      // gate had already closed underneath it and tore the SDK back down —
      // it must never be left alive just because disable() couldn't find
      // anything to close while init was still in flight.
      expect(initCallCount, 1);
      expect(closeCallCount, 1);

      service.captureError(Exception('after teardown'), StackTrace.current);
      await Future<void>.delayed(Duration.zero);
      expect(captureCallCount, 0);
    },
  );

  test(
    'enable → disable → enable: close가 끝난 뒤에만 새 init이 시작되고 서로 겹치지 않는다',
    () async {
      final events = <String>[];
      var initCallCount = 0;
      var closeCallCount = 0;
      final firstInitGate = Completer<void>();
      final closeGate = Completer<void>();
      final service = buildService(
        sentryInit: (_) async {
          initCallCount++;
          events.add('initStart:$initCallCount');
          if (initCallCount == 1) {
            await firstInitGate.future;
          }
          events.add('initEnd:$initCallCount');
        },
        sentryClose: () async {
          closeCallCount++;
          events.add('closeStart:$closeCallCount');
          await closeGate.future;
          events.add('closeEnd:$closeCallCount');
        },
      );

      // enable: init #1 starts and blocks on firstInitGate.
      final enableFuture1 = service.initialize();
      // disable while init #1 is still in flight: it has to wait for #1 to
      // settle, at which point _doEnable notices the gate is closed and
      // tears the SDK back down itself.
      final disableFuture = service.setConsent(false);

      firstInitGate.complete();
      // Let init #1 finish and its resulting close begin, but don't let the
      // close itself complete yet — it is gated on closeGate.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(initCallCount, 1);
      expect(closeCallCount, 1);
      expect(events, contains('closeStart:1'));
      expect(events, isNot(contains('closeEnd:1')));

      // A second enable arrives while the close from the first cycle is
      // still in flight.
      final enableFuture2 = service.initialize();

      // Init #2 must NOT start yet: it has to wait for close #1 to finish
      // first, so it never races the in-flight _sentryClose() call.
      await Future<void>.delayed(Duration.zero);
      expect(initCallCount, 1);

      closeGate.complete();
      await Future.wait([enableFuture1, disableFuture]);
      await enableFuture2;

      expect(initCallCount, 2);
      expect(closeCallCount, 1);
      // Strict ordering: close #1 fully finishes before init #2 starts —
      // the two operations never overlap.
      expect(events, [
        'initStart:1',
        'initEnd:1',
        'closeStart:1',
        'closeEnd:1',
        'initStart:2',
        'initEnd:2',
      ]);
    },
  );

  test('reporter 자체(캡처 함수)가 던져도 밖으로 새어나가지 않는다', () async {
    final service = buildService(
      captureException: (_, {stackTrace, hint}) async {
        throw Exception('transport exploded');
      },
    );
    await service.initialize();

    expect(
      () => service.captureError(Exception('boom'), StackTrace.current),
      returnsNormally,
    );
  });

  group('configureOptions (보안 기본값)', () {
    test('민감한 추적 기능이 모두 꺼져 있고 redaction이 연결된다', () {
      final service = buildService(dsn: 'https://fake@example.test/1');
      final options = SentryFlutterOptions();

      service.configureOptions(options);

      expect(options.dsn, 'https://fake@example.test/1');
      expect(options.sendDefaultPii, isFalse);
      expect(options.tracesSampleRate, 0);
      // ignore: deprecated_member_use, experimental_member_use
      expect(options.profilesSampleRate, 0);
      expect(options.attachScreenshot, isFalse);
      // ignore: experimental_member_use
      expect(options.attachViewHierarchy, isFalse);
      expect(options.beforeSend, isNotNull);
    });

    test(
      '중복 보고를 막기 위해 FlutterErrorIntegration/OnErrorIntegration을 제거한다',
      () {
        final service = buildService();
        final options = SentryFlutterOptions();
        options.addIntegration(OnErrorIntegration());
        final beforeCount = options.integrations.length;
        expect(
          options.integrations.whereType<OnErrorIntegration>(),
          isNotEmpty,
        );

        service.configureOptions(options);

        expect(options.integrations.whereType<OnErrorIntegration>(), isEmpty);
        expect(options.integrations.length, beforeCount - 1);
      },
    );
  });

  group('redactSensitiveText', () {
    test('Claude API 키 형태 문자열을 제거한다', () {
      final redacted = redactSensitiveText('key=sk-ant-abc123XYZ_-9 leaked');
      expect(redacted, isNot(contains('sk-ant-abc123XYZ_-9')));
      expect(redacted, contains('[redacted-api-key]'));
    });

    test('Windows/POSIX 절대 경로를 제거한다', () {
      final windows = redactSensitiveText(
        r'failed to open C:\Users\rlaeh\human_status\secret.hive',
      );
      expect(windows, isNot(contains(r'C:\Users\rlaeh')));

      final posix = redactSensitiveText(
        'failed to open /Users/rlaeh/human_status/secret.hive',
      );
      expect(posix, isNot(contains('/Users/rlaeh')));
    });
  });

  group('redactSentryEvent', () {
    test('메시지·예외의 민감 문자열과 URL query/fragment를 제거한다', () {
      final event = SentryEvent(
        message: const SentryMessage(
          'Failed reading C:\\Users\\rlaeh\\.env with sk-ant-secretvalue',
        ),
        exceptions: [
          SentryException(
            type: 'Exception',
            value: 'token sk-ant-anothersecret leaked at /Users/rlaeh/app',
          ),
        ],
        request: SentryRequest(
          url: 'https://example.test/path?token=secret#fragment-data',
        ),
      );

      final redacted = redactSentryEvent(event, Hint());

      expect(redacted, isNotNull);
      expect(redacted!.message!.formatted, isNot(contains('sk-ant-')));
      expect(redacted.message!.formatted, isNot(contains(r'C:\Users\rlaeh')));
      expect(redacted.exceptions!.single.value, isNot(contains('sk-ant-')));
      expect(
        redacted.exceptions!.single.value,
        isNot(contains('/Users/rlaeh')),
      );
      expect(redacted.request!.url, isNot(contains('token=secret')));
      expect(redacted.request!.url, isNot(contains('fragment-data')));
      expect(redacted.request!.queryString, isEmpty);
      expect(redacted.request!.fragment, isEmpty);
    });

    test('예외 메시지에 JSON으로 섞여 들어온 sk-ant- 패턴 문자열도 걸러낸다', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FormatException',
            value:
                'backup import failed: {"claudeApiKey":"sk-ant-realkeyvalue"}',
          ),
        ],
      );

      final redacted = redactSentryEvent(event, Hint());

      expect(redacted!.exceptions!.single.value, isNot(contains('sk-ant-')));
    });

    test('exception stacktrace 프레임의 절대 경로(absPath)를 제거한다', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'Exception',
            value: 'boom',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  absPath: r'C:\Users\rlaeh\human_status\lib\main.dart',
                  fileName: 'main.dart',
                  lineNo: 10,
                ),
              ],
            ),
          ),
        ],
      );

      final redacted = redactSentryEvent(event, Hint());

      final frame = redacted!.exceptions!.single.stackTrace!.frames.single;
      expect(frame.absPath, isNot(contains(r'C:\Users\rlaeh')));
      expect(frame.absPath, contains('[redacted-path]'));
      // Non-sensitive fields are left untouched.
      expect(frame.fileName, 'main.dart');
      expect(frame.lineNo, 10);
    });

    test(
      'stack frame의 vars(로컬 변수)/fileName/module/package에 담긴 민감 문자열도 제거한다',
      () {
        final event = SentryEvent(
          exceptions: [
            SentryException(
              type: 'Exception',
              value: 'boom',
              stackTrace: SentryStackTrace(
                frames: [
                  SentryStackFrame(
                    fileName: r'C:\Users\rlaeh\human_status\lib\main.dart',
                    module: '/Users/rlaeh/human_status/lib/main.dart',
                    package: r'C:\Users\rlaeh\human_status\pkg',
                    lineNo: 10,
                    vars: {
                      'apiKey': 'sk-ant-varsleak',
                      r'C:\Users\rlaeh\secret_key_name': 'value',
                      'count': 3,
                    },
                  ),
                ],
              ),
            ),
          ],
        );

        final redacted = redactSentryEvent(event, Hint());

        final frame = redacted!.exceptions!.single.stackTrace!.frames.single;
        expect(frame.fileName, isNot(contains(r'C:\Users\rlaeh')));
        expect(frame.module, isNot(contains('/Users/rlaeh')));
        expect(frame.package, isNot(contains(r'C:\Users\rlaeh')));
        expect(frame.lineNo, 10);
        // Value redacted.
        expect(frame.vars['apiKey'], isNot(contains('sk-ant-')));
        // Key redacted too.
        expect(
          frame.vars.keys,
          isNot(contains(r'C:\Users\rlaeh\secret_key_name')),
        );
        expect(
          frame.vars.keys.any((k) => k.toString().contains('[redacted-path]')),
          isTrue,
        );
        // Non-string values pass through unchanged.
        expect(frame.vars['count'], 3);
      },
    );

    test(
      'stack frame의 function/contextLine/preContext/postContext/rawFunction/symbol에 '
      '담긴 민감 문자열도 제거한다',
      () {
        final event = SentryEvent(
          exceptions: [
            SentryException(
              type: 'Exception',
              value: 'boom',
              stackTrace: SentryStackTrace(
                frames: [
                  SentryStackFrame(
                    function: 'load(C:\\Users\\rlaeh\\human_status\\lib\\a.dart)',
                    contextLine: 'final key = "sk-ant-contextleak";',
                    rawFunction:
                        r'_Impl.load (C:\Users\rlaeh\human_status\lib\a.dart)',
                    symbol: r'_Impl$load$C:\Users\rlaeh\human_status',
                    preContext: [
                      'import "sk-ant-prekey";',
                      r'// C:\Users\rlaeh\human_status\lib\pre.dart',
                    ],
                    postContext: [
                      r'// C:\Users\rlaeh\human_status\lib\post.dart',
                      'const key = "sk-ant-postkey";',
                    ],
                    lineNo: 10,
                  ),
                ],
              ),
            ),
          ],
        );

        final redacted = redactSentryEvent(event, Hint());

        final frame = redacted!.exceptions!.single.stackTrace!.frames.single;
        expect(frame.function, isNot(contains(r'C:\Users\rlaeh')));
        expect(frame.contextLine, isNot(contains('sk-ant-')));
        expect(frame.rawFunction, isNot(contains(r'C:\Users\rlaeh')));
        expect(frame.symbol, isNot(contains(r'C:\Users\rlaeh')));
        expect(frame.preContext[0], isNot(contains('sk-ant-')));
        expect(frame.preContext[1], isNot(contains(r'C:\Users\rlaeh')));
        expect(frame.postContext[0], isNot(contains(r'C:\Users\rlaeh')));
        expect(frame.postContext[1], isNot(contains('sk-ant-')));
        expect(frame.lineNo, 10);
      },
    );

    test('thread의 stack trace(frame의 absPath 포함)도 exception과 동일하게 제거한다', () {
      final event = SentryEvent(
        threads: [
          SentryThread(
            id: 1,
            crashed: true,
            stacktrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  absPath: r'C:\Users\rlaeh\human_status\lib\background.dart',
                  lineNo: 5,
                ),
              ],
            ),
          ),
        ],
      );

      final redacted = redactSentryEvent(event, Hint());

      final frame = redacted!.threads!.single.stacktrace!.frames.single;
      expect(frame.absPath, isNot(contains(r'C:\Users\rlaeh')));
      expect(frame.absPath, contains('[redacted-path]'));
      expect(frame.lineNo, 5);
    });

    test('breadcrumb의 message/category/data에 담긴 민감 문자열을 제거한다', () {
      final event = SentryEvent(
        breadcrumbs: [
          Breadcrumb(
            message: 'opened /Users/rlaeh/secret.txt',
            category: 'sk-ant-categoryleak',
            data: {
              'path': r'C:\Users\rlaeh\human_status\secret.hive',
              'count': 3,
            },
          ),
        ],
      );

      final redacted = redactSentryEvent(event, Hint());

      final crumb = redacted!.breadcrumbs!.single;
      expect(crumb.message, isNot(contains('/Users/rlaeh')));
      expect(crumb.category, isNot(contains('sk-ant-')));
      expect(crumb.data!['path'], isNot(contains(r'C:\Users\rlaeh')));
      // Non-string values pass through unchanged.
      expect(crumb.data!['count'], 3);
    });

    test('breadcrumb data의 key 자체에 담긴 민감 문자열도 제거한다', () {
      final event = SentryEvent(
        breadcrumbs: [
          Breadcrumb(
            data: {r'C:\Users\rlaeh\human_status\secret.hive': 'value'},
          ),
        ],
      );

      final redacted = redactSentryEvent(event, Hint());

      final data = redacted!.breadcrumbs!.single.data!;
      expect(
        data.keys,
        isNot(contains(r'C:\Users\rlaeh\human_status\secret.hive')),
      );
      expect(
        data.keys.any((k) => k.contains('[redacted-path]')),
        isTrue,
      );
    });

    test('extra와 tags에 담긴 민감 문자열(중첩 맵 포함)을 제거한다', () {
      final event = SentryEvent(
        // ignore: deprecated_member_use
        extra: {
          'lastError': 'token sk-ant-extraleak used',
          'nested': {'path': '/Users/rlaeh/nested/file'},
        },
        tags: {'build': 'sk-ant-tagleak'},
      );

      final redacted = redactSentryEvent(event, Hint());

      // ignore: deprecated_member_use
      expect(redacted!.extra!['lastError'], isNot(contains('sk-ant-')));
      expect(
        // ignore: deprecated_member_use
        (redacted.extra!['nested'] as Map)['path'],
        isNot(contains('/Users/rlaeh')),
      );
      expect(redacted.tags!['build'], isNot(contains('sk-ant-')));
    });

    test('tags의 key 자체에 담긴 민감 문자열도 제거한다', () {
      final event = SentryEvent(
        tags: {r'C:\Users\rlaeh\human_status\tagkey': 'value'},
      );

      final redacted = redactSentryEvent(event, Hint());

      final tags = redacted!.tags!;
      expect(
        tags.keys,
        isNot(contains(r'C:\Users\rlaeh\human_status\tagkey')),
      );
      expect(tags.keys.any((k) => k.contains('[redacted-path]')), isTrue);
    });

    test('extra의 key 자체와 중첩 맵의 key에 담긴 민감 문자열도 제거한다', () {
      final event = SentryEvent(
        // ignore: deprecated_member_use
        extra: {
          'sk-ant-topkeyleak': 'value',
          'nested': {r'C:\Users\rlaeh\nested_key': 'value'},
        },
      );

      final redacted = redactSentryEvent(event, Hint());

      // ignore: deprecated_member_use
      final extra = redacted!.extra!;
      expect(extra.keys, isNot(contains('sk-ant-topkeyleak')));
      expect(extra.keys.any((k) => k.contains('[redacted-api-key]')), isTrue);
      final nested = extra.values.whereType<Map>().single;
      expect(nested.keys, isNot(contains(r'C:\Users\rlaeh\nested_key')));
    });

    test('contexts의 커스텀 문자열 항목은 제거하되 SDK 기본 typed 필드는 보존한다', () {
      final contexts = Contexts(device: const SentryDevice(model: 'Pixel'))
        ..['custom'] = 'leaked sk-ant-contextvalue';
      final event = SentryEvent(contexts: contexts);

      final redacted = redactSentryEvent(event, Hint());

      expect(redacted!.contexts['custom'], isNot(contains('sk-ant-')));
      expect(redacted.contexts.device?.model, 'Pixel');
    });

    test('custom contexts의 중첩 맵에 담긴 key/value 민감 문자열을 모두 제거한다', () {
      final contexts = Contexts(device: const SentryDevice(model: 'Pixel'))
        ..['custom'] = {
          r'C:\Users\rlaeh\custom_key': 'sk-ant-customvalueleak',
        };
      final event = SentryEvent(contexts: contexts);

      final redacted = redactSentryEvent(event, Hint());

      final custom = redacted!.contexts['custom'] as Map;
      expect(custom.keys, isNot(contains(r'C:\Users\rlaeh\custom_key')));
      final redactedValue = custom.values.single as String;
      expect(redactedValue, isNot(contains('sk-ant-')));
      expect(redacted.contexts.device?.model, 'Pixel');
    });

    test('request의 headers/cookies/body를 전부 제거하고 URL/method만 남긴다', () {
      final event = SentryEvent(
        request: SentryRequest(
          url: 'https://example.test/path?token=secret#frag',
          method: 'POST',
          headers: const {
            'Authorization': 'Bearer sk-ant-headerleak',
            'Cookie': 'session=abc',
          },
          cookies: 'session=abc',
          data: const {'password': 'hunter2'},
        ),
      );

      final redacted = redactSentryEvent(event, Hint());

      final request = redacted!.request!;
      expect(request.method, 'POST');
      expect(request.headers, isEmpty);
      expect(request.cookies, isNull);
      expect(request.data, isNull);
      expect(request.queryString, isEmpty);
      expect(request.fragment, isEmpty);
    });
  });
}
