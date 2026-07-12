import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/asset_snapshot_provider.dart';

class AssetSnapshotListView extends ConsumerWidget {
  const AssetSnapshotListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestAssetSnapshotProvider);
    final snapshots = [...ref.watch(assetSnapshotsProvider)]
      ..sort((a, b) => b.importedAt.compareTo(a.importedAt));

    if (latest == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '아직 가져온 자산 현황이 없어요.\n오른쪽 아래 + 버튼으로 뱅크샐러드 파일을 가져와보세요.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('순자산', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(latest.netWorth.toInt().toString(), style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 4),
                Text(
                  '가져온 날짜: ${latest.importedAt.toString().split(' ').first}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('자산', style: Theme.of(context).textTheme.titleLarge),
        Card(
          child: Column(
            children: latest.assetsByCategory.entries
                .map((e) => ListTile(title: Text(e.key), trailing: Text(e.value.toInt().toString())))
                .toList(),
          ),
        ),
        if (latest.liabilitiesByCategory.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('부채', style: Theme.of(context).textTheme.titleLarge),
          Card(
            child: Column(
              children: latest.liabilitiesByCategory.entries
                  .map((e) => ListTile(title: Text(e.key), trailing: Text(e.value.toInt().toString())))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('가져온 이력', style: Theme.of(context).textTheme.titleLarge),
            Text('${snapshots.length}건'),
          ],
        ),
        ...snapshots.map((s) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text(s.importedAt.toString().split(' ').first),
                subtitle: Text('순자산 ${s.netWorth.toInt()}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref.read(assetSnapshotsProvider.notifier).deleteSnapshot(s.id),
                ),
              ),
            )),
      ],
    );
  }
}
