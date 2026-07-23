import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Minimal crash-reporting abstraction so callers (main.dart's global error
/// handlers, [AppBootstrap], the settings screen) never depend on the Sentry
/// SDK directly and tests can substitute a call-counting fake instead of
/// touching a real transport.
///
/// Every implementation must treat "not yet consented" / "not yet
/// initialized" as a silent no-op for the capture methods — this is the
/// safety gate the whole feature depends on, not an optional detail.
abstract class CrashReporter {
  /// Performs (idempotent) SDK setup. Called by [AppBootstrap] once storage
  /// has confirmed consent is already `true`, and by the settings screen
  /// right after persisting a fresh opt-in.
  Future<void> initialize();

  /// Forwards a Flutter framework error. No-op unless consent is granted
  /// and [initialize] has completed successfully.
  void captureFlutterError(FlutterErrorDetails details);

  /// Forwards an uncaught zone/async error. Same no-op gate as
  /// [captureFlutterError].
  void captureError(Object error, StackTrace stackTrace);

  /// Opens (`true`) or closes (`true` -> `false`) the reporting gate. Turning
  /// it off must block new events immediately, before any async teardown
  /// (SDK close, queue flush) completes.
  Future<void> setConsent(bool enabled);

  /// Closes the underlying SDK, if initialized. Idempotent.
  Future<void> close();
}

/// Production [CrashReporter] backed by `sentry_flutter`.
///
/// Safety by construction: [dsn] defaults to the `SENTRY_DSN` compile-time
/// define (`--dart-define=SENTRY_DSN=...`), never a hardcoded value. When
/// it's empty — the default for every local run, `flutter test`, and any
/// build that didn't opt in at build time — [initialize]/[setConsent] never
/// call into the Sentry SDK at all, regardless of stored consent. The SDK
/// call itself, the capture calls, and the "is this ready" gate are all
/// separately injectable so unit tests can verify the gating/redaction logic
/// without ever touching a real transport.
class CrashReportingService implements CrashReporter {
  CrashReportingService({
    String? dsn,
    @visibleForTesting
    Future<void> Function(FlutterOptionsConfiguration optionsConfiguration)?
    sentryInit,
    @visibleForTesting
    Future<SentryId> Function(
      dynamic throwable, {
      dynamic stackTrace,
      Hint? hint,
    })?
    captureException,
    @visibleForTesting Future<void> Function()? sentryClose,
  }) : dsn = dsn ?? const String.fromEnvironment('SENTRY_DSN'),
       _sentryInit = sentryInit ?? SentryFlutter.init,
       _captureException = captureException ?? Sentry.captureException,
       _sentryClose = sentryClose ?? Sentry.close;

  final String dsn;
  final Future<void> Function(FlutterOptionsConfiguration optionsConfiguration)
  _sentryInit;
  final Future<SentryId> Function(
    dynamic throwable, {
    dynamic stackTrace,
    Hint? hint,
  })
  _captureException;
  final Future<void> Function() _sentryClose;

  // Synchronous no-op gate: false until a successful setConsent(true)/
  // initialize() call, and flipped back to false *before* any awaiting in
  // setConsent(false)/close() — closing must block new events immediately,
  // not after the SDK teardown finishes.
  bool _gateOpen = false;
  bool _initialized = false;

  // Collapses concurrent/repeated enable attempts into a single real SDK
  // init call. Cleared once that call settles (successfully with the gate
  // still open — a failed or since-reverted init must not be cached — see
  // _doEnable).
  Future<void>? _enableFuture;

  // Set for the duration of an in-flight SDK teardown (from either
  // _disable() or _doEnable()'s own post-init gate re-check), and cleared
  // once it settles. _enable() awaits this before starting a new
  // _sentryInit() call so a close and the next init are always sequenced —
  // never run concurrently — even across a fast enable/disable/enable
  // sequence.
  Future<void>? _closingFuture;

  @override
  Future<void> initialize() => _enable();

  @override
  Future<void> setConsent(bool enabled) => enabled ? _enable() : _disable();

  Future<void> _enable() {
    _gateOpen = true;
    if (dsn.isEmpty) {
      // Safe default: consent may be true (e.g. loaded from storage at
      // bootstrap) but without a DSN there is nowhere to send events, so the
      // SDK is never touched.
      return Future.value();
    }
    final existing = _enableFuture;
    if (existing != null) return existing;
    // If a previous enable/disable cycle's teardown is still in flight,
    // queue this init behind it instead of starting _sentryInit() now —
    // starting it immediately would race the in-flight _sentryClose().
    final closing = _closingFuture;
    final started = closing == null
        ? _doEnable()
        : closing.then((_) => _doEnable());
    return _enableFuture = started;
  }

  Future<void> _doEnable() async {
    try {
      await _sentryInit(_configureOptions);
    } catch (e) {
      // Allow a later enable attempt (e.g. next app launch, or the user
      // toggling the switch again) to retry instead of caching a permanent
      // failure. The failure itself is propagated (not swallowed) so the
      // caller — ObservabilityConsentNotifier.setEnabled — can actually
      // observe it and surface sessionInitFailed; every call site already
      // treats this as best-effort (main.dart's bootstrap call is
      // unawaited+catchError, the settings-screen path wraps it in
      // try/catch), so a thrown failure here never crashes the app or
      // blocks bootstrap.
      _enableFuture = null;
      rethrow;
    }
    _initialized = true;
    if (!_gateOpen) {
      // A disable() came in while this init was still in flight: _disable
      // found _initialized still false back then, so it couldn't close
      // anything and instead awaited this same future. The SDK just
      // finished starting up behind the now-closed gate — tear it back
      // down immediately instead of leaving a live SDK/native integration
      // around with no way for the caller to trigger another close().
      _initialized = false;
      _enableFuture = null;
      await _teardown();
    }
  }

  Future<void> _disable() async {
    _gateOpen = false;
    final pendingEnable = _enableFuture;
    if (pendingEnable != null && !_initialized) {
      // init is still in flight. Wait for it to settle instead of racing it:
      // if it ends up succeeding, _doEnable's own post-await check above
      // notices the gate is closed and closes the SDK itself, so there is
      // nothing left to do here. If it fails, there was never anything to
      // close.
      await pendingEnable;
      return;
    }
    _enableFuture = null;
    if (!_initialized) return;
    _initialized = false;
    await _teardown();
  }

  /// Runs `_sentryClose()`, recording it in [_closingFuture] for the
  /// duration so a concurrent [_enable] queues its `_sentryInit()` call
  /// behind this one instead of overlapping it.
  Future<void> _teardown() {
    final future = _runTeardown();
    _closingFuture = future;
    return future;
  }

  Future<void> _runTeardown() async {
    try {
      await _sentryClose();
    } catch (_) {
      // Best-effort: the gate is already closed, so no new events go out
      // regardless of whether the SDK's own teardown succeeded.
    } finally {
      _closingFuture = null;
    }
  }

  /// The same options callback passed to the injected SDK init function —
  /// exposed under a public name so `crash_reporting_service_test.dart` can
  /// verify the security-relevant configuration (redaction wiring, disabled
  /// tracing/replay/screenshot, de-duplicated integrations) against a real
  /// [SentryFlutterOptions] instance without ever calling the actual SDK
  /// init.
  @visibleForTesting
  void configureOptions(SentryFlutterOptions options) =>
      _configureOptions(options);

  void _configureOptions(SentryFlutterOptions options) {
    options.dsn = dsn;
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0;
    // ignore: experimental_member_use
    options.profilesSampleRate = 0;
    // ignore: experimental_member_use
    options.experimental.replay.sessionSampleRate = 0;
    // ignore: experimental_member_use
    options.experimental.replay.onErrorSampleRate = 0;
    options.attachScreenshot = false;
    // ignore: experimental_member_use
    options.attachViewHierarchy = false;
    options.beforeSend = redactSentryEvent;

    // main.dart installs a single manual capture path (FlutterError.onError
    // + runZonedGuarded, see installFlutterErrorReporting/zoneErrorHandler).
    // sentry_flutter's own default integrations would otherwise *also* hook
    // those exact same global handlers, double-reporting every error. There
    // is no public option to opt out of adding them up front, so they're
    // removed right after SentryFlutter.init creates them (the officially
    // documented way — see the `setAppStartEnd` deprecation note in
    // sentry_flutter's source for the same pattern). FlutterErrorIntegration
    // isn't exported by the package's public API, so it's matched by type
    // name rather than an implementation import.
    options.integrations
        .where(
          (i) =>
              i is OnErrorIntegration ||
              i.runtimeType.toString() == 'FlutterErrorIntegration',
        )
        .toList()
        .forEach(options.removeIntegration);
  }

  @override
  void captureFlutterError(FlutterErrorDetails details) {
    if (!_gateOpen || !_initialized) return;
    _safeCapture(details.exception, details.stack);
  }

  @override
  void captureError(Object error, StackTrace stackTrace) {
    if (!_gateOpen || !_initialized) return;
    _safeCapture(error, stackTrace);
  }

  void _safeCapture(Object error, StackTrace? stackTrace) {
    try {
      unawaited(_captureAndSwallow(error, stackTrace));
    } catch (_) {
      // Never let a reporter failure propagate back into a global error
      // handler — that would risk a recursive/duplicate error report.
    }
  }

  Future<void> _captureAndSwallow(Object error, StackTrace? stackTrace) async {
    try {
      await _captureException(error, stackTrace: stackTrace);
    } catch (_) {
      // Same rationale as the outer try/catch in _safeCapture — a transport
      // failure must never surface as an uncaught error of its own.
    }
  }

  @override
  Future<void> close() => _disable();
}

final _claudeApiKeyPattern = RegExp(r'sk-ant-[A-Za-z0-9_-]+');

// Matches an absolute local filesystem path so it can be redacted out of
// exception messages/formatted text before it reaches beforeSend — Windows
// drive-letter paths and POSIX home/private paths both show up in Dart stack
// traces and on-disk-path exceptions (e.g. a corrupt Hive file).
final _localPathPattern = RegExp(
  r'[A-Za-z]:[\\/][^\s]*'
  r'|(?:/(?:Users|home|private/var)/)[^\s]*',
);

/// Strips substrings that shouldn't leave the device even inside an
/// exception message: Claude API keys, and absolute local file paths.
@visibleForTesting
String redactSensitiveText(String input) {
  var result = input.replaceAll(_claudeApiKeyPattern, '[redacted-api-key]');
  result = result.replaceAll(_localPathPattern, '[redacted-path]');
  return result;
}

String? _redactUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  final uri = Uri.tryParse(url);
  if (uri == null) return redactSensitiveText(url);
  return uri.replace(query: '', fragment: '').toString();
}

/// Recursively applies [redactSensitiveText] to every [String] reachable
/// from [value] through nested [Map]s/[List]s — both keys and values —
/// leaving anything else (a typed SDK object such as [SentryDevice], a
/// number, a bool) untouched. Used for the free-form bags (breadcrumb data,
/// event extra, stack frame vars, custom contexts) where the SDK or a
/// future integration could put arbitrary strings, including as a map key.
dynamic _redactDynamic(dynamic value) {
  if (value is String) return redactSensitiveText(value);
  if (value is Map) {
    final result = <dynamic, dynamic>{};
    value.forEach((key, v) {
      final redactedKey = key is String ? redactSensitiveText(key) : key;
      result[redactedKey] = _redactDynamic(v);
    });
    return result;
  }
  if (value is List) {
    return value.map(_redactDynamic).toList();
  }
  return value;
}

/// Same redaction as [_redactDynamic], but keeps the static
/// `Map<String, dynamic>` type of a String-keyed free-form bag (breadcrumb
/// data, event extra, stack frame vars) so the result can be passed straight
/// back into the SDK API that declared it, instead of widening to
/// `Map<dynamic, dynamic>`.
Map<String, dynamic> _redactStringKeyedMap(Map<String, dynamic> map) {
  return map.map(
    (key, value) => MapEntry(redactSensitiveText(key), _redactDynamic(value)),
  );
}

/// Redacts every text field on a single stack frame: the absolute path,
/// the relative file/module/package strings, and the free-form local
/// variable dump — any of which can carry a local filesystem path or a
/// leaked secret embedded in a variable's string representation.
SentryStackFrame _redactStackFrame(SentryStackFrame frame) {
  final absPath = frame.absPath;
  final fileName = frame.fileName;
  final function = frame.function;
  final module = frame.module;
  final contextLine = frame.contextLine;
  final package = frame.package;
  final rawFunction = frame.rawFunction;
  final symbol = frame.symbol;
  final vars = frame.vars;
  final framesOmitted = frame.framesOmitted;
  final preContext = frame.preContext;
  final postContext = frame.postContext;
  return SentryStackFrame(
    absPath: absPath == null ? null : redactSensitiveText(absPath),
    fileName: fileName == null ? null : redactSensitiveText(fileName),
    function: function == null ? null : redactSensitiveText(function),
    module: module == null ? null : redactSensitiveText(module),
    lineNo: frame.lineNo,
    colNo: frame.colNo,
    contextLine: contextLine == null ? null : redactSensitiveText(contextLine),
    inApp: frame.inApp,
    package: package == null ? null : redactSensitiveText(package),
    native: frame.native,
    platform: frame.platform,
    imageAddr: frame.imageAddr,
    symbolAddr: frame.symbolAddr,
    instructionAddr: frame.instructionAddr,
    rawFunction: rawFunction == null ? null : redactSensitiveText(rawFunction),
    stackStart: frame.stackStart,
    symbol: symbol == null ? null : redactSensitiveText(symbol),
    framesOmitted: framesOmitted.isEmpty ? null : framesOmitted,
    preContext: preContext.isEmpty
        ? null
        : preContext.map(redactSensitiveText).toList(),
    postContext: postContext.isEmpty
        ? null
        : postContext.map(redactSensitiveText).toList(),
    vars: vars.isEmpty ? null : _redactStringKeyedMap(vars),
  );
}

SentryStackTrace _redactStackTrace(SentryStackTrace stackTrace) {
  final redactedFrames = stackTrace.frames.map(_redactStackFrame).toList();
  return stackTrace.copyWith(frames: redactedFrames);
}

SentryException _redactException(SentryException exception) {
  final value = exception.value;
  final stackTrace = exception.stackTrace;
  return exception.copyWith(
    value: value == null ? null : redactSensitiveText(value),
    stackTrace: stackTrace == null ? null : _redactStackTrace(stackTrace),
  );
}

/// A thread's stack trace (e.g. from an ANR/native crash report attached to
/// a background thread) carries the same frame-level risk as an exception's
/// stack trace, so it goes through the same [_redactStackFrame] logic.
SentryThread _redactThread(SentryThread thread) {
  final stacktrace = thread.stacktrace;
  if (stacktrace == null) return thread;
  return thread.copyWith(stacktrace: _redactStackTrace(stacktrace));
}

Breadcrumb _redactBreadcrumb(Breadcrumb breadcrumb) {
  final message = breadcrumb.message;
  final category = breadcrumb.category;
  final data = breadcrumb.data;
  return breadcrumb.copyWith(
    message: message == null ? null : redactSensitiveText(message),
    category: category == null ? null : redactSensitiveText(category),
    data: data == null ? null : _redactStringKeyedMap(data),
  );
}

/// Sanitizes the free-form entries of [contexts] — both the key a value is
/// stored under (a custom context name, or a key inside a nested map value)
/// and a raw [String]/[Map] value itself, either of which is how a stray
/// sensitive value (or a future integration) could smuggle data in. The
/// SDK's own typed entries (device/OS/app/browser/gpu/culture/runtime/
/// trace/response) are plain Dart objects, not [String]/[Map], so their
/// values pass through unchanged, and their key names are fixed constants
/// that never match the redaction patterns — that metadata is intentionally
/// sent and already documented in the privacy policy.
Contexts _redactContexts(Contexts contexts) {
  final redacted = contexts.clone();
  for (final key in redacted.keys.toList()) {
    final value = redacted[key];
    final redactedValue = (value is String || value is Map)
        ? _redactDynamic(value)
        : value;
    final redactedKey = redactSensitiveText(key);
    if (redactedKey != key) {
      redacted.remove(key);
    }
    redacted[redactedKey] = redactedValue;
  }
  return redacted;
}

/// Drops everything from [request] except a redacted URL/method — headers,
/// cookies, request body and env can carry arbitrary app/network data the
/// filter has no safe way to selectively scrub, so the safest rule is to
/// never forward them at all.
SentryRequest? _redactRequest(SentryRequest? request) {
  if (request == null) return null;
  return SentryRequest(
    url: _redactUrl(request.url),
    method: request.method,
    queryString: '',
    fragment: '',
  );
}

/// `beforeSend` filter: strips local absolute paths and Claude API
/// key-shaped strings from every text field the SDK could populate
/// (message, exception values, stack frame paths, breadcrumbs, contexts,
/// extra, tags), and drops the request's headers/cookies/body/query/fragment
/// entirely. Never attaches new data — only strips.
@visibleForTesting
SentryEvent? redactSentryEvent(SentryEvent event, Hint hint) {
  final message = event.message;
  final redactedMessage = message?.copyWith(
    formatted: redactSensitiveText(message.formatted),
  );

  final redactedExceptions = event.exceptions?.map(_redactException).toList();
  final redactedThreads = event.threads?.map(_redactThread).toList();
  final redactedBreadcrumbs = event.breadcrumbs
      ?.map(_redactBreadcrumb)
      .toList();
  // ignore: deprecated_member_use
  final extra = event.extra;
  final redactedExtra = extra == null ? null : _redactStringKeyedMap(extra);
  final redactedTags = event.tags?.map(
    (key, value) =>
        MapEntry(redactSensitiveText(key), redactSensitiveText(value)),
  );

  return event.copyWith(
    message: redactedMessage,
    exceptions: redactedExceptions,
    threads: redactedThreads,
    breadcrumbs: redactedBreadcrumbs,
    contexts: _redactContexts(event.contexts),
    // ignore: deprecated_member_use
    extra: redactedExtra,
    tags: redactedTags,
    request: _redactRequest(event.request),
  );
}
