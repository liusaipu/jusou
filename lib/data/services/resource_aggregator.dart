import 'package:equatable/equatable.dart';

import '../models/resource.dart';
import 'link_validator.dart';
import 'resource_deduper.dart';
import 'resource_ranker.dart';
import 'resource_source.dart';
import 'resource_text_normalizer.dart';

class AggregatedSearchResult extends Equatable {
  final List<Resource> resources;
  final int totalBeforeDedupe;
  final int total;
  final int elapsedMs;
  final List<SourceSearchResult> sourceResults;
  final List<SourceSearchFailure> failures;

  const AggregatedSearchResult({
    required this.resources,
    required this.totalBeforeDedupe,
    required this.total,
    required this.elapsedMs,
    required this.sourceResults,
    required this.failures,
  });

  @override
  List<Object?> get props {
    return [
      resources,
      totalBeforeDedupe,
      total,
      elapsedMs,
      sourceResults,
      failures,
    ];
  }
}

class ResourceAggregator {
  final List<ResourceSource> sources;
  final LinkValidator linkValidator;
  final ResourceDeduper deduper;
  final ResourceRanker ranker;
  final ResourceTextNormalizer normalizer;

  const ResourceAggregator({
    required this.sources,
    this.linkValidator = const _DefaultLinkValidator(),
    this.deduper = const ResourceDeduper(),
    this.ranker = const ResourceRanker(),
    this.normalizer = const ResourceTextNormalizer(),
  });

  Future<AggregatedSearchResult> search(String query) async {
    final stopwatch = Stopwatch()..start();
    final normalizedQuery = query.trim();

    if (normalizedQuery.isEmpty || sources.isEmpty) {
      stopwatch.stop();
      return AggregatedSearchResult(
        resources: const [],
        totalBeforeDedupe: 0,
        total: 0,
        elapsedMs: stopwatch.elapsedMilliseconds,
        sourceResults: const [],
        failures: const [],
      );
    }

    final queryVariants = normalizer.searchQueryVariants(normalizedQuery);
    final settled = await Future.wait([
      for (final source in sources)
        for (final queryVariant in queryVariants)
          _searchSource(source, queryVariant),
    ]);

    final sourceResults = settled
        .map((result) => result.result)
        .whereType<SourceSearchResult>()
        .toList();
    final failures = settled
        .map((result) => result.failure)
        .whereType<SourceSearchFailure>()
        .toList();

    final allResources = sourceResults
        .expand(
          (result) => result.resources.map((resource) {
            final mergedSources = {
              ...resource.mergedSources,
              result.sourceId,
            }.toList();
            return resource.copyWith(
              source: resource.source.isEmpty
                  ? result.sourceId
                  : resource.source,
              mergedSources: mergedSources,
            );
          }),
        )
        .toList();

    final validated = await linkValidator.validateAll(allResources);
    final deduped = deduper.dedupe(validated);
    final ranked = ranker.rank(
      deduped,
      query: normalizedQuery,
      sources: sources,
    );

    stopwatch.stop();
    return AggregatedSearchResult(
      resources: ranked,
      totalBeforeDedupe: allResources.length,
      total: ranked.length,
      elapsedMs: stopwatch.elapsedMilliseconds,
      sourceResults: sourceResults,
      failures: failures,
    );
  }

  Future<_SettledSearchResult> _searchSource(
    ResourceSource source,
    String query,
  ) async {
    try {
      return _SettledSearchResult.success(await source.search(query));
    } on Object catch (error) {
      return _SettledSearchResult.failure(
        SourceSearchFailure(
          sourceId: source.id,
          sourceLabel: source.label,
          error: error,
        ),
      );
    }
  }
}

/// 搜索管线刻意不开启网络校验：一次搜索结果可能上百条，逐个发请求会拖慢首屏并触发风控。
/// 此处仅做格式/识别级判断；网络可达性校验由 [ResourceService.validateLink]
/// 或 LocalLibraryService 的自动校验任务在用户主动触发时调用。
class _DefaultLinkValidator extends LinkValidator {
  const _DefaultLinkValidator() : super();
}

class _SettledSearchResult {
  final SourceSearchResult? result;
  final SourceSearchFailure? failure;

  const _SettledSearchResult.success(this.result) : failure = null;

  const _SettledSearchResult.failure(this.failure) : result = null;
}
