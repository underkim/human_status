import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/observability_provider.dart';

/// 익명 크래시 리포팅 토글. 원래 화면에서 "추천 퀘스트 새로고침" tile보다
/// 앞, "데이터 및 개인정보"([DataPrivacyTile])보다는 훨씬 앞(자동/수동 백업
/// 앞)에 있었으므로 그 위치를 그대로 유지할 수 있도록 별도 위젯으로 둔다.
class CrashReportingSettingsTile extends ConsumerWidget {
  const CrashReportingSettingsTile({super.key});

  Future<void> _toggleCrashReporting(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    if (enable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('익명 크래시 리포팅'),
          content: const Text(
            '켜면 앱이 예기치 않게 오류를 일으켰을 때 예외 종류·스택 정보와 기기·OS·앱 버전 같은 '
            '진단 정보가 Sentry(오류 수집 서비스)로 전송돼요. 퀘스트·목표·거래 등 기록한 내용이나 '
            'Claude API 키는 보내지 않아요. 언제든 다시 끌 수 있고, 자세한 내용은 설정의 '
            '"데이터 및 개인정보"에서 확인할 수 있어요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('동의하고 켜기'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final result = await ref
        .read(crashReportingConsentProvider.notifier)
        .setEnabled(enable);
    if (!context.mounted) return;
    if (result == ConsentChangeResult.saveFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crashReportingConsent = ref.watch(crashReportingConsentProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.bug_report_outlined),
      title: const Text('익명 크래시 리포팅'),
      subtitle: Text(
        !crashReportingConsent.enabled
            ? '꺼짐 · 오류 정보가 외부로 전송되지 않아요'
            : crashReportingConsent.sessionInitFailed
            ? '켜짐 · 이번 세션은 연결하지 못했어요. 다음 실행 때 다시 시도해요'
            : '켜짐 · 앱 오류와 기기·OS 정보를 Sentry로 보내요',
      ),
      value: crashReportingConsent.enabled,
      onChanged: crashReportingConsent.isChanging
          ? null
          : (v) => _toggleCrashReporting(context, ref, v),
    );
  }
}

/// "데이터 및 개인정보" 안내 다이얼로그와 전체 개인정보처리방침 보기.
/// 저장소나 provider를 바꾸지 않는 읽기 전용 정보 흐름이다.
class DataPrivacyTile extends StatelessWidget {
  const DataPrivacyTile({super.key});

  /// Read-only informational dialog — no storage or provider access, so it
  /// cannot mutate app state no matter how it's dismissed.
  Future<void> _showDataPrivacyDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('데이터 및 개인정보'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '모든 게임 데이터(스텟·퀘스트·목표·거래 등)는 계정이나 서버 동기화 없이 이 '
                '기기에만 로컬로 저장돼요.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Claude API 키는 지원되는 플랫폼에서는 보안 저장소(Android Keystore, '
                'iOS/macOS Keychain, Windows DPAPI, Linux libsecret)에 저장되고, '
                '백업 파일에는 포함되지 않아요.',
              ),
              const SizedBox(height: 12),
              const Text(
                '기기를 바꾸거나 데이터를 초기화하기 전에는 설정의 "백업 내보내기"로 먼저 '
                '내보내두는 걸 권장해요.',
              ),
              const SizedBox(height: 12),
              const Text(
                '자동 백업을 켜면 앱을 열 때 선택한 폴더에 백업 파일을 저장해요. 그 폴더가 '
                'Google Drive·OneDrive·iCloud Drive 같은 동기화 폴더라면 해당 서비스 정책에 '
                '따라 파일이 외부로 전송될 수 있어요 — 앱은 그 여부를 알거나 통제하지 않아요. '
                '자동 백업 폴더/주기 같은 기기별 설정 자체는 백업 파일에는 포함되지 않아요.',
              ),
              const SizedBox(height: 12),
              const Text(
                '웹에서는 API 키 보호 수준이 다른 플랫폼보다 낮아요. 신뢰할 수 있는 기기의 '
                'HTTPS 환경에서만 사용해주세요.',
              ),
              const SizedBox(height: 12),
              const Text(
                '익명 크래시 리포팅은 기본적으로 꺼져 있고, 설정에서 직접 켠 경우에만 오류 '
                '정보가 Sentry로 전송돼요. 자세한 처리 항목·보관 기간은 아래 버튼으로 볼 수 '
                '있어요.',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showFullPrivacyPolicy(context),
                  child: const Text('개인정보처리방침 전체 보기'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  /// Loads the bundled `docs/privacy_policy.md` asset and shows it verbatim
  /// (plain text, not markdown-rendered) in a scrollable dialog — this is
  /// the same document maintainers edit, so there is a single source of
  /// truth instead of a copy that can drift out of sync.
  Future<void> _showFullPrivacyPolicy(BuildContext context) async {
    String? text;
    try {
      text = await rootBundle.loadString('docs/privacy_policy.md');
    } catch (_) {
      // Falls through with text == null; shown as a load-failure message
      // below instead of leaking the raw asset-loading exception.
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('개인정보처리방침'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(text ?? '문서를 불러오지 못했어요. 잠시 후 다시 시도해주세요.'),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.privacy_tip_outlined),
      title: const Text('데이터 및 개인정보'),
      subtitle: const Text('기기에 저장 · API 키는 백업에서 제외'),
      onTap: () => _showDataPrivacyDialog(context),
    );
  }
}
