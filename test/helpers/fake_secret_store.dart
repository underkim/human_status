import 'package:human_status/services/secret_store.dart';

/// Deterministic, in-memory [SecretStore] whose read/write/delete can each be
/// made to throw on demand, so migration/save/delete failure paths are
/// exercisable without a real platform keychain.
class FakeSecretStore implements SecretStore {
  final Map<String, String> values = {};
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw Exception('simulated read failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw Exception('simulated write failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw Exception('simulated delete failure');
    values.remove(key);
  }
}
