import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auto_backup_provider.dart';
import '../../services/auto_backup_controller.dart';
import '../../services/storage_service.dart' show AutoBackupFrequency;

/// 자동 백업 켜기/끄기, 폴더, 주기, 마지막 실행 상태. `AutoBackupState`가
/// `isChangingSettings`/`isBackingUp`을 이미 들고 있어 이 섹션 자체는 로컬
/// state 없이 provider만 watch한다.
class AutoBackupSettingsSection extends ConsumerWidget {
  const AutoBackupSettingsSection({super.key});

  /// Formats an instant as `2026. 7. 23. 오후 3:20`. Written by hand (rather
  /// than `DateFormat.yMd().add_jm()`) so it doesn't depend on
  /// `initializeDateFormatting('ko_KR')` having run — nothing else in this
  /// app currently does that, and adding it just for this one label isn't
  /// worth the extra global init step.
  String _formatAutoBackupTimestamp(DateTime at) {
    final local = at.toLocal();
    final isAm = local.hour < 12;
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}. ${local.month}. ${local.day}. '
        '${isAm ? '오전' : '오후'} $hour12:$minute';
  }

  /// Shortens a directory path to its last 1–2 components for the compact
  /// settings-row display (plan 3.1: "전체 경로 대신 마지막 1~2개 경로 구성요소만
  /// 화면에 표시"). The full path is only shown in the detail dialog opened
  /// from the info button.
  String _abbreviateAutoBackupPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length <= 2) return normalized;
    return '.../${parts[parts.length - 2]}/${parts.last}';
  }

  String _autoBackupToggleSubtitle(AutoBackupState state) {
    if (!state.enabled) {
      return '꺼짐 · 폴더를 선택하면 앱을 열 때 주기적으로 백업해요';
    }
    if (state.hasUnresolvedFailure) {
      return '백업 실패 · 폴더 접근을 확인해주세요';
    }
    final freqLabel = state.frequency == AutoBackupFrequency.daily
        ? '매일'
        : '매주';
    return '켜짐 · $freqLabel';
  }

  String _autoBackupLastRunSubtitle(AutoBackupState state) {
    final successText = state.lastSuccessAt == null
        ? '아직 자동 백업하지 않았어요'
        : '마지막 성공 ${_formatAutoBackupTimestamp(state.lastSuccessAt!)}';
    if (!state.hasUnresolvedFailure) return successText;
    return '$successText · 최근 시도 실패';
  }

  void _showAutoBackupSaveFailedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('설정을 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
    );
  }

  void _showAutoBackupProbeFailedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('선택한 폴더에 쓸 수 없어요. 다른 폴더를 선택해주세요.')),
    );
  }

  Future<void> _toggleAutoBackup(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    if (enable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('자동 백업'),
          content: const Text(
            '앱을 시작하거나 다시 열었을 때 선택한 주기가 지났으면 백업해요. 앱이 완전히 종료된 '
            '동안에는 실행되지 않아요. 동기화 폴더를 선택하면 해당 서비스의 정책에 따라 백업 '
            '파일이 외부로 전송될 수 있어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('폴더 선택하고 켜기'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final result = await ref
        .read(autoBackupProvider.notifier)
        .setEnabled(enable);
    if (!context.mounted) return;
    switch (result) {
      case AutoBackupActionResult.success:
        if (enable) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('자동 백업을 켰어요.')));
        }
        return;
      case AutoBackupActionResult.cancelled:
        return;
      case AutoBackupActionResult.probeFailed:
        _showAutoBackupProbeFailedSnackBar(context);
        return;
      case AutoBackupActionResult.saveFailed:
        _showAutoBackupSaveFailedSnackBar(context);
        return;
    }
  }

  Future<void> _selectAutoBackupDirectory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await ref
        .read(autoBackupProvider.notifier)
        .selectDirectory();
    if (!context.mounted) return;
    switch (result) {
      case AutoBackupActionResult.success:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('백업 폴더를 저장했어요.')));
        return;
      case AutoBackupActionResult.cancelled:
        return;
      case AutoBackupActionResult.probeFailed:
        _showAutoBackupProbeFailedSnackBar(context);
        return;
      case AutoBackupActionResult.saveFailed:
        _showAutoBackupSaveFailedSnackBar(context);
        return;
    }
  }

  Future<void> _selectAutoBackupFrequency(
    BuildContext context,
    WidgetRef ref,
    AutoBackupFrequency current,
  ) async {
    final selected = await showDialog<AutoBackupFrequency>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 주기'),
        content: RadioGroup<AutoBackupFrequency>(
          groupValue: current,
          onChanged: (v) => Navigator.pop(context, v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              RadioListTile<AutoBackupFrequency>(
                title: Text('매일'),
                value: AutoBackupFrequency.daily,
              ),
              RadioListTile<AutoBackupFrequency>(
                title: Text('매주'),
                value: AutoBackupFrequency.weekly,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
    if (selected == null || selected == current) return;

    final result = await ref
        .read(autoBackupProvider.notifier)
        .setFrequency(selected);
    if (!context.mounted) return;
    if (result == AutoBackupActionResult.saveFailed) {
      _showAutoBackupSaveFailedSnackBar(context);
    }
  }

  Future<void> _backupNow(BuildContext context, WidgetRef ref) async {
    final outcome = await ref.read(autoBackupProvider.notifier).backupNow();
    if (!context.mounted) return;
    switch (outcome) {
      case AutoBackupRunOutcome.ran:
        final failed = ref.read(autoBackupProvider).hasUnresolvedFailure;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failed ? '백업에 실패했어요. 폴더를 확인해주세요.' : '지금 백업했어요.'),
          ),
        );
        return;
      case AutoBackupRunOutcome.unsupported:
      case AutoBackupRunOutcome.disabled:
      case AutoBackupRunOutcome.noDirectory:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('자동 백업이 꺼져 있거나 폴더가 설정되지 않았어요.')),
        );
        return;
    }
  }

  Future<void> _showAutoBackupFolderDialog(BuildContext context, String path) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('백업 폴더'),
        content: SingleChildScrollView(child: SelectableText(path)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  List<Widget> _tiles(
    BuildContext context,
    WidgetRef ref,
    AutoBackupState state,
  ) {
    if (!state.isSupported) {
      return [
        SwitchListTile(
          secondary: const Icon(Icons.backup_outlined),
          title: const Text('자동 백업'),
          subtitle: const Text(
            '이 플랫폼에서는 폴더 자동 백업을 지원하지 않아요. 아래 수동 백업을 사용해주세요.',
          ),
          value: false,
          onChanged: null,
        ),
      ];
    }

    final directoryPath = state.directoryPath;
    return [
      SwitchListTile(
        secondary: const Icon(Icons.backup_outlined),
        title: const Text('자동 백업'),
        subtitle: Text(_autoBackupToggleSubtitle(state)),
        value: state.enabled,
        onChanged: state.isChangingSettings
            ? null
            : (v) => _toggleAutoBackup(context, ref, v),
      ),
      ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: const Text('백업 폴더'),
        subtitle: Text(
          directoryPath == null
              ? '선택되지 않음'
              : _abbreviateAutoBackupPath(directoryPath),
        ),
        trailing: directoryPath == null
            ? null
            : IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: '전체 경로 보기',
                onPressed: () =>
                    _showAutoBackupFolderDialog(context, directoryPath),
              ),
        enabled: !state.isChangingSettings,
        onTap: state.isChangingSettings
            ? null
            : () => _selectAutoBackupDirectory(context, ref),
      ),
      ListTile(
        leading: const Icon(Icons.event_repeat_outlined),
        title: const Text('백업 주기'),
        subtitle: Text(
          state.frequency == AutoBackupFrequency.daily ? '매일' : '매주',
        ),
        enabled: !state.isChangingSettings,
        onTap: state.isChangingSettings
            ? null
            : () => _selectAutoBackupFrequency(context, ref, state.frequency),
      ),
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('마지막 백업'),
        subtitle: Text(_autoBackupLastRunSubtitle(state)),
        trailing: state.isBackingUp
            ? const Text('백업하는 중...')
            : TextButton(
                onPressed: () => _backupNow(context, ref),
                child: const Text('지금 백업'),
              ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(autoBackupProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _tiles(context, ref, state),
    );
  }
}
