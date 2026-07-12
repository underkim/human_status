import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/financial_advisor_service.dart';
import '../services/storage_service.dart';
import 'profile_provider.dart';

final financialAdvisorServiceProvider = Provider<FinancialAdvisorService>(
  (ref) => FinancialAdvisorService(storage: ref.watch(storageServiceProvider)),
);

final financialAdviceProvider = StateNotifierProvider<FinancialAdviceNotifier, List<AdviceItem>>((ref) {
  return FinancialAdviceNotifier(ref.watch(storageServiceProvider), ref);
});

class FinancialAdviceNotifier extends StateNotifier<List<AdviceItem>> {
  final StorageService storage;
  final Ref ref;

  // Initial state reads whatever main.dart's startup refreshIfNeeded() call
  // already cached on the profile, so no extra refresh is triggered here.
  FinancialAdviceNotifier(this.storage, this.ref)
      : super(storage.getProfile().cachedAdvice.map(AdviceItem.fromJson).toList());

  void reload() => state = storage.getProfile().cachedAdvice.map(AdviceItem.fromJson).toList();

  /// Forces a fresh round of advice regardless of the 24h refresh interval —
  /// used by the manual refresh button.
  Future<void> refreshNow() async {
    final profile = storage.getProfile();
    profile.lastAdviceRefresh = null;
    await storage.saveProfile(profile);
    final advice = await ref.read(financialAdvisorServiceProvider).refreshIfNeeded();
    state = advice;
  }
}
