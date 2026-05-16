import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/local_library.dart';
import '../models/resource.dart';
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
/// 聚合本地索引、社区索引或远程 API adapter 后统一返回结果
class ResourceService {
  final ResourceAggregator _aggregator;

  ResourceService({
    List<ResourceSource>? sources,
    ResourceAggregator? aggregator,
    bool? enableRemote,
    String? remoteUrl,
  }) : _aggregator =
           aggregator ??
           ResourceAggregator(
             sources:
                 sources ??
                 _defaultSources(
                   enableRemoteOverride: enableRemote,
                   remoteUrlOverride: remoteUrl,
                 ),
           );

  List<ResourceSource> get sources => _aggregator.sources;

  /// 搜索资源：多来源查询 -> 链接校验 -> 去重 -> 排序
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

  /// 搜索资源并返回来源命中、失败和去重前数量，供 UI 展示来源状态。
  Future<ResourceSearchResponse> searchDetailed(String query) async {
    final result = await _aggregator.search(query);
    return ResourceSearchResponse(
      results: result.resources,
      total: result.total,
      totalBeforeDedupe: result.totalBeforeDedupe,
      elapsedMs: result.elapsedMs,
      sourceStatuses: _sourceStatuses(result),
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

  static List<ResourceSource> _defaultSources({
    bool? enableRemoteOverride,
    String? remoteUrlOverride,
  }) {
    final home = Platform.environment['HOME'] ?? '.';
    final dataDir = p.join(home, '.jusou');
    final sources = <ResourceSource>[
      LocalIndexSource(indexPath: p.join(dataDir, 'index.json')),
    ];

    final enableRemote =
        enableRemoteOverride ??
        Platform.environment['JUSOU_ENABLE_REMOTE']?.toLowerCase() != 'false';
    if (enableRemote) {
      final remoteUrl =
          remoteUrlOverride ??
          Platform.environment['JUSOU_REMOTE_URL'] ??
          LibrarySettings.defaultRemoteUrl;
      if (remoteUrl.isNotEmpty) {
        sources.add(RemoteSearchSource(baseUrl: remoteUrl));
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

  List<SourceStatus> _sourceStatuses(AggregatedSearchResult result) {
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

  /// 获取所有分类
  List<String> getCategories() => const ['全部', '电影', '电视剧', '纪录片', '综艺'];

  /// 获取最新资源
  List<Resource> getRecent({int limit = 20}) {
    final resources = _aggregator.sources.expand((source) {
      if (source is LocalIndexSource) return source.getAllLoaded();
      if (source is JsonFileResourceSource) return source.getAllLoaded();
      return const <Resource>[];
    }).toList();

    resources.sort((a, b) => (b.updatedAt ?? DateTime(1970))
        .compareTo(a.updatedAt ?? DateTime(1970)));
    return resources.take(limit).toList();
  }
}
