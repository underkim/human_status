import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:human_status/models/asset_snapshot.dart';
import 'package:human_status/models/goal.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/models/user_profile.dart';
import 'package:human_status/services/financial_advisor_service.dart';
import 'package:human_status/services/storage_service.dart';
import 'package:uuid/uuid.dart';

import 'helpers/test_app.dart';

/// Always throws, simulating a timed-out or otherwise failed Claude request.
class _AlwaysFailsSource implements FinancialAdviceSource {
  @override
  Future<List<AdviceItem>> generateAdvice(FinancialAdviceContext context) {
    throw TimeoutException('simulated timeout');
  }
}

void main() {
  group('AdviceItem.toJson/fromJson', () {
    test('round-trips', () {
      const item = AdviceItem(category: 'spending', message: 'test');
      final restored = AdviceItem.fromJson(item.toJson());
      expect(restored.category, 'spending');
      expect(restored.message, 'test');
    });
  });

  group('LocalRuleFinancialAdviceSource', () {
    final source = LocalRuleFinancialAdviceSource();

    test('flags a category increase of 30% or more', () async {
      const context = FinancialAdviceContext(
        currentMonthExpenseByCategory: {'식비': 130},
        previousMonthExpenseByCategory: {'식비': 100},
        goalProgress: [],
      );
      final advice = await source.generateAdvice(context);
      expect(
        advice.any((a) => a.category == 'spending' && a.message.contains('식비')),
        isTrue,
      );
    });

    test('praises a category decrease of 30% or more', () async {
      const context = FinancialAdviceContext(
        currentMonthExpenseByCategory: {'식비': 60},
        previousMonthExpenseByCategory: {'식비': 100},
        goalProgress: [],
      );
      final advice = await source.generateAdvice(context);
      expect(
        advice.any(
          (a) => a.category == 'spending' && a.message.contains('줄였어요'),
        ),
        isTrue,
      );
    });

    test('does not comment on changes under the threshold', () async {
      const context = FinancialAdviceContext(
        currentMonthExpenseByCategory: {'식비': 110},
        previousMonthExpenseByCategory: {'식비': 100},
        goalProgress: [],
      );
      final advice = await source.generateAdvice(context);
      expect(advice.any((a) => a.category == 'spending'), isFalse);
    });

    test('flags a goal that is behind its expected pace', () async {
      const context = FinancialAdviceContext(
        currentMonthExpenseByCategory: {},
        previousMonthExpenseByCategory: {},
        goalProgress: [
          GoalProgressSummary(
            title: '여행자금',
            actualProgress: 0.2,
            expectedProgress: 0.5,
          ),
        ],
      );
      final advice = await source.generateAdvice(context);
      expect(
        advice.any(
          (a) =>
              a.category == 'goal' &&
              a.message.contains('여행자금') &&
              a.message.contains('느려요'),
        ),
        isTrue,
      );
    });

    test('praises a goal that is on or ahead of pace', () async {
      const context = FinancialAdviceContext(
        currentMonthExpenseByCategory: {},
        previousMonthExpenseByCategory: {},
        goalProgress: [
          GoalProgressSummary(
            title: '여행자금',
            actualProgress: 0.6,
            expectedProgress: 0.5,
          ),
        ],
      );
      final advice = await source.generateAdvice(context);
      expect(
        advice.any((a) => a.category == 'goal' && a.message.contains('잘 따라가고')),
        isTrue,
      );
    });

    test('comments on net worth direction when available', () async {
      const context = FinancialAdviceContext(
        currentMonthExpenseByCategory: {},
        previousMonthExpenseByCategory: {},
        goalProgress: [],
        netWorthChangePercent: 12,
      );
      final advice = await source.generateAdvice(context);
      expect(
        advice.any(
          (a) => a.category == 'networth' && a.message.contains('늘었어요'),
        ),
        isTrue,
      );
    });

    test(
      'falls back to a general encouragement message when nothing else applies',
      () async {
        const context = FinancialAdviceContext(
          currentMonthExpenseByCategory: {},
          previousMonthExpenseByCategory: {},
          goalProgress: [],
        );
        final advice = await source.generateAdvice(context);
        expect(advice, hasLength(1));
        expect(advice.first.category, 'general');
      },
    );
  });

  group('FinancialAdvisorService.shouldRefresh', () {
    final service = FinancialAdvisorService(storage: StorageService());

    test('is true when never refreshed', () {
      expect(service.shouldRefresh(UserProfile()), isTrue);
    });

    test('is false right after a refresh', () {
      expect(
        service.shouldRefresh(UserProfile(lastAdviceRefresh: DateTime.now())),
        isFalse,
      );
    });

    test('is true once the refresh interval has elapsed', () {
      final stale = DateTime.now().subtract(const Duration(hours: 25));
      expect(
        service.shouldRefresh(UserProfile(lastAdviceRefresh: stale)),
        isTrue,
      );
    });
  });

  group('FinancialAdvisorService.refreshIfNeeded fallback', () {
    test(
      'a Claude timeout falls back to the local rule engine and updates the cache',
      () async {
        final storage = await createTestStorage();
        final service = FinancialAdvisorService(
          storage: storage,
          source: _AlwaysFailsSource(),
        );

        final advice = await service.refreshIfNeeded();

        expect(advice, isNotEmpty);
        expect(storage.getProfile().lastAdviceRefresh, isNotNull);
        expect(storage.getProfile().cachedAdvice, isNotEmpty);
      },
    );

    test(
      'preserves the previously cached advice when refresh is not due',
      () async {
        final storage = await createTestStorage();
        final profile = storage.getProfile();
        profile.lastAdviceRefresh = DateTime.now();
        profile.cachedAdvice = [
          const AdviceItem(category: 'general', message: 'old advice').toJson(),
        ];
        await storage.saveProfile(profile);
        final service = FinancialAdvisorService(
          storage: storage,
          source: _AlwaysFailsSource(),
        );

        final advice = await service.refreshIfNeeded();

        expect(advice, hasLength(1));
        expect(advice.first.message, 'old advice');
      },
    );
  });

  group('FinancialAdvisorService secure API key selection', () {
    test(
      'with no source override and no stored API key, the local engine is used and no HTTP request is made',
      () async {
        final storage = await createTestStorage();
        var requested = false;
        final client = MockClient((request) async {
          requested = true;
          return http.Response('unused', 200);
        });
        final service = FinancialAdvisorService(
          storage: storage,
          claudeHttpClient: client,
        );

        final advice = await service.refreshIfNeeded();

        expect(requested, isFalse);
        expect(advice, isNotEmpty);
      },
    );

    test(
      'with no source override and a stored API key, Claude is used with that key and its result is cached',
      () async {
        final storage = await createTestStorage();
        await storage.saveClaudeApiKey('sk-ant-from-secure-storage');
        String? capturedApiKeyHeader;
        final client = MockClient((request) async {
          capturedApiKeyHeader = request.headers['x-api-key'];
          return http.Response(
            '{"content": [{"type": "text", "text": '
            '"[{\\"category\\": \\"spending\\", \\"message\\": \\"Claude generated advice\\"}]"}]}',
            200,
          );
        });
        final service = FinancialAdvisorService(
          storage: storage,
          claudeHttpClient: client,
        );

        final advice = await service.refreshIfNeeded();

        expect(capturedApiKeyHeader, 'sk-ant-from-secure-storage');
        expect(advice, hasLength(1));
        expect(advice.first.message, 'Claude generated advice');
      },
    );

    test(
      'a Claude HTTP failure with a stored API key still falls back to the local engine',
      () async {
        final storage = await createTestStorage();
        await storage.saveClaudeApiKey('sk-ant-broken');
        final client = MockClient(
          (request) async => http.Response('server error', 500),
        );
        final service = FinancialAdvisorService(
          storage: storage,
          claudeHttpClient: client,
        );

        final advice = await service.refreshIfNeeded();

        expect(advice, isNotEmpty);
      },
    );
  });

  group('FinancialAdvisorService.buildContext', () {
    late Directory tempDir;
    late StorageService storage;
    late FinancialAdvisorService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'human_status_advisor_test_',
      );
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(GoalAdapter());
      }
      if (!Hive.isAdapterRegistered(4)) {
        Hive.registerAdapter(TransactionAdapter());
      }
      if (!Hive.isAdapterRegistered(5)) {
        Hive.registerAdapter(AssetSnapshotAdapter());
      }

      storage = StorageService();
      final suffix = DateTime.now().microsecondsSinceEpoch;
      storage.transactionsBox = await Hive.openBox<Transaction>('tx_$suffix');
      storage.goalsBox = await Hive.openBox<Goal>('goals_$suffix');
      storage.assetSnapshotsBox = await Hive.openBox<AssetSnapshot>(
        'snap_$suffix',
      );
      service = FinancialAdvisorService(storage: storage);
    });

    tearDown(() async {
      await storage.transactionsBox.close();
      await storage.goalsBox.close();
      await storage.assetSnapshotsBox.close();
      await tempDir.delete(recursive: true);
    });

    Transaction tx(double amount, DateTime date, {String category = '식비'}) =>
        Transaction(
          id: const Uuid().v4(),
          type: TransactionType.expense,
          category: category,
          memo: '',
          amount: amount,
          date: date,
          createdAt: DateTime.now(),
        );

    test('aggregates this month vs last month expenses by category', () async {
      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1, 15);
      await storage.saveTransaction(tx(100, now));
      await storage.saveTransaction(tx(50, now, category: '교통'));
      await storage.saveTransaction(tx(80, lastMonth));

      final context = service.buildContext();

      expect(context.currentMonthExpenseByCategory['식비'], 100);
      expect(context.currentMonthExpenseByCategory['교통'], 50);
      expect(context.previousMonthExpenseByCategory['식비'], 80);
    });

    test(
      'computes expectedProgress from elapsed time for a dated financial goal',
      () async {
        final now = DateTime.now();
        final goal = Goal(
          id: 'g1',
          title: '여행자금',
          description: '',
          statId: 'wealth',
          targetAmount: 1000,
          currentAmount: 200,
          targetDate: now.add(const Duration(days: 10)),
          createdAt: now.subtract(const Duration(days: 10)),
        );
        await storage.saveGoal(goal);

        final context = service.buildContext();

        expect(context.goalProgress, hasLength(1));
        expect(context.goalProgress.first.expectedProgress, closeTo(0.5, 0.05));
        expect(context.goalProgress.first.actualProgress, 0.2);
      },
    );

    test('netWorthChange is null with fewer than 2 snapshots', () async {
      await storage.saveAssetSnapshot(
        AssetSnapshot(
          id: 's1',
          importedAt: DateTime.now(),
          assetsByCategory: {'현금': 1000},
          liabilitiesByCategory: {},
          totalAssets: 1000,
          totalLiabilities: 0,
        ),
      );

      final context = service.buildContext();

      expect(context.netWorthChange, isNull);
      expect(context.netWorthChangePercent, isNull);
    });

    test(
      'computes netWorthChangePercent from the two most recent snapshots',
      () async {
        final now = DateTime.now();
        await storage.saveAssetSnapshot(
          AssetSnapshot(
            id: 's1',
            importedAt: now.subtract(const Duration(days: 30)),
            assetsByCategory: {'현금': 1000},
            liabilitiesByCategory: {},
            totalAssets: 1000,
            totalLiabilities: 0,
          ),
        );
        await storage.saveAssetSnapshot(
          AssetSnapshot(
            id: 's2',
            importedAt: now,
            assetsByCategory: {'현금': 1100},
            liabilitiesByCategory: {},
            totalAssets: 1100,
            totalLiabilities: 0,
          ),
        );

        final context = service.buildContext();

        expect(context.netWorthChange, 100);
        expect(context.netWorthChangePercent, 10);
      },
    );
  });
}
