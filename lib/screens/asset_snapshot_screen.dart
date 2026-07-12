import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_snapshot.dart';
import '../providers/asset_snapshot_provider.dart';
import '../services/asset_snapshot_import_service.dart';
import '../services/transaction_import_service.dart';

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
            '아직 가져온 자산 현황이 없어요.\n오른쪽 아래 + 버튼으로 현황.csv를 가져와보세요.',
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

class AssetSnapshotImportScreen extends ConsumerStatefulWidget {
  const AssetSnapshotImportScreen({super.key});

  @override
  ConsumerState<AssetSnapshotImportScreen> createState() => _AssetSnapshotImportScreenState();
}

class _AssetSnapshotImportScreenState extends ConsumerState<AssetSnapshotImportScreen> {
  String? _fileName;
  String? _error;
  AssetSnapshot? _parsedSnapshot;
  bool _isImporting = false;

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _fileName = null;
      _parsedSnapshot = null;
    });

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = '파일을 읽을 수 없어요.');
      return;
    }

    try {
      final text = decodeBytes(bytes);
      final rows = parseCsvRows(text);
      final parsed = AssetSnapshotImportService.parse(rows);
      if (!parsed.isValid) {
        setState(() => _error = parsed.error);
        return;
      }
      setState(() {
        _fileName = file.name;
        _parsedSnapshot = parsed.snapshot;
      });
    } catch (e) {
      setState(() => _error = '파일을 해석할 수 없어요: $e');
    }
  }

  Future<void> _confirmImport() async {
    final snapshot = _parsedSnapshot;
    if (snapshot == null) return;

    setState(() => _isImporting = true);
    try {
      await ref.read(assetSnapshotsProvider.notifier).importSnapshot(snapshot);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('자산 현황을 가져왔어요.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('가져오기에 실패했어요: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _parsedSnapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('자산 현황 가져오기')),
      body: AbsorbPointer(
        absorbing: _isImporting,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('뱅크샐러드에서 내보낸 현황.csv 파일을 선택하세요.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(_fileName ?? '파일 선택'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (snapshot != null) ...[
              const SizedBox(height: 20),
              Text('미리보기', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('총자산: ${snapshot.totalAssets.toInt()}'),
                      Text('총부채: ${snapshot.totalLiabilities.toInt()}'),
                      Text(
                        '순자산: ${snapshot.netWorth.toInt()}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('자산 상세', style: Theme.of(context).textTheme.titleSmall),
              ...snapshot.assetsByCategory.entries.map(
                (e) => ListTile(dense: true, title: Text(e.key), trailing: Text(e.value.toInt().toString())),
              ),
              if (snapshot.liabilitiesByCategory.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('부채 상세', style: Theme.of(context).textTheme.titleSmall),
                ...snapshot.liabilitiesByCategory.entries.map(
                  (e) => ListTile(dense: true, title: Text(e.key), trailing: Text(e.value.toInt().toString())),
                ),
              ],
              const SizedBox(height: 16),
              if (_isImporting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('가져오는 중...'),
                    ],
                  ),
                ),
              FilledButton(
                onPressed: _isImporting ? null : _confirmImport,
                child: const Text('가져오기 확정'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
