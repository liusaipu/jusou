import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/resource.dart';
import 'alipansou_search_source.dart';
import 'json_file_resource_source.dart';
import 'link_validator.dart';
import 'local_index_source.dart';
import 'remote_search_source.dart';
import 'resource_aggregator.dart';
import 'resource_source.dart';

class ResourceSearchResponse {
  final List<Resource> results;
  final int total;
  final int totalBeforeDedupe;
  final int elapsedMs;
  final List<SourceStatus> sourceStatuses;

  const ResourceSearchResponse({
    required this.results,
    required this.total,
    required this.totalBeforeDedupe,
    required this.elapsedMs,
    required this.sourceStatuses,
  });
}

enum SourceStatusLevel { success, empty, partialFailure, failure }

class SourceStatus {
  final String sourceId;
  final String sourceLabel;
  final SourceStatusLevel level;
  final int resultCount;
  final int elapsedMs;
  final String? errorMessage;

  const SourceStatus({
    required this.sourceId,
    required this.sourceLabel,
    required this.level,
    required this.resultCount,
    required this.elapsedMs,
    this.errorMessage,
  });
}

/// Jusou 资源数据库服务
/// 聚合本地索引、社区索引或远程 API adapter 后统一返回结果。
/// 远程源采用顺序 fallback：主源无结果时依次尝试备用地址。
class ResourceService {
  final ResourceAggregator _aggregator;
  final List<String> _remoteUrls;

  ResourceService({
    List<ResourceSource>? sources,
    ResourceAggregator? aggregator,
    bool? enableRemote,
    List<String>? remoteUrls,
  }) : _remoteUrls =
           remoteUrls ?? _resolveRemoteUrls(enableRemote: enableRemote),
       _aggregator =
           aggregator ??
           ResourceAggregator(
             sources:
                 sources ??
                 _buildSources(
                   enableRemote: enableRemote,
                   remoteUrls: remoteUrls,
                 ),
           );

  List<ResourceSource> get sources => _aggregator.sources;

  bool get hasConfiguredDataSources {
    for (final source in _aggregator.sources) {
      if (source is LocalIndexSource) {
        if (File(source.indexPath).existsSync()) return true;
        continue;
      }
      if (source is JsonFileResourceSource) {
        if (File(source.filePath).existsSync()) return true;
        continue;
      }
      if (source is RemoteSearchSource) {
        if (source.baseUrl.trim().isNotEmpty) return true;
        continue;
      }
      if (source is AlipansouSearchSource) {
        if (source.baseUrl.trim().isNotEmpty) return true;
        continue;
      }

      return true;
    }
    return false;
  }

  Future<({List<Resource> results, int total, int elapsedMs})> search(
    String query,
  ) async {
    final result = await searchDetailed(query);
    return (
      results: result.results,
      total: result.total,
      elapsedMs: result.elapsedMs,
    );
  }

  /// 搜索资源：主源 -> 备用源顺序 fallback
  Future<ResourceSearchResponse> searchDetailed(String query) async {
    final result = await _aggregator.search(query);

    if (_shouldTryBackup(result)) {
      for (int i = 1; i < _remoteUrls.length; i++) {
        final backupUrl = _remoteUrls[i].trim();
        if (backupUrl.isEmpty) continue;

        final backupAggregator = _buildAggregatorWithRemoteUrl(backupUrl);
        final backupResult = await backupAggregator.search(query);

        if (backupResult.total > 0) {
          return ResourceSearchResponse(
            results: backupResult.resources,
            total: backupResult.total,
            totalBeforeDedupe: backupResult.totalBeforeDedupe,
            elapsedMs: result.elapsedMs + backupResult.elapsedMs,
            sourceStatuses: _sourceStatusesFromResult(backupResult),
          );
        }
      }
    }

    return ResourceSearchResponse(
      results: result.resources,
      total: result.total,
      totalBeforeDedupe: result.totalBeforeDedupe,
      elapsedMs: result.elapsedMs,
      sourceStatuses: _sourceStatusesFromResult(result),
    );
  }

  Future<Resource> validateLink(
    Resource resource, {
    bool enableNetworkCheck = true,
  }) async {
    final validator = LinkValidator(enableNetworkCheck: enableNetworkCheck);
    final validation = await validator.validate(resource);
    return resource.copyWith(validation: validation);
  }

  /// 获取所有分类
  List<String> getCategories() => const ['全部', '电影', '电视剧', '纪录片', '综艺'];

  /// 获取最新资源
  List<Resource> getRecent({int limit = 20}) {
    final resources = _aggregator.sources.expand((source) {
      if (source is LocalIndexSource) return source.getAllLoaded();
      if (source is JsonFileResourceSource) return source.getAllLoaded();
      return const <Resource>[];
    }).toList();

    resources.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return resources.take(limit).toList();
  }

  static bool _shouldTryBackup(AggregatedSearchResult result) =>
      result.total == 0;

  ResourceAggregator _buildAggregatorWithRemoteUrl(String url) {
    final remoteSource = _remoteSourceForUrl(url);
    final baseSources = _aggregator.sources
        .where((s) => !s.id.startsWith('remote:'))
        .toList();
    return ResourceAggregator(sources: [remoteSource, ...baseSources]);
  }

  List<SourceStatus> _sourceStatusesFromResult(AggregatedSearchResult result) {
    return _aggregator.sources.map((source) {
      final successes = result.sourceResults.where((item) {
        return item.sourceId == source.id;
      }).toList();
      final failures = result.failures.where((item) {
        return item.sourceId == source.id;
      }).toList();
      final resultCount = successes.fold<int>(
        0,
        (total, item) => total + item.resources.length,
      );
      final elapsedMs = successes.fold<int>(
        0,
        (total, item) => total + item.elapsedMs,
      );
      final level = failures.isNotEmpty
          ? successes.isEmpty
                ? SourceStatusLevel.failure
                : SourceStatusLevel.partialFailure
          : resultCount > 0
          ? SourceStatusLevel.success
          : SourceStatusLevel.empty;

      return SourceStatus(
        sourceId: source.id,
        sourceLabel: source.label,
        level: level,
        resultCount: resultCount,
        elapsedMs: elapsedMs,
        errorMessage: failures.isEmpty ? null : failures.first.error.toString(),
      );
    }).toList();
  }

  static List<String> _resolveRemoteUrls({bool? enableRemote}) {
    final enable =
        enableRemote ??
        Platform.environment['JUSOU_ENABLE_REMOTE']?.toLowerCase() != 'false';
    if (!enable) return [];
    final envUrl = Platform.environment['JUSOU_REMOTE_URL'];
    return envUrl != null && envUrl.trim().isNotEmpty ? [envUrl.trim()] : [];
  }

  static List<ResourceSource> _buildSources({
    bool? enableRemote,
    List<String>? remoteUrls,
  }) {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dataDir = p.join(home, '.jusou');
    final sources = <ResourceSource>[
      LocalIndexSource(indexPath: p.join(dataDir, 'index.json')),
    ];

    final enable =
        enableRemote ??
        Platform.environment['JUSOU_ENABLE_REMOTE']?.toLowerCase() != 'false';
    if (enable) {
      List<String> urls;
      if (remoteUrls != null) {
        urls = remoteUrls;
      } else {
        final envUrl = Platform.environment['JUSOU_REMOTE_URL'];
        urls = envUrl != null && envUrl.trim().isNotEmpty
            ? [envUrl.trim()]
            : [];
      }
      // 只将第一个 URL 加入 aggregator，其余作为备用 fallback
      if (urls.isNotEmpty) {
        final trimmed = urls.first.trim();
        if (trimmed.isNotEmpty) {
          sources.add(_remoteSourceForUrl(trimmed));
        }
      }
    }

    final sourcesDir = Directory(p.join(dataDir, 'sources'));
    if (sourcesDir.existsSync()) {
      final files =
          sourcesDir
              .listSync()
              .whereType<File>()
              .where((file) => p.extension(file.path).toLowerCase() == '.json')
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final name = p.basenameWithoutExtension(file.path);
        sources.add(
          JsonFileResourceSource(
            filePath: file.path,
            sourceId: 'json_$name',
            sourceLabel: name,
          ),
        );
      }
    }

    return sources;
  }

  static ResourceSource _remoteSourceForUrl(String url) {
    if (AlipansouSearchSource.supports(url)) {
      return AlipansouSearchSource(baseUrl: url);
    }
    return RemoteSearchSource(baseUrl: url);
  }
}
