import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backup_service.dart';
import 'profile_provider.dart';

/// Exposed as a provider (rather than constructed inline in
/// [SettingsScreen]) so tests can override it with an instance whose
/// `debugApplyFaultInjector`/`debugRollbackFaultInjector` are pre-wired,
/// exercising the apply/rollback-failure UI paths without reaching into
/// storage internals from the widget layer.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(storage: ref.watch(storageServiceProvider)),
);
