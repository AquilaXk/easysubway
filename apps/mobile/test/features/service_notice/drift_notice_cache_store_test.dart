import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/service_notice/data/drift_notice_cache_store.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late DriftNoticeCacheStore store;

  setUp(() {
    db = UserDatabase.memory();
    store = DriftNoticeCacheStore(userDatabase: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('저장된 캐시가 없으면 null', () async {
    expect(await store.load(), isNull);
  });

  test('etag·공지·수신 시각을 왕복 저장한다', () async {
    final fetchedAt = DateTime.utc(2026, 7, 6, 12, 0, 0);
    await store.save(
      NoticeCacheEntry(
        etag: '"e1"',
        notices: [
          ServiceNotice(
            id: 'n1',
            scope: NoticeScope.line,
            scopeValue: '2',
            title: '2호선 지연',
            body: '우회',
            severity: NoticeSeverity.disruption,
            publishedAt: DateTime.parse('2026-07-06T09:00:00'),
          ),
        ],
        fetchedAt: fetchedAt,
      ),
    );

    final loaded = (await store.load())!;
    expect(loaded.etag, '"e1"');
    expect(loaded.fetchedAt, fetchedAt);
    expect(loaded.notices.single.id, 'n1');
    expect(loaded.notices.single.severity, NoticeSeverity.disruption);
    expect(loaded.notices.single.scopeValue, '2');
  });
}
