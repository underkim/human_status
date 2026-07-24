import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_bootstrap.dart';
import 'services/crash_reporting_service.dart';

export 'app/app_bootstrap.dart' show AppBootstrap;
export 'app/human_status_app.dart' show HumanStatusApp;
export 'app/startup_sequence.dart'
    show runStartupSequence, scheduleNotifications;

Future<void> main() async {
  final reporter = CrashReportingService();
  // Everything below runs inside one root zone so runZonedGuarded's onError
  // catches uncaught async errors outside the Flutter framework (timers,
  // Futures). It never fires for errors FlutterError.onError already
  // handles synchronously.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Consent hasn't been read from storage yet at this point (that only
    // happens once AppBootstrap opens it) — reporter starts as a safe no-op,
    // so any error here is still shown via the existing Flutter path but
    // never sent anywhere.
    installFlutterErrorReporting(reporter);
    // runApp fires immediately with a mounted bootstrap widget — storage
    // init (which can fail, e.g. a corrupt Hive file) happens behind it, so
    // a failure surfaces as a recovery screen instead of a blank pre-runApp
    // crash.
    runApp(AppBootstrap(crashReporter: reporter));
  }, zoneErrorHandler(reporter));
}

/// Installs the process-wide `FlutterError.onError` handler that forwards
/// every Flutter framework error to [reporter] (a no-op unless consent is
/// granted and the reporter has finished initializing) and then always
/// calls whatever handler was previously installed — Flutter's own
/// presentation by default — exactly once, so existing error display never
/// changes. Extracted from `main()` so it can be exercised directly in
/// `test/global_error_handler_test.dart` without a full app boot.
void installFlutterErrorReporting(CrashReporter reporter) {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    try {
      reporter.captureFlutterError(details);
    } catch (_) {
      // A reporter failure must never block/duplicate the existing Flutter
      // error presentation below, nor become an uncaught error itself.
    }
    (previousFlutterError ?? FlutterError.presentError)(details);
  };
}

/// Builds the `onError` callback for `runZonedGuarded`: forwards an
/// uncaught zone error to [reporter] (no-op gated, same as
/// [installFlutterErrorReporting]) and never rethrows, so a reporter failure
/// can't crash the zone it's meant to be protecting.
void Function(Object error, StackTrace stack) zoneErrorHandler(
  CrashReporter reporter,
) {
  return (error, stack) {
    try {
      reporter.captureError(error, stack);
    } catch (_) {
      // See installFlutterErrorReporting — never let this rethrow.
    }
  };
}
