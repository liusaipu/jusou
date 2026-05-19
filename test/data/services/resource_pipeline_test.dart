import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jusou/data/models/link_validation.dart';
import 'package:jusou/data/models/local_library.dart';
import 'package:jusou/data/models/resource.dart';
import 'package:jusou/data/services/alipansou_search_source.dart';
import 'package:jusou/data/services/link_validator.dart';
import 'package:jusou/data/services/local_library_service.dart';
import 'package:jusou/data/services/resource_aggregator.dart';
import 'package:jusou/data/services/resource_deduper.dart';
import 'package:jusou/data/services/resource_key.dart';
import 'package:jusou/data/services/remote_search_source.dart';
import 'package:jusou/data/services/resource_service.dart';
import 'package:jusou/data/services/resource_source.dart';
import 'package:jusou/data/services/resource_text_normalizer.dart';
import 'package:jusou/data/services/share_link_parser.dart';
import 'package:path/path.dart' as p;

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

    test('falls back to GET when HEAD cannot confirm reachability', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((options) {
          if (options.method == 'HEAD') {
            return ResponseBody.fromString('', 405);
          }
          return ResponseBody.fromString('', 200);
        });
      final validator = LinkValidator(dio: dio, enableNetworkCheck: true);

      final validation = await validator.validate(
        _resource(
          id: 'share',
          title: '繁花',
          shareUrl: 'https://www.alipan.com/s/fanhua123',
          source: 'local',
        ),
      );

      expect(validation.level, LinkValidationLevel.httpReachable);
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

    test('normalizes common resource types from json', () {
      final documentary = Resource.fromJson({
        'title': '地球脉动',
        'type': '纪录片',
        'share_url': 'https://www.alipan.com/s/doc123',
      });
      final variety = Resource.fromJson({
        'title': '声生不息',
        'type': 'variety',
        'share_url': 'https://www.alipan.com/s/show123',
      });

      expect(documentary.type, 'documentary');
      expect(variety.type, 'variety');
    });
  });

  group('ResourceKey', () {
    test('uses canonical share identity for link variants', () {
      final aliyun = _resource(
        id: 'a',
        title: '狂飙',
        shareUrl: 'https://www.aliyundrive.com/s/same123?pwd=abcd',
        source: 'local',
      );
      final alipan = _resource(
        id: 'b',
        title: '狂飙',
        shareUrl: 'https://www.alipan.com/s/same123',
        source: 'remote',
      );

      expect(ResourceKey.forResource(aliyun), ResourceKey.forResource(alipan));
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
    test('detects configured remote data sources', () {
      final empty = ResourceService(sources: const []);
      final remote = ResourceService(
        remoteUrls: const ['https://api.example.test'],
        sources: [RemoteSearchSource(baseUrl: 'https://api.example.test')],
      );

      expect(empty.hasConfiguredDataSources, isFalse);
      expect(remote.hasConfiguredDataSources, isTrue);
    });

    test('uses alipansou adapter for configured remote url', () {
      final service = ResourceService(remoteUrls: const ['alipansou.com']);

      expect(service.sources.whereType<AlipansouSearchSource>(), hasLength(1));
    });

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

  group('AlipansouSearchSource', () {
    test('supports alipansou host names', () {
      expect(AlipansouSearchSource.supports('https://alipansou.com'), isTrue);
      expect(
        AlipansouSearchSource.supports('https://www.alipansou.com'),
        isTrue,
      );
      expect(AlipansouSearchSource.supports('alipansou.com'), isTrue);
      expect(
        AlipansouSearchSource.supports('https://api.example.test'),
        isFalse,
      );
    });

    test('computes challenge cookie value used by alipansou', () {
      final cookie = AlipansouSearchSource.challengeCookieValue(
        '4592c1122aa2602528737b5ea1bbb7c665d6667c4493a502f907433bf8e5230b'
        'b07dc20337475005417a3429e2eaa34c',
      );

      expect(
        cookie,
        '6e7ceb2a708864a5fe98e470d4ede4a13b51e89dd15c55832d34b739291461d0'
        'ecb43190217dc7ca65a57a3f265ebf1248de754a46791617dbaf5a33004c7def'
        '28778c7a5356ced7e22474f6a6e16bd77e5ef8c83fa9a47022ac5cf3862f8a'
        '24503e3a3e3ba98027c359b121a95e1c88',
      );
    });

    test('parses search cards and resolves cv redirects', () async {
      const challenge =
          '4592c1122aa2602528737b5ea1bbb7c665d6667c4493a502f907433bf8e5230b'
          'b07dc20337475005417a3429e2eaa34c';
      final dio = Dio(BaseOptions(baseUrl: 'https://alipansou.com'))
        ..httpClientAdapter = _FakeHttpClientAdapter((options) {
          if (options.path == '/search' && options.headers['Cookie'] == null) {
            return ResponseBody.fromString(
              '''
              <html>
                <div id="ori" style="display:none;">/search?k=主角</div>
                <script>start_load("$challenge")</script>
                ck_ml_sea_
              </html>
              ''',
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8'],
              },
            );
          }

          if (options.path == '/search' &&
              options.headers['Cookie']?.toString().contains('ck_ml_sea_=') ==
                  true) {
            return ResponseBody.fromString(
              '''
              <a href="/s/lfw80FXpCeBCoimtzj8exbPDsIri8" target="_blank">
                <van-card>
                  <template #title>
                    <div name="content-title">
                      <span style='color:red;'>主角</span>(2026） 4K 更新至13集
                    </div>
                  </template>
                  <template #bottom>
                    <div>
                      时间: 2026-05-10 &nbsp;&nbsp;格式: <b>文件夹</b> &nbsp;&nbsp;大小: 3.8G
                    </div>
                  </template>
                </van-card>
              </a>
              ''',
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html; charset=utf-8'],
              },
            );
          }

          if (options.path == '/cv/lfw80FXpCeBCoimtzj8exbPDsIri8') {
            return ResponseBody.fromString(
              '<a href="https://www.alipan.com/s/MMBcWB9zCUf">Found</a>',
              302,
              headers: {
                'location': ['https://www.alipan.com/s/MMBcWB9zCUf'],
              },
            );
          }

          return ResponseBody.fromString('', 404);
        });
      final source = AlipansouSearchSource(dio: dio);

      final result = await source.search('主角');

      expect(result.resources, hasLength(1));
      final resource = result.resources.single;
      expect(resource.title, '主角 (2026） 4K 更新至13集');
      expect(resource.shareUrl, 'https://www.alipan.com/s/MMBcWB9zCUf');
      expect(resource.fileSize, '3.8GB');
      expect(resource.episodeCount, 13);
      expect(resource.updatedAt, DateTime(2026, 5, 10));
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
            remoteUrls: ['https://example.com'],
            darkMode: false,
            telegramChannels: ['movie_channel'],
          ),
        );

        final snapshot = await service.snapshot();
        final cached = await service.applyCachedValidation([resource]);

        expect(snapshot.favorites.single.title, '漫长的季节');
        expect(snapshot.recentlyOpened.single.shareUrl, resource.shareUrl);
        expect(snapshot.searchHistory.single.query, '漫长的季节');
        expect(snapshot.invalidReports.single.shareUrl, resource.shareUrl);
        expect(snapshot.settings.enableRemote, isFalse);
        expect(snapshot.settings.darkMode, isFalse);
        expect(snapshot.settings.telegramChannels, ['movie_channel']);
        expect(
          cached.single.validation?.level,
          LinkValidationLevel.recognizedShare,
        );
      },
    );

    test(
      'uses canonical resource keys for favorites and validation cache',
      () async {
        final service = LocalLibraryService(enablePersistence: false);
        final aliyun = _resource(
          id: 'a',
          title: '狂飙',
          shareUrl: 'https://www.aliyundrive.com/s/same123?pwd=abcd',
          source: 'local',
        );
        final alipan = _resource(
          id: 'b',
          title: '狂飙 阿里云盘',
          shareUrl: 'https://www.alipan.com/s/same123',
          source: 'remote',
        );
        final validated = aliyun.copyWith(
          validation: LinkValidationResult(
            level: LinkValidationLevel.recognizedShare,
            reason: '已识别',
            checkedAt: DateTime(2026),
          ),
        );

        expect(await service.toggleFavorite(aliyun), isTrue);
        expect(await service.toggleFavorite(alipan), isFalse);
        await service.cacheValidation(validated);

        final snapshot = await service.snapshot();
        final cached = await service.applyCachedValidation([alipan]);

        expect(snapshot.favorites, isEmpty);
        expect(
          cached.single.validation?.level,
          LinkValidationLevel.recognizedShare,
        );
      },
    );

    test('imports and exports portable config packages', () async {
      final service = LocalLibraryService(enablePersistence: false);

      final imported = await service.importConfig('''
{
  "app": "jusou",
  "schema_version": 1,
  "settings": {
    "enable_remote": false,
    "remote_urls": [
      "https://one.example.test",
      "https://two.example.test",
      "https://one.example.test"
    ],
    "dark_mode": false,
    "telegram_channels": [
      "@MovieShare",
      "https://t.me/s/DramaShare",
      "bad channel"
    ]
  }
}
''');

      expect(imported.enableRemote, isFalse);
      expect(imported.remoteUrls, [
        'https://one.example.test',
        'https://two.example.test',
      ]);
      expect(imported.darkMode, isFalse);
      expect(imported.telegramChannels, ['movieshare', 'dramashare']);

      final exported = await service.exportConfig(exportedAt: DateTime(2026));

      expect(exported, contains('"app": "jusou"'));
      expect(exported, contains('"schema_version": 1'));
      expect(exported, contains('"enable_remote": false'));
      expect(exported, contains('"telegram_channels": ['));
      expect(exported, contains('"movieshare"'));
    });

    test(
      'writes selected config files by overwriting existing content',
      () async {
        final dir = await Directory.systemTemp.createTemp('jusou_config_test');
        addTearDown(() => dir.delete(recursive: true));
        final path = p.join(dir.path, 'config.json');
        await File(path).writeAsString('old content');

        final service = LocalLibraryService(enablePersistence: false);
        await service.updateSettings(
          const LibrarySettings(
            enableRemote: false,
            remoteUrls: ['https://overwrite.example.test'],
            darkMode: false,
            telegramChannels: ['overwrite_channel'],
          ),
        );

        await service.writeConfigFileAt(path);
        final content = await File(path).readAsString();
        expect(content, isNot('old content'));

        final imported = await LocalLibraryService(
          enablePersistence: false,
        ).importConfigFile(path);
        expect(imported.remoteUrls, ['https://overwrite.example.test']);
        expect(imported.telegramChannels, ['overwrite_channel']);
      },
    );
  });
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;

  const _FakeHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
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
