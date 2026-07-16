import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key-value secret persistence, abstracted so [StorageService] can
/// be tested without touching a platform keychain/keystore.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production [SecretStore] backed by the OS keychain/keystore via
/// flutter_secure_storage.
class FlutterSecureStorageSecretStore implements SecretStore {
  FlutterSecureStorageSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory [SecretStore] used by [StorageService.inMemory] so tests never
/// invoke a platform channel by default.
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
