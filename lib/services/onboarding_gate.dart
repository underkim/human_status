import 'storage_service.dart';

/// Whether the app should show the first-mission onboarding flow instead of
/// [HomeShell]. HumanStatusApp re-evaluates this on every build (not just at
/// launch) so a mid-session change — completing/skipping onboarding, or a
/// data reset in Settings — is reflected immediately.
///
/// `UserProfile.onboardingCompleted` already defaults to `true` when read
/// from a pre-onboarding Hive record (see UserProfileAdapter), so existing
/// users are never re-onboarded after an update. This extra `goals`/`quests`
/// check is a safety net for the one case that fallback can't cover: a fresh
/// install (new, incomplete `UserProfile`) that immediately restores an
/// older backup — backups intentionally exclude the profile box, so the
/// flag alone would stay `false` even though the restored data proves this
/// isn't a first run.
bool shouldShowOnboarding(StorageService storage) {
  final profile = storage.getProfile();
  if (profile.onboardingCompleted) return false;
  return storage.getGoals().isEmpty && storage.getQuests().isEmpty;
}
