import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/profile_provider.dart';
import '../../theme/app_colors.dart';

/// Claude API 키 편집. secure storage 저장/삭제 실패는 일반화된 오류만
/// 보여주고 이전 상태를 유지한다.
class ApiKeySettingsSection extends ConsumerWidget {
  const ApiKeySettingsSection({super.key});

  Future<void> _editApiKey(BuildContext context, WidgetRef ref) async {
    final storage = ref.read(storageServiceProvider);
    final controller = TextEditingController(text: storage.claudeApiKey ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Claude API 키'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('설정하면 추천 퀘스트가 Claude AI로 생성돼요. 비워두면 로컬 규칙 기반으로 동작합니다.'),
            if (kIsWeb) ...[
              const SizedBox(height: 8),
              Text(
                '웹에서는 브라우저에 저장된 API 키의 보호 수준이 낮아요. 신뢰할 수 있는 기기의 HTTPS 환경에서만 입력해주세요.',
                style: TextStyle(color: context.appColors.warning),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'sk-ant-...'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('키 삭제'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result == null) return;

    try {
      if (result.isEmpty) {
        await storage.deleteClaudeApiKey();
      } else {
        await storage.saveClaudeApiKey(result);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API 키를 저장하지 못했어요. 잠시 후 다시 시도해주세요.')),
        );
      }
      return;
    }
    ref.read(profileProvider.notifier).reload();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isEmpty ? 'API 키를 삭제했어요.' : 'API 키를 저장했어요.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // apiKeySet은 secure storage 값이라 profileProvider 자체를 쓰지 않지만,
    // 원래 화면에서는 이 위젯이 profileProvider를 watch하는 형제와 함께 한
    // build()에 있어 API 키 저장 뒤의 profileProvider.notifier.reload()가
    // 이 부분도 다시 그리게 만들었다 — 그 재빌드 계약을 그대로 유지한다.
    ref.watch(profileProvider);
    final apiKeySet =
        (ref.read(storageServiceProvider).claudeApiKey ?? '').isNotEmpty;

    return ListTile(
      leading: const Icon(Icons.smart_toy_outlined),
      title: const Text('Claude API 키'),
      subtitle: Text(
        apiKeySet ? '설정됨 — AI 추천 사용 중' : '설정 안 됨 — 로컬 규칙 기반 추천 사용 중',
      ),
      onTap: () => _editApiKey(context, ref),
    );
  }
}
