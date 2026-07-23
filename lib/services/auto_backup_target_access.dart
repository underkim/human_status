import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether this platform can be trusted to write to a user-picked folder on
/// a later app launch, not just at the moment the folder is chosen.
///
/// Per `docs/plans/phase2_auto_backup_plan.md` section 2.2, `file_selector`'s
/// `getDirectoryPath()` shows a picker UI on more platforms than this — but
/// showing a picker and durably being able to write to what it returned on
/// the *next* run are different guarantees:
///  - Windows/Linux: the returned path is a normal absolute filesystem path
///    usable across runs under ordinary file permissions.
///  - Android: the installed `file_selector_android` only converts
///    `content://` URIs under the primary internal storage and never
///    requests a persistable URI permission, so a cloud-provider or
///    external-volume folder can silently stop being writable after this
///    run.
///  - iOS: `file_selector` doesn't support directory selection at all.
///  - macOS: reopening a sandboxed app needs a security-scoped bookmark
///    (resolve/start/stop around every write) that this phase does not
///    implement or validate on a signed build — shipping a path-only
///    implementation risks a silent failure on the very next launch, so
///    macOS is treated the same as the other unsupported platforms here
///    rather than as "conditionally supported". Revisit once bookmark
///    support has an actual signed-build verification pass.
///  - Web: `getDirectoryPath()` always returns `null`.
///
/// Callers that need this to be overridable in a test (e.g. to exercise the
/// "unsupported platform" UI/logic branch regardless of which OS is
/// actually running the test suite) should accept an injectable
/// `bool Function()` defaulting to `() => isAutoBackupSupportedPlatform`
/// (see [AutoBackupController] and `AutoBackupNotifier`) rather than
/// overriding this top-level getter directly.
bool get isAutoBackupSupportedPlatform {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux;
}
