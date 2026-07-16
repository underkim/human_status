import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:human_status/models/user_profile.dart';
import 'package:human_status/services/secret_store.dart';
import 'package:human_status/services/storage_service.dart';

import 'helpers/fake_secret_store.dart';

Future<StorageService> _openStorage(FakeSecretStore secretStore) async {
  final storage = StorageService(inMemory: true, secretStore: secretStore);
  await storage.init();
  addTearDown(Hive.close);
  return storage;
}

void main() {
  test(
    'a fresh install with no legacy or secure key loads a null claudeApiKey',
    () async {
      final storage = await _openStorage(FakeSecretStore());
      expect(storage.claudeApiKey, isNull);
    },
  );

  test(
    'a fresh secure key (no legacy field) loads directly without touching the profile',
    () async {
      final secretStore = FakeSecretStore()
        ..values['claude_api_key'] = 'sk-secure-existing';
      final storage = await _openStorage(secretStore);

      expect(storage.claudeApiKey, 'sk-secure-existing');
      expect(storage.getProfile().claudeApiKey, isNull);
    },
  );

  test(
    'a legacy plaintext key migrates into secure storage and is scrubbed from the profile',
    () async {
      final storage = StorageService(
        inMemory: true,
        secretStore: FakeSecretStore(),
      );
      addTearDown(Hive.close);

      // init() creates the default profile; write the legacy value through
      // the normal API, then re-run init() (as a real app restart would) so
      // migration picks it up.
      await storage.init();
      final profile = storage.getProfile();
      profile.claudeApiKey = 'sk-legacy-value';
      await storage.saveProfile(profile);

      // Re-run the private migration path via a second init() call, which
      // is exactly what a real app restart does against persisted state.
      await storage.init();

      expect(storage.claudeApiKey, 'sk-legacy-value');
      expect(storage.getProfile().claudeApiKey, isNull);
      expect(
        (storage.secretStore as FakeSecretStore).values['claude_api_key'],
        'sk-legacy-value',
      );
    },
  );

  test(
    'when both a secure key and a stale legacy key exist, the secure key wins and the legacy duplicate is scrubbed',
    () async {
      final secretStore = FakeSecretStore()
        ..values['claude_api_key'] = 'sk-secure-current';
      final storage = StorageService(inMemory: true, secretStore: secretStore);
      await storage.init();
      final profile = storage.getProfile();
      profile.claudeApiKey = 'sk-stale-legacy';
      await storage.saveProfile(profile);

      await storage.init();

      expect(storage.claudeApiKey, 'sk-secure-current');
      expect(storage.getProfile().claudeApiKey, isNull);
    },
  );

  test(
    'a migration write failure preserves the legacy value, keeps the app usable, and retries on the next init',
    () async {
      final secretStore = FakeSecretStore()..failWrite = true;
      final storage = StorageService(inMemory: true, secretStore: secretStore);
      await storage.init();
      final profile = storage.getProfile();
      profile.claudeApiKey = 'sk-only-copy';
      await storage.saveProfile(profile);

      await storage.init();

      // Migration failed, but the only copy is preserved and usable.
      expect(storage.claudeApiKey, 'sk-only-copy');
      expect(storage.getProfile().claudeApiKey, 'sk-only-copy');
      expect(secretStore.values['claude_api_key'], isNull);

      // A later init (e.g. secure storage recovers) retries and succeeds.
      secretStore.failWrite = false;
      await storage.init();

      expect(storage.claudeApiKey, 'sk-only-copy');
      expect(storage.getProfile().claudeApiKey, isNull);
      expect(secretStore.values['claude_api_key'], 'sk-only-copy');
    },
  );

  test(
    'a secure-storage read failure falls back to the legacy value without erasing it, and app bootstrap still succeeds',
    () async {
      final secretStore = FakeSecretStore()..failRead = true;
      final storage = StorageService(inMemory: true, secretStore: secretStore);
      await storage.init();
      final profile = storage.getProfile();
      profile.claudeApiKey = 'sk-fallback-value';
      await storage.saveProfile(profile);

      // Re-init while reads still fail: bootstrap must not throw.
      await storage.init();

      expect(storage.claudeApiKey, 'sk-fallback-value');
      // The legacy field is left untouched so a later successful init can
      // still migrate it.
      expect(storage.getProfile().claudeApiKey, 'sk-fallback-value');

      secretStore.failRead = false;
      await storage.init();

      expect(storage.claudeApiKey, 'sk-fallback-value');
      expect(storage.getProfile().claudeApiKey, isNull);
      expect(secretStore.values['claude_api_key'], 'sk-fallback-value');
    },
  );

  test(
    'a secure-storage read failure with no legacy value leaves the key null and does not throw',
    () async {
      final secretStore = FakeSecretStore()..failRead = true;
      final storage = await _openStorage(secretStore);
      expect(storage.claudeApiKey, isNull);
    },
  );

  test('saveClaudeApiKey persists and updates the cached value', () async {
    final storage = await _openStorage(FakeSecretStore());
    await storage.saveClaudeApiKey('sk-new-value');

    expect(storage.claudeApiKey, 'sk-new-value');
    expect(
      (storage.secretStore as FakeSecretStore).values['claude_api_key'],
      'sk-new-value',
    );
  });

  test(
    'deleteClaudeApiKey removes the key and clears the cached value',
    () async {
      final secretStore = FakeSecretStore()..values['claude_api_key'] = 'sk-x';
      final storage = await _openStorage(secretStore);
      expect(storage.claudeApiKey, 'sk-x');

      await storage.deleteClaudeApiKey();

      expect(storage.claudeApiKey, isNull);
      expect(secretStore.values.containsKey('claude_api_key'), isFalse);
    },
  );

  test(
    'a save failure throws and leaves the previously effective key untouched',
    () async {
      final secretStore = FakeSecretStore()
        ..values['claude_api_key'] = 'sk-old';
      final storage = await _openStorage(secretStore);
      expect(storage.claudeApiKey, 'sk-old');

      secretStore.failWrite = true;
      await expectLater(
        storage.saveClaudeApiKey('sk-new'),
        throwsA(isA<Exception>()),
      );

      expect(storage.claudeApiKey, 'sk-old');
      expect(secretStore.values['claude_api_key'], 'sk-old');
    },
  );

  test(
    'a delete failure throws and leaves the previously effective key untouched',
    () async {
      final secretStore = FakeSecretStore()
        ..values['claude_api_key'] = 'sk-old';
      final storage = await _openStorage(secretStore);

      secretStore.failDelete = true;
      await expectLater(
        storage.deleteClaudeApiKey(),
        throwsA(isA<Exception>()),
      );

      expect(storage.claudeApiKey, 'sk-old');
      expect(secretStore.values['claude_api_key'], 'sk-old');
    },
  );

  test(
    'InMemorySecretStore never invokes a platform channel and round-trips values',
    () async {
      final store = InMemorySecretStore();
      expect(await store.read('k'), isNull);
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
    },
  );

  test(
    'StorageService(inMemory: true) defaults to InMemorySecretStore, never a platform-backed store',
    () async {
      final storage = StorageService(inMemory: true);
      expect(storage.secretStore, isA<InMemorySecretStore>());
      await storage.init();
      addTearDown(Hive.close);
      expect(storage.claudeApiKey, isNull);
    },
  );

  test('UserProfile() constructed fresh has no claudeApiKey', () {
    expect(UserProfile().claudeApiKey, isNull);
  });
}
