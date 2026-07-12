import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/finance_provider.dart';
import '../services/transaction_import_service.dart';

/// Imports transactions from a Banksalad 가계부.csv export — the only CSV
/// format this app accepts (see TransactionImportService.parseBanksaladTransactions).
class TransactionImportScreen extends ConsumerStatefulWidget {
  const TransactionImportScreen({super.key});

  @override
  ConsumerState<TransactionImportScreen> createState() => _TransactionImportScreenState();
}

class _TransactionImportScreenState extends ConsumerState<TransactionImportScreen> {
  String? _fileName;
  String? _error;
  List<ParsedImportRow>? _preview;
  bool _isImporting = false;

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _fileName = null;
      _preview = null;
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
      final result = TransactionImportService.parseBanksaladTransactions(rows);
      if (!result.isValid) {
        setState(() => _error = result.error);
        return;
      }
      setState(() {
        _fileName = file.name;
        _preview = result.rows;
      });
    } catch (e) {
      setState(() => _error = '파일을 해석할 수 없어요: $e');
    }
  }

  Future<void> _confirmImport(List<ParsedImportRow> preview) async {
    final valid = preview.where((r) => r.isValid).map((r) => r.transaction!).toList();
    if (valid.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      await ref.read(transactionsProvider.notifier).importTransactions(valid);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('${valid.length}건을 가져왔어요.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('가져오기에 실패했어요: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final validCount = preview?.where((r) => r.isValid).length ?? 0;
    final failCount = preview != null ? preview.length - validCount : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('가계부 CSV 가져오기')),
      body: AbsorbPointer(
        absorbing: _isImporting,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('뱅크샐러드에서 내보낸 가계부.csv 파일을 선택하세요. UTF-8과 EUC-KR 인코딩을 모두 자동으로 인식해요.'),
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
            if (preview != null) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('미리보기', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    failCount > 0 ? '$validCount건 인식됨 · $failCount건 제외/실패' : '$validCount건 인식됨',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...preview.take(20).map((row) => _PreviewTile(row: row)),
              if (preview.length > 20)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('...그 외 ${preview.length - 20}건', style: Theme.of(context).textTheme.bodySmall),
                ),
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
                onPressed: (validCount > 0 && !_isImporting) ? () => _confirmImport(preview) : null,
                child: Text('$validCount건 가져오기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final ParsedImportRow row;

  const _PreviewTile({required this.row});

  @override
  Widget build(BuildContext context) {
    if (!row.isValid) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.error ?? '알 수 없는 오류', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 2),
              Text(row.rawRow.join(', '), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    final tx = row.transaction!;
    final isExpense = tx.type.name == 'expense';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(
          isExpense ? Icons.arrow_downward : Icons.arrow_upward,
          color: isExpense ? Colors.red : Colors.green,
        ),
        title: Text('${tx.category} · ${tx.date.toString().split(' ').first}'),
        subtitle: tx.memo.isNotEmpty ? Text(tx.memo) : null,
        trailing: Text('${isExpense ? '-' : '+'}${tx.amount.toInt()}'),
      ),
    );
  }
}
