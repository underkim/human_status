import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/asset_snapshot_provider.dart';
import '../../providers/backup_provider.dart';
import '../../providers/finance_provider.dart';
import '../../providers/financial_planning_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/quest_provider.dart';
import '../../services/backup_service.dart';

/// 백업 내보내기/가져오기. 저장·가져오기 각각 자체 in-flight 플래그로
/// 중복 탭을 막고, 가져오기는 미리보기 → 확인 → 교체 흐름을 거친다.
class ManualBackupSettingsSection extends ConsumerStatefulWidget {
  const ManualBackupSettingsSection({
    super.key,
    this.debugPickBackupSource,
    this.debugSaveBackupFile,
  });

  /// Test-only seam replacing the platform file-picker / web paste dialog
  /// that normally supplies the raw import content: `file_selector`'s
  /// platform channel isn't available under `flutter test`. Returns the raw
  /// backup text, `''` for an explicit-but-empty selection, or `null` if
  /// the (fake) picker was cancelled. Left `null` in production, so the
  /// real picker/dialog always runs.
  @visibleForTesting
  final Future<String?> Function(BuildContext context)? debugPickBackupSource;

  /// Test-only seam replacing the "write bytes to a chosen location" step
  /// of export, for the same platform-channel reason as
  /// [debugPickBackupSource]. Left `null` in production.
  @visibleForTesting
  final Future<void> Function(String fileName, String jsonStr)?
  debugSaveBackupFile;

  @override
  ConsumerState<ManualBackupSettingsSection> createState() =>
      _ManualBackupSettingsSectionState();
}

class _ManualBackupSettingsSectionState
    extends ConsumerState<ManualBackupSettingsSection> {
  bool _exportInProgress = false;
  bool _importInProgress = false;

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    if (_exportInProgress) return;
    setState(() => _exportInProgress = true);
    try {
      final String jsonStr;
      try {
        jsonStr = ref.read(backupServiceProvider).encode();
      } catch (_) {
        if (context.mounted) _showGenericExportError(context);
        return;
      }

      if (!context.mounted) return;

      // 웹은 파일 저장 위치 선택이 불가능해 기존 복사 다이얼로그를 유지한다.
      if (kIsWeb) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('백업 내보내기'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(child: SelectableText(jsonStr)),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await Clipboard.setData(ClipboardData(text: jsonStr));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('클립보드에 복사했어요.')),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) _showGenericExportError(context);
                  }
                },
                child: const Text('복사'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
        return;
      }

      final fileName =
          'human_status_backup_${DateTime.now().toString().split(' ').first}.json';

      if (widget.debugSaveBackupFile != null) {
        try {
          await widget.debugSaveBackupFile!(fileName, jsonStr);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('백업 파일을 저장했어요.')));
          }
        } catch (_) {
          if (context.mounted) _showGenericExportError(context);
        }
        return;
      }

      final FileSaveLocation? location;
      try {
        location = await getSaveLocation(suggestedName: fileName);
      } catch (_) {
        if (context.mounted) _showGenericExportError(context);
        return;
      }
      if (location == null) return;

      try {
        final bytes = Uint8List.fromList(utf8.encode(jsonStr));
        await XFile.fromData(
          bytes,
          mimeType: 'application/json',
          name: fileName,
        ).saveTo(location.path);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('백업 파일을 저장했어요.')));
        }
      } catch (_) {
        if (context.mounted) _showGenericExportError(context);
      }
    } finally {
      if (mounted) setState(() => _exportInProgress = false);
    }
  }

  void _showGenericExportError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('백업 저장에 실패했어요. 잠시 후 다시 시도해주세요.')),
    );
  }

  /// Reloads every provider a restore can touch from storage. Each reload is
  /// best-effort: one notifier throwing (e.g. a corrupt box read) must not
  /// stop the rest from syncing, and must never swallow the caller's own
  /// failure/rollback warning — a reload failure here is silently ignored
  /// rather than rethrown.
  void _reloadBackupAffectedProviders(WidgetRef ref) {
    void safeReload(void Function() reload) {
      try {
        reload();
      } catch (_) {
        // 개별 provider 재로딩 실패가 나머지 재로딩이나 호출자가 이미
        // 보여주기로 한 실패/경고 메시지를 막아서는 안 된다.
      }
    }

    safeReload(() => ref.read(statsProvider.notifier).reload());
    safeReload(() => ref.read(questsProvider.notifier).reload());
    safeReload(() => ref.read(profileProvider.notifier).reload());
    safeReload(() => ref.read(unlockedAchievementsProvider.notifier).reload());
    safeReload(() => ref.read(goalsProvider.notifier).reload());
    safeReload(() => ref.read(transactionsProvider.notifier).reload());
    safeReload(() => ref.read(assetSnapshotsProvider.notifier).reload());
    safeReload(() => ref.read(financialPlanProvider.notifier).reload());
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    if (_importInProgress) return;
    setState(() => _importInProgress = true);
    try {
      // 소스 선택(파일 피커/웹 붙여넣기 다이얼로그/파일 읽기) 전체를 하나의
      // 경계로 감싼다 — 플랫폼 채널이나 파일 IO가 어디서 던지든 원문 예외가
      // 새어나가지 않고 일반화된 오류만 보여준다. `return`으로 끝나는 사용자
      // 취소는 예외가 아니므로 이 catch에 걸리지 않고 조용히 종료된다.
      String? jsonStr;
      try {
        if (widget.debugPickBackupSource != null) {
          jsonStr = await widget.debugPickBackupSource!(context);
        } else if (kIsWeb) {
          final controller = TextEditingController();
          jsonStr = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('백업 가져오기'),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 10,
                decoration: const InputDecoration(hintText: '백업 JSON을 붙여넣으세요'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text('가져오기'),
                ),
              ],
            ),
          );
        } else {
          const typeGroup = XTypeGroup(label: 'json', extensions: ['json']);
          final file = await openFile(acceptedTypeGroups: [typeGroup]);
          if (file == null) return;
          if (await file.length() > BackupService.maxBackupBytes) {
            throw const FormatException('Backup file is too large');
          }
          jsonStr = await file.readAsString();
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('파일을 읽을 수 없어요. 다시 시도해주세요.')),
          );
        }
        return;
      }
      // null은 사용자가 선택/붙여넣기를 취소한 것이라 조용히 끝난다. 반면
      // 빈 문자열은 "가져오기"를 눌렀지만 내용이 없는 경우라 오류를 알려야
      // 한다 — 아래 malformed 케이스와 동일하게 교체 확인 없이 종료한다.
      if (jsonStr == null) return;
      if (utf8.encode(jsonStr).length > BackupService.maxBackupBytes) {
        if (context.mounted) _showGenericImportError(context);
        return;
      }
      if (jsonStr.trim().isEmpty) {
        if (context.mounted) _showGenericImportError(context);
        return;
      }

      final backupService = ref.read(backupServiceProvider);
      final BackupPreview preview;
      try {
        preview = backupService.inspect(jsonStr);
      } catch (_) {
        if (context.mounted) _showGenericImportError(context);
        return;
      }

      // 검사를 통과한 경우에만, 요약을 포함한 최종 교체 확인을 띄운다.
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('백업 가져오기'),
          content: Text(
            '현재 모든 데이터가 아래 백업 내용으로 교체됩니다. 계속할까요?\n\n'
            '· 스텟 ${preview.statsCount}개\n'
            '· 퀘스트 ${preview.questsCount}개\n'
            '· 목표 ${preview.goalsCount}개\n'
            '· 거래 ${preview.transactionsCount}건\n'
            '· 자산 스냅샷 ${preview.assetSnapshotsCount}개\n'
            '· 업적 ${preview.achievementsCount}개\n'
            '· 재무 계획: ${preview.hasFinancialPlan ? '포함됨' : '없음'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('교체'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      try {
        await backupService.restore(jsonStr);
        _reloadBackupAffectedProviders(ref);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('가져오기가 완료됐어요.')));
        }
      } on BackupRestoreRollbackFailedException catch (_) {
        // apply와 rollback이 모두 실패해 저장소가 부분 상태일 수 있다 — 화면
        // 상태만이라도 실제 저장소와 맞추고, 문제의 심각성을 스낵바보다
        // 눈에 띄는 다이얼로그로 명확히 경고한다.
        _reloadBackupAffectedProviders(ref);
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('가져오기 실패'),
              content: const Text(
                '가져오기 도중 오류가 발생했고, 이전 상태로 되돌리는 것도 완료되지 못했어요. '
                '데이터 상태가 불완전할 수 있어요. 백업 파일로 다시 가져오기를 시도하거나 '
                '데이터를 직접 확인해주세요.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
        }
      } on BackupRestoreException catch (_) {
        // apply는 실패했지만 rollback은 성공해 기존 데이터로 돌아갔다 —
        // mutation이 시작됐던 도메인들을 화면에도 반영한 뒤 재시도를 안내한다.
        _reloadBackupAffectedProviders(ref);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('가져오기에 실패해 기존 데이터로 되돌렸어요. 다시 시도할 수 있어요.'),
            ),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('가져오기에 실패했어요. 잠시 후 다시 시도해주세요.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _importInProgress = false);
    }
  }

  void _showGenericImportError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('백업 파일 형식을 확인할 수 없어요. 다른 파일을 선택해주세요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('백업 내보내기'),
          // 확인 대화상자를 띄우는 동안까지 애니메이션이 도는 스피너를
          // 계속 보여주면 오해를 주므로(사용자 입력을 기다리는 중일 뿐
          // 실제로 바쁜 게 아니다), 정적인 텍스트/비활성화로만 진행 중임을
          // 알린다.
          subtitle: _exportInProgress ? const Text('저장하는 중...') : null,
          enabled: !_exportInProgress,
          onTap: _exportInProgress ? null : () => _exportBackup(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('백업 가져오기'),
          subtitle: _importInProgress ? const Text('가져오는 중...') : null,
          enabled: !_importInProgress,
          onTap: _importInProgress ? null : () => _importBackup(context, ref),
        ),
      ],
    );
  }
}
