import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_snapshot.dart';
import '../services/storage_service.dart';
import 'profile_provider.dart';

final assetSnapshotsProvider = StateNotifierProvider<AssetSnapshotsNotifier, List<AssetSnapshot>>((ref) {
  return AssetSnapshotsNotifier(ref.watch(storageServiceProvider));
});

/// The most recently imported snapshot, or null if none exist yet.
final latestAssetSnapshotProvider = Provider<AssetSnapshot?>((ref) {
  final list = ref.watch(assetSnapshotsProvider);
  if (list.isEmpty) return null;
  final sorted = [...list]..sort((a, b) => b.importedAt.compareTo(a.importedAt));
  return sorted.first;
});

class AssetSnapshotsNotifier extends StateNotifier<List<AssetSnapshot>> {
  final StorageService storage;

  AssetSnapshotsNotifier(this.storage) : super(storage.getAssetSnapshots());

  void reload() => state = storage.getAssetSnapshots();

  Future<void> importSnapshot(AssetSnapshot snapshot) async {
    await storage.saveAssetSnapshot(snapshot);
    reload();
  }

  Future<void> deleteSnapshot(String id) async {
    await storage.deleteAssetSnapshot(id);
    reload();
  }
}
