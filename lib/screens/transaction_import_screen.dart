import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/finance_provider.dart';
import '../services/transaction_import_service.dart';

class TransactionImportScreen extends ConsumerStatefulWidget {
  const TransactionImportScreen({super.key});

  @override
  ConsumerState<TransactionImportScreen> createState() => _TransactionImportScreenState();
}

class _TransactionImportScreenState extends ConsumerState<TransactionImportScreen> {
  String? _fileName;
  List<List<String>>? _allRows;
  String? _fileError;
  int _headerRowIndex = 0;
  final _headerRowController = TextEditingController(text: '0');
  final _dateFormatController = TextEditingController();

  int? _dateColumn;
  AmountColumnMode _amountMode = AmountColumnMode.single;
  int? _amountColumn;
  bool _positiveIsIncome = true;
  int? _incomeColumn;
  int? _expenseColumn;
  int? _memoColumn;
  int? _categoryColumn;

  bool _isImporting = false;

  @override
  void dispose() {
    _headerRowController.dispose();
    _dateFormatController.dispose();
    super.dispose();
  }

  List<String>? get _headers {
    final rows = _allRows;
    if (rows == null || _headerRowIndex < 0 || _headerRowIndex >= rows.length) return null;
    return rows[_headerRowIndex];
  }

  List<List<String>>? get _dataRows {
    final rows = _allRows;
    if (rows == null || _headerRowIndex + 1 > rows.length) return null;
    return rows.sublist(_headerRowIndex + 1);
  }

  Future<void> _pickFile() async {
    setState(() {
      _fileError = null;
      _fileName = null;
      _allRows = null;
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
      setState(() => _fileError = '파일을 읽을 수 없어요.');
      return;
    }

    try {
      final text = decodeBytes(bytes);
      final rows = parseCsvRows(text);
      if (rows.isEmpty) {
        setState(() => _fileError = '파일에 내용이 없어요.');
        return;
      }
      setState(() {
        _fileName = file.name;
        _allRows = rows;
        _headerRowIndex = 0;
        _headerRowController.text = '0';
        _dateColumn = 0;
        _amountColumn = rows.first.length > 1 ? 1 : 0;
        _incomeColumn = null;
        _expenseColumn = null;
        _memoColumn = null;
        _categoryColumn = null;
      });
    } catch (e) {
      setState(() => _fileError = '파일을 해석할 수 없어요: $e');
    }
  }

  List<ParsedImportRow> _computePreview() {
    final dataRows = _dataRows;
    if (dataRows == null) return [];
    final mapping = ImportColumnMapping(
      dateColumn: _dateColumn ?? 0,
      dateFormat: _dateFormatController.text.trim().isEmpty ? null : _dateFormatController.text.trim(),
      amountMode: _amountMode,
      amountColumn: _amountColumn,
      positiveIsIncome: _positiveIsIncome,
      incomeColumn: _incomeColumn,
      expenseColumn: _expenseColumn,
      memoColumn: _memoColumn,
      categoryColumn: _categoryColumn,
    );
    return dataRows.map((row) => TransactionImportService.mapRow(row, mapping)).toList();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('가져오기에 실패했어요: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final headers = _headers;
    final preview = _computePreview();
    final validCount = preview.where((r) => r.isValid).length;
    final failCount = preview.length - validCount;

    return Scaffold(
      appBar: AppBar(title: const Text('CSV 가져오기')),
      body: AbsorbPointer(
        absorbing: _isImporting,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('은행/카드사 앱에서 내보낸 거래내역 CSV 파일을 선택하세요. UTF-8과 EUC-KR 인코딩을 모두 자동으로 인식해요.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(_fileName ?? '파일 선택'),
            ),
            if (_fileError != null) ...[
              const SizedBox(height: 8),
              Text(_fileError!, style: const TextStyle(color: Colors.red)),
            ],
            if (headers != null) ...[
              const SizedBox(height: 20),
              Text('헤더 행 설정', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              TextField(
                controller: _headerRowController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '헤더 행 번호 (0부터 시작)',
                  helperText: '계좌 정보 등 안내 문구가 앞에 있으면 건너뛸 행 수를 늘리세요.',
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v.trim());
                  if (parsed != null && parsed >= 0 && _allRows != null && parsed < _allRows!.length) {
                    setState(() => _headerRowIndex = parsed);
                  }
                },
              ),
              const SizedBox(height: 20),
              Text('컬럼 매핑', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _ColumnDropdown(
                label: '날짜 컬럼',
                headers: headers,
                value: _dateColumn,
                onChanged: (v) => setState(() => _dateColumn = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dateFormatController,
                decoration: const InputDecoration(
                  labelText: '날짜 형식 (선택, 예: yyyy.MM.dd)',
                  helperText: '비워두면 자동으로 인식을 시도해요.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SegmentedButton<AmountColumnMode>(
                segments: const [
                  ButtonSegment(value: AmountColumnMode.single, label: Text('금액 컬럼 1개')),
                  ButtonSegment(value: AmountColumnMode.splitIncomeExpense, label: Text('입금/출금 분리')),
                ],
                selected: {_amountMode},
                onSelectionChanged: (s) => setState(() => _amountMode = s.first),
              ),
              const SizedBox(height: 8),
              if (_amountMode == AmountColumnMode.single) ...[
                _ColumnDropdown(
                  label: '금액 컬럼',
                  headers: headers,
                  value: _amountColumn,
                  onChanged: (v) => setState(() => _amountColumn = v),
                ),
                SwitchListTile(
                  title: const Text('양수(+)는 수입이에요'),
                  subtitle: const Text('꺼두면 양수를 지출로 해석해요.'),
                  value: _positiveIsIncome,
                  onChanged: (v) => setState(() => _positiveIsIncome = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ] else ...[
                _ColumnDropdown(
                  label: '입금액(수입) 컬럼',
                  headers: headers,
                  value: _incomeColumn,
                  allowNone: true,
                  onChanged: (v) => setState(() => _incomeColumn = v),
                ),
                const SizedBox(height: 8),
                _ColumnDropdown(
                  label: '출금액(지출) 컬럼',
                  headers: headers,
                  value: _expenseColumn,
                  allowNone: true,
                  onChanged: (v) => setState(() => _expenseColumn = v),
                ),
              ],
              const SizedBox(height: 8),
              _ColumnDropdown(
                label: '메모 컬럼 (선택)',
                headers: headers,
                value: _memoColumn,
                allowNone: true,
                onChanged: (v) => setState(() => _memoColumn = v),
              ),
              const SizedBox(height: 8),
              _ColumnDropdown(
                label: '카테고리 컬럼 (선택)',
                headers: headers,
                value: _categoryColumn,
                allowNone: true,
                onChanged: (v) => setState(() => _categoryColumn = v),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('미리보기', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    failCount > 0 ? '$validCount건 인식됨 · $failCount건 실패' : '$validCount건 인식됨',
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

class _ColumnDropdown extends StatelessWidget {
  final String label;
  final List<String> headers;
  final int? value;
  final bool allowNone;
  final ValueChanged<int?> onChanged;

  const _ColumnDropdown({
    required this.label,
    required this.headers,
    required this.value,
    required this.onChanged,
    this.allowNone = false,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        if (allowNone) const DropdownMenuItem<int?>(value: null, child: Text('없음')),
        ...headers.asMap().entries.map(
              (e) => DropdownMenuItem<int?>(value: e.key, child: Text('${e.key}: ${e.value}')),
            ),
      ],
      onChanged: onChanged,
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
