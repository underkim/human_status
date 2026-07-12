import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_snapshot.dart';
import '../models/transaction.dart';
import '../providers/asset_snapshot_provider.dart';
import '../providers/finance_provider.dart';
import '../services/asset_snapshot_import_service.dart';
import '../services/banksalad_workbook_reader.dart';
import '../services/transaction_import_service.dart';

/// Imports both the transaction ledger and the asset/liability snapshot from
/// a single Banksalad .xlsx export in one action — the only supported
/// financial-data import path (see TransactionImportService.parseBanksaladLedger
/// and AssetSnapshotImportService.parse).
class BanksaladImportScreen extends ConsumerStatefulWidget {
  const BanksaladImportScreen({super.key});

  @override
  ConsumerState<BanksaladImportScreen> createState() => _BanksaladImportScreenState();
}

class _BanksaladImportScreenState extends ConsumerState<BanksaladImportScreen> {
  String? _fileName;
  String? _error;

  List<Transaction>? _newTransactions;
  int _duplicateCount = 0;
  int _excludedCount = 0;

  AssetSnapshot? _assetSnapshot;
  String? _assetError;

  bool _isImporting = false;

  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _fileName = null;
      _newTransactions = null;
      _assetSnapshot = null;
      _assetError = null;
    });

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
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
      final workbook = BanksaladWorkbook.decode(bytes);

      final ledgerRows = workbook.findSheetRowsContaining('가계부');
      if (ledgerRows == null) {
        setState(() => _error = '가계부 내역 시트를 찾을 수 없어요.');
        return;
      }
      final ledgerResult = TransactionImportService.parseBanksaladLedger(ledgerRows);
      if (!ledgerResult.isValid) {
        setState(() => _error = ledgerResult.error);
        return;
      }

      final allParsed = ledgerResult.rows!;
      final validTx = allParsed.where((r) => r.isValid).map((r) => r.transaction!).toList();
      final existing = ref.read(transactionsProvider);
      final newTx = TransactionImportService.filterDuplicates(validTx, existing);

      AssetSnapshot? snapshot;
      String? assetErr;
      final statusRows = workbook.findSheetRowsContaining('현황');
      if (statusRows == null) {
        assetErr = '자산현황 시트를 찾을 수 없어요.';
      } else {
        final snapResult = AssetSnapshotImportService.parse(statusRows);
        if (snapResult.isValid) {
          snapshot = snapResult.snapshot;
        } else {
          assetErr = snapResult.error;
        }
      }

      setState(() {
        _fileName = file.name;
        _newTransactions = newTx;
        _duplicateCount = validTx.length - newTx.length;
        _excludedCount = allParsed.length - validTx.length;
        _assetSnapshot = snapshot;
        _assetError = assetErr;
      });
    } catch (e) {
      setState(() => _error = '파일을 해석할 수 없어요: $e');
    }
  }

  Future<void> _confirmImport() async {
    final newTx = _newTransactions ?? const <Transaction>[];
    final snapshot = _assetSnapshot;

    setState(() => _isImporting = true);
    try {
      if (newTx.isNotEmpty) {
        await ref.read(transactionsProvider.notifier).importTransactions(newTx);
      }
      if (snapshot != null) {
        final today = DateTime.now();
        for (final existing in ref.read(assetSnapshotsProvider)) {
          if (_isSameDate(existing.importedAt, today)) {
            await ref.read(assetSnapshotsProvider.notifier).deleteSnapshot(existing.id);
          }
        }
        await ref.read(assetSnapshotsProvider.notifier).importSnapshot(snapshot);
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      final parts = <String>[
        if (newTx.isNotEmpty) '거래 ${newTx.length}건',
        if (snapshot != null) '자산현황 1건',
      ];
      messenger.showSnackBar(SnackBar(content: Text('${parts.join(', ')}을 가져왔어요.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('가져오기에 실패했어요: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final newTx = _newTransactions;
    final snapshot = _assetSnapshot;
    final canConfirm = !_isImporting && ((newTx?.isNotEmpty ?? false) || snapshot != null);

    return Scaffold(
      appBar: AppBar(title: const Text('뱅크샐러드 파일 가져오기')),
      body: AbsorbPointer(
        absorbing: _isImporting,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('뱅크샐러드에서 내려받은 .xlsx 파일을 선택하세요. 거래내역과 자산현황을 한 번에 가져와요.'),
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
            if (newTx != null) ...[
              const SizedBox(height: 20),
              Text('거래내역', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '신규 ${newTx.length}건 · 중복 제외 $_duplicateCount건 · 내부이체/제외 $_excludedCount건',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              ...newTx.take(20).map((tx) => _TransactionPreviewTile(transaction: tx)),
              if (newTx.length > 20)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('...그 외 ${newTx.length - 20}건', style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 20),
              Text('자산현황', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (snapshot != null)
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
                )
              else
                Text(_assetError ?? '자산현황을 인식하지 못했어요.', style: TextStyle(color: Colors.orange.shade800)),
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
                onPressed: canConfirm ? _confirmImport : null,
                child: const Text('가져오기 확정'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransactionPreviewTile extends StatelessWidget {
  final Transaction transaction;

  const _TransactionPreviewTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == TransactionType.expense;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(
          isExpense ? Icons.arrow_downward : Icons.arrow_upward,
          color: isExpense ? Colors.red : Colors.green,
        ),
        title: Text('${transaction.category} · ${transaction.date.toString().split(' ').first}'),
        subtitle: transaction.memo.isNotEmpty ? Text(transaction.memo) : null,
        trailing: Text('${isExpense ? '-' : '+'}${transaction.amount.toInt()}'),
      ),
    );
  }
}
