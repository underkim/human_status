import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_status/models/quest.dart';
import 'package:human_status/models/transaction.dart';
import 'package:human_status/providers/finance_provider.dart';
import 'package:human_status/providers/profile_provider.dart';
import 'package:human_status/providers/quest_provider.dart';

import 'helpers/test_app.dart';

Quest _quest(
  String id,
  String title, {
  String description = '',
  QuestStatus status = QuestStatus.active,
  QuestDifficulty difficulty = QuestDifficulty.easy,
  String? goalId,
  DateTime? completedAt,
  DateTime? createdAt,
}) {
  return Quest(
    id: id,
    title: title,
    description: description,
    statRewards: const {'health': 10},
    status: status,
    difficulty: difficulty,
    source: status == QuestStatus.suggested
        ? QuestSource.suggested
        : QuestSource.manual,
    createdAt: createdAt ?? DateTime(2026, 7, 1),
    completedAt: completedAt,
    goalId: goalId,
  );
}

Transaction _tx(
  String id, {
  String category = '식비',
  String memo = '',
  TransactionType type = TransactionType.expense,
  double amount = 1000,
  DateTime? date,
  String? linkedGoalId,
}) {
  final d = date ?? DateTime(2026, 7, 10);
  return Transaction(
    id: id,
    type: type,
    category: category,
    memo: memo,
    amount: amount,
    date: d,
    linkedGoalId: linkedGoalId,
    createdAt: d,
  );
}

void main() {
  group('questMatchesSearchQuery', () {
    test('빈 문자열과 공백뿐인 검색어에 모든 퀘스트를 반환한다', () {
      final quest = _quest('q1', '물 마시기');
      expect(questMatchesSearchQuery(quest, ''), isTrue);
      expect(questMatchesSearchQuery(quest, '   '), isTrue);
    });

    test('title과 description을 부분 일치로 검색한다', () {
      final quest = _quest('q1', '아침 운동', description: '30분 조깅하기');
      expect(questMatchesSearchQuery(quest, '운동'), isTrue);
      expect(questMatchesSearchQuery(quest, '조깅'), isTrue);
      expect(questMatchesSearchQuery(quest, '독서'), isFalse);
    });

    test('영문 대소문자를 무시하고 한글 부분 문자열을 찾는다', () {
      final quest = _quest('q1', 'Read a book', description: '물 마시기');
      expect(questMatchesSearchQuery(quest, 'READ'), isTrue);
      expect(questMatchesSearchQuery(quest, 'read'), isTrue);
      expect(questMatchesSearchQuery(quest, '마시'), isTrue);
    });

    test('id, difficulty, goalId를 검색 대상으로 사용하지 않는다', () {
      final quest = _quest(
        'special-id-xyz',
        '물 마시기',
        description: '',
        difficulty: QuestDifficulty.hard,
        goalId: 'goal-abc',
      );
      expect(questMatchesSearchQuery(quest, 'special-id-xyz'), isFalse);
      expect(questMatchesSearchQuery(quest, '어려움'), isFalse);
      expect(questMatchesSearchQuery(quest, 'goal-abc'), isFalse);
    });
  });

  group('transactionMatchesSearchQuery', () {
    test('빈 문자열과 공백뿐인 검색어에 모든 거래를 반환한다', () {
      final tx = _tx('t1', category: '식비', memo: '점심 식사');
      expect(transactionMatchesSearchQuery(tx, ''), isTrue);
      expect(transactionMatchesSearchQuery(tx, '   '), isTrue);
    });

    test('memo와 category를 부분 일치로 검색한다', () {
      final tx = _tx('t1', category: '식비', memo: '스타벅스 아메리카노');
      expect(transactionMatchesSearchQuery(tx, '스타벅스'), isTrue);
      expect(transactionMatchesSearchQuery(tx, '식비'), isTrue);
      expect(transactionMatchesSearchQuery(tx, '교통'), isFalse);
    });

    test('영문 대소문자를 무시하고 한글 부분 문자열을 찾는다', () {
      final tx = _tx('t1', category: 'Cafe', memo: '아메리카노');
      expect(transactionMatchesSearchQuery(tx, 'CAFE'), isTrue);
      expect(transactionMatchesSearchQuery(tx, 'cafe'), isTrue);
      expect(transactionMatchesSearchQuery(tx, '아메리카노'), isTrue);
    });

    test('amount, date, linkedGoalId를 검색 대상으로 사용하지 않는다', () {
      final tx = _tx(
        't1',
        category: '식비',
        memo: '',
        amount: 12345,
        date: DateTime(2026, 7, 15),
        linkedGoalId: 'goal-search-me',
      );
      expect(transactionMatchesSearchQuery(tx, '12345'), isFalse);
      expect(transactionMatchesSearchQuery(tx, '2026'), isFalse);
      expect(transactionMatchesSearchQuery(tx, 'goal-search-me'), isFalse);
    });
  });

  group('검색어 Notifier', () {
    test('QuestSearchQueryNotifier의 clear는 state를 빈 문자열로 되돌린다', () {
      final notifier = QuestSearchQueryNotifier();
      notifier.setQuery('물 마시기');
      expect(notifier.state, '물 마시기');
      notifier.clear();
      expect(notifier.state, '');
    });

    test('TransactionSearchQueryNotifier의 clear는 state를 빈 문자열로 되돌린다', () {
      final notifier = TransactionSearchQueryNotifier();
      notifier.setQuery('스타벅스');
      expect(notifier.state, '스타벅스');
      notifier.clear();
      expect(notifier.state, '');
    });
  });

  group('퀘스트 파생 검색 Provider', () {
    test('상태별 목록과 검색어를 합성하고 완료 목록의 기존 정렬을 보존한다', () async {
      final storage = await createTestStorage();
      await storage.saveQuest(
        _quest('a1', '물 마시기', status: QuestStatus.active),
      );
      await storage.saveQuest(_quest('a2', '운동하기', status: QuestStatus.active));
      await storage.saveQuest(
        _quest('s1', '독서 추천', status: QuestStatus.suggested),
      );
      await storage.saveQuest(
        _quest(
          'c1',
          '물 마시기 완료',
          status: QuestStatus.completed,
          completedAt: DateTime(2026, 7, 1),
        ),
      );
      await storage.saveQuest(
        _quest(
          'c2',
          '늦게 완료한 물 마시기',
          status: QuestStatus.completed,
          completedAt: DateTime(2026, 7, 10),
        ),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      // 검색어가 없으면 원본 상태별 목록과 동일하다.
      expect(container.read(searchedActiveQuestsProvider).length, 2);
      expect(container.read(searchedSuggestedQuestsProvider).length, 1);
      expect(container.read(searchedCompletedQuestsProvider).length, 2);

      container.read(questSearchQueryProvider.notifier).setQuery('물 마시기');

      final active = container.read(searchedActiveQuestsProvider);
      expect(active.map((q) => q.id), ['a1']);

      final suggested = container.read(searchedSuggestedQuestsProvider);
      expect(suggested, isEmpty);

      // 완료 탭은 둘 다 일치하며, completedAt 내림차순(최신 먼저)이 유지된다.
      final completed = container.read(searchedCompletedQuestsProvider);
      expect(completed.map((q) => q.id), ['c2', 'c1']);
    });

    test('검색 중 questsProvider가 갱신되면 같은 검색어로 결과를 다시 계산한다', () async {
      final storage = await createTestStorage();
      await storage.saveQuest(
        _quest('a1', '물 마시기', status: QuestStatus.active),
      );

      final container = ProviderContainer(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      container.read(questSearchQueryProvider.notifier).setQuery('운동');
      expect(container.read(searchedActiveQuestsProvider), isEmpty);

      await container
          .read(questsProvider.notifier)
          .addQuest(_quest('a2', '운동하기', status: QuestStatus.active));

      final active = container.read(searchedActiveQuestsProvider);
      expect(active.map((q) => q.id), ['a2']);
    });
  });

  group('거래 파생 검색 Provider', () {
    test(
      'searchedTransactionsProvider는 검색 중 transactionsProvider가 갱신되면 같은 검색어로 결과를 다시 계산한다',
      () async {
        final storage = await createTestStorage();
        await storage.saveTransaction(_tx('t1', category: '식비', memo: '점심'));

        final container = ProviderContainer(
          overrides: [storageServiceProvider.overrideWithValue(storage)],
        );
        addTearDown(container.dispose);

        // 검색어가 없으면 전체 거래를 반환한다.
        expect(container.read(searchedTransactionsProvider).length, 1);

        container.read(transactionSearchQueryProvider.notifier).setQuery('카페');
        expect(container.read(searchedTransactionsProvider), isEmpty);

        await container
            .read(transactionsProvider.notifier)
            .addTransaction(_tx('t2', category: '카페', memo: '아메리카노'));

        final result = container.read(searchedTransactionsProvider);
        expect(result.map((t) => t.id), ['t2']);
      },
    );
  });
}
