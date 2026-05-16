import 'package:flutter_test/flutter_test.dart';
import 'package:jusou/data/models/link_validation.dart';
import 'package:jusou/data/models/local_library.dart';
import 'package:jusou/data/models/resource.dart';
import 'package:jusou/data/services/link_validator.dart';
import 'package:jusou/data/services/local_library_service.dart';
import 'package:jusou/data/services/resource_aggregator.dart';
import 'package:jusou/data/services/resource_deduper.dart';
import 'package:jusou/data/services/resource_service.dart';
import 'package:jusou/data/services/resource_source.dart';
import 'package:jusou/data/services/resource_text_normalizer.dart';
import 'package:jusou/data/services/share_link_parser.dart';

void main() {
  group('ResourceTextNormalizer', () {
    test('matches common variant characters in Chinese titles', () {
      const normalizer = ResourceTextNormalizer();

      expect(normalizer.titleKey('狂飚'), '狂飙');
      expect(normalizer.keywordMatchScore('狂飚', '狂飙'), 40);
      expect(normalizer.searchQueryVariants('狂飚'), ['狂飚', '狂飙']);
    });
  });

  group('ShareLinkParser', () {
    test('normalizes Aliyun and Alipan links to the same share id', () {
      const parser = ShareLinkParser();

      final aliyun = parser.parse(
        'https://www.aliyundrive.com/s/abc123?foo=bar',
      );
      final alipan = parser.parse('https://www.alipan.com/s/abc123');

      expect(aliyun.provider, 'aliyun');
      expect(alipan.provider, 'aliyun');
      expect(aliyun.shareId, alipan.shareId);
      expect(aliyun.canonicalUrl, alipan.canonicalUrl);
    });

    test('recognizes common cloud drive providers from remote results', () {
      const parser = ShareLinkParser();

      expect(parser.parse('https://drive.uc.cn/s/abc123').provider, 'uc');
      expect(
        parser.parse('https://pan.xunlei.com/s/abc123?pwd=1234').provider,
        'xunlei',
      );
      expect(
        parser.parse('https://115cdn.com/s/abc123?password=1234').provider,
        '115',
      );
      expect(parser.parse('https://123pan.com/s/abc123').provider, '123');
    });
  });

  group('LinkValidator', () {
    test('rejects demo placeholder share links from seed data', () async {
      const validator = LinkValidator();

      final validation = await validator.validate(
        _resource(
          id: 'seed',
          title: '狂飙',
          shareUrl: 'https://www.aliyundrive.com/s/example5',
          source: 'local',
        ),
      );

      expect(validation.level, LinkValidationLevel.invalid);
    });
  });

  group('Resource', () {
    test('round trips validation and merged metadata from json', () {
      final checkedAt = DateTime(2026, 1, 2, 3, 4);

      final resource = Resource.fromJson({
        'id': 'resource',
        'title': '繁花',
        'share_url': 'https://www.alipan.com/s/fanhua123',
        'source': 'local',
        'updated_at': DateTime(2026).toIso8601String(),
        'quality_score': 88.5,
        'duplicate_count': 3,
        'merged_sources': ['local', 'remote'],
        'validation': {
          'level': 'httpReachable',
          'reason': '链接页面可访问',
          'checked_at': checkedAt.toIso8601String(),
        },
      });

      expect(resource.qualityScore, 88.5);
      expect(resource.duplicateCount, 3);
      expect(resource.mergedSources, ['local', 'remote']);
      expect(resource.validation?.level, LinkValidationLevel.httpReachable);
      expect(resource.validation?.checkedAt, checkedAt);
    });
  });

  group('ResourceAggregator', () {
    test('dedupes the same share from multiple sources', () async {
      final aggregator = ResourceAggregator(
        sources: [
          _FakeSource(
            id: 'source_a',
            label: 'source_a',
            trustScore: 70,
            resources: [
              _resource(
                id: 'a',
                title: '流浪地球2',
                shareUrl: 'https://www.aliyundrive.com/s/abc123',
                source: 'source_a',
              ),
            ],
          ),
          _FakeSource(
            id: 'source_b',
            label: 'source_b',
            trustScore: 60,
            resources: [
              _resource(
                id: 'b',
                title: '流浪地球2 阿里云盘',
                shareUrl: 'https://www.alipan.com/s/abc123',
                source: 'source_b',
              ),
            ],
          ),
        ],
      );

      final result = await aggregator.search('流浪地球2');

      expect(result.totalBeforeDedupe, 2);
      expect(result.total, 1);
      expect(result.resources.single.duplicateCount, 2);
      expect(
        result.resources.single.mergedSources,
        containsAll(['source_a', 'source_b']),
      );
    });

    test('dedupes repeated link variants from search results', () async {
      final aggregator = ResourceAggregator(
        sources: [
          _FakeSource(
            id: 'source_a',
            label: 'source_a',
            trustScore: 70,
            resources: [
              _resource(
                id: 'a',
                title: '狂飙',
                shareUrl: 'https://www.aliyundrive.com/s/same123?pwd=abcd',
                source: 'source_a',
              ),
              _resource(
                id: 'b',
                title: '狂飙 阿里云盘',
                shareUrl: 'https://www.alipan.com/s/same123',
                source: 'source_a',
              ),
            ],
          ),
        ],
      );

      final result = await aggregator.search('狂飙');

      expect(result.totalBeforeDedupe, 2);
      expect(result.total, 1);
      expect(result.resources.single.duplicateCount, 2);
    });

    test('keeps a usable poster from any merged duplicate', () {
      const deduper = ResourceDeduper();

      final result = deduper.dedupe([
        _resource(
          id: 'a',
          title: '漫长的季节',
          year: '2023',
          fileSize: '35GB',
          shareUrl: 'https://www.aliyundrive.com/s/posterless123',
          source: 'source_a',
        ),
        _resource(
          id: 'b',
          title: '漫长的季节 4K',
          posterUrl: 'https://example.com/poster.jpg',
          shareUrl: 'https://www.alipan.com/s/posterless123',
          source: 'source_b',
        ),
      ]);

      expect(result, hasLength(1));
      expect(result.single.posterUrl, 'https://example.com/poster.jpg');
    });

    test('ranks stronger matches before noisy titles', () async {
      final aggregator = ResourceAggregator(
        sources: [
          _FakeSource(
            id: 'trusted',
            label: 'trusted',
            trustScore: 80,
            resources: [
              _resource(
                id: 'good',
                title: '繁花',
                year: '2023',
                shareUrl: 'https://www.alipan.com/s/good123',
                fileSize: '45GB',
                source: 'trusted',
              ),
              _resource(
                id: 'noisy',
                title: '繁花 在线观看 免费下载 阿里云盘',
                shareUrl: 'https://example.com/fanhua',
                source: 'trusted',
              ),
            ],
          ),
        ],
      );

      final result = await aggregator.search('繁花');

      expect(result.resources, hasLength(2));
      expect(result.resources.first.id, 'good');
      expect(
        result.resources.first.qualityScore,
        greaterThan(result.resources.last.qualityScore),
      );
    });

    test('retries sources with variant-normalized Chinese query', () async {
      final source = _QueryAwareFakeSource(
        id: 'source_a',
        label: 'source_a',
        trustScore: 70,
        resourcesByQuery: {
          '狂飙': [
            _resource(
              id: 'kuangbiao',
              title: '狂飙',
              year: '2023',
              shareUrl: 'https://www.alipan.com/s/kuangbiao123',
              source: 'source_a',
            ),
          ],
        },
      );
      final aggregator = ResourceAggregator(sources: [source]);

      final result = await aggregator.search('狂飚');

      expect(source.queries, ['狂飚', '狂飙']);
      expect(result.resources, hasLength(1));
      expect(result.resources.single.title, '狂飙');
    });

    test('filters placeholder share links from search results', () async {
      final aggregator = ResourceAggregator(
        sources: [
          _FakeSource(
            id: 'local',
            label: 'local',
            trustScore: 70,
            resources: [
              _resource(
                id: 'seed',
                title: '狂飙',
                shareUrl: 'https://www.aliyundrive.com/s/example5',
                source: 'local',
              ),
            ],
          ),
        ],
      );

      final result = await aggregator.search('狂飙');

      expect(result.totalBeforeDedupe, 1);
      expect(result.resources, isEmpty);
    });
  });

  group('ResourceService', () {
    test('exposes per-source status and failures', () async {
      final service = ResourceService(
        sources: [
          _FakeSource(
            id: 'local',
            label: '本地',
            trustScore: 70,
            resources: [
              _resource(
                id: 'local-a',
                title: '繁花',
                shareUrl: 'https://www.alipan.com/s/fanhua123',
                source: 'local',
              ),
            ],
          ),
          const _ThrowingSource(id: 'remote', label: '远程', trustScore: 50),
        ],
      );

      final result = await service.searchDetailed('繁花');

      expect(result.results, hasLength(1));
      expect(result.totalBeforeDedupe, 1);
      expect(result.sourceStatuses, hasLength(2));
      expect(
        result.sourceStatuses
            .firstWhere((status) => status.sourceId == 'local')
            .level,
        SourceStatusLevel.success,
      );
      expect(
        result.sourceStatuses
            .firstWhere((status) => status.sourceId == 'remote')
            .level,
        SourceStatusLevel.failure,
      );
    });
  });

  group('LocalLibraryService', () {
    test(
      'stores favorites, history, invalid reports, settings and validation cache',
      () async {
        final service = LocalLibraryService(enablePersistence: false);
        final resource = _resource(
          id: 'fav',
          title: '漫长的季节',
          shareUrl: 'https://www.alipan.com/s/season123',
          source: 'local',
        );
        final validated = resource.copyWith(
          validation: LinkValidationResult(
            level: LinkValidationLevel.recognizedShare,
            reason: '已识别',
            checkedAt: DateTime(2026),
          ),
        );

        expect(await service.toggleFavorite(resource), isTrue);
        await service.recordOpened(resource);
        await service.recordSearch('漫长的季节', 12);
        await service.reportInvalid(resource);
        await service.cacheValidation(validated);
        await service.updateSettings(
          const LibrarySettings(
            enableRemote: false,
            remoteUrl: 'https://example.com',
          ),
        );

        final snapshot = await service.snapshot();
        final cached = await service.applyCachedValidation([resource]);

        expect(snapshot.favorites.single.title, '漫长的季节');
        expect(snapshot.recentlyOpened.single.shareUrl, resource.shareUrl);
        expect(snapshot.searchHistory.single.query, '漫长的季节');
        expect(snapshot.invalidReports.single.shareUrl, resource.shareUrl);
        expect(snapshot.settings.enableRemote, isFalse);
        expect(
          cached.single.validation?.level,
          LinkValidationLevel.recognizedShare,
        );
      },
    );
  });
}

class _FakeSource implements ResourceSource {
  @override
  final String id;

  @override
  final String label;

  @override
  final int trustScore;

  final List<Resource> resources;

  const _FakeSource({
    required this.id,
    required this.label,
    required this.trustScore,
    required this.resources,
  });

  @override
  Future<SourceSearchResult> search(String query) async {
    return SourceSearchResult(
      sourceId: id,
      sourceLabel: label,
      resources: resources,
      total: resources.length,
      elapsedMs: 0,
    );
  }
}

class _QueryAwareFakeSource implements ResourceSource {
  @override
  final String id;

  @override
  final String label;

  @override
  final int trustScore;

  final Map<String, List<Resource>> resourcesByQuery;
  final List<String> queries = [];

  _QueryAwareFakeSource({
    required this.id,
    required this.label,
    required this.trustScore,
    required this.resourcesByQuery,
  });

  @override
  Future<SourceSearchResult> search(String query) async {
    queries.add(query);
    final resources = resourcesByQuery[query] ?? const <Resource>[];
    return SourceSearchResult(
      sourceId: id,
      sourceLabel: label,
      resources: resources,
      total: resources.length,
      elapsedMs: 0,
    );
  }
}

class _ThrowingSource implements ResourceSource {
  @override
  final String id;

  @override
  final String label;

  @override
  final int trustScore;

  const _ThrowingSource({
    required this.id,
    required this.label,
    required this.trustScore,
  });

  @override
  Future<SourceSearchResult> search(String query) async {
    throw StateError('boom');
  }
}

Resource _resource({
  required String id,
  required String title,
  required String shareUrl,
  required String source,
  String? year,
  String? fileSize,
  String? posterUrl,
}) {
  return Resource(
    id: id,
    title: title,
    year: year,
    type: 'movie',
    shareUrl: shareUrl,
    posterUrl: posterUrl,
    fileSize: fileSize,
    source: source,
    updatedAt: DateTime(2026),
  );
}
