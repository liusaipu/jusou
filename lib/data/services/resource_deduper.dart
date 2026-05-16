import '../models/link_validation.dart';
import '../models/resource.dart';
import 'resource_text_normalizer.dart';
import 'share_link_parser.dart';

class ResourceDeduper {
  final ShareLinkParser _parser;
  final ResourceTextNormalizer _normalizer;

  const ResourceDeduper({
    ShareLinkParser parser = const ShareLinkParser(),
    ResourceTextNormalizer normalizer = const ResourceTextNormalizer(),
  }) : _parser = parser,
       _normalizer = normalizer;

  List<Resource> dedupe(List<Resource> resources) {
    final groups = <String, List<Resource>>{};

    for (final resource in resources) {
      final key = _dedupeKey(resource);
      groups.putIfAbsent(key, () => []).add(resource);
    }

    return groups.values.map(_mergeGroup).toList();
  }

  String _dedupeKey(Resource resource) {
    final info = _parser.parse(resource.shareUrl);
    if (info.isRecognizedShare && info.shareId != null) {
      return 'share:${info.provider}:${info.shareId}';
    }
    if (info.canonicalUrl != null) return 'url:${info.canonicalUrl}';

    final titleKey = _normalizer.titleKey(resource.title);
    if (titleKey.isNotEmpty &&
        resource.year != null &&
        resource.fileSize != null) {
      return 'meta:$titleKey:${resource.year}:${resource.fileSize}';
    }

    return 'resource:${resource.id}';
  }

  Resource _mergeGroup(List<Resource> group) {
    final sorted = [...group]..sort(_compareResourceQuality);
    final selected = sorted.first;
    final selectedPoster = selected.posterUrl?.trim();
    final posterUrl = selectedPoster != null && selectedPoster.isNotEmpty
        ? selectedPoster
        : group
              .map((resource) => resource.posterUrl?.trim())
              .whereType<String>()
              .firstWhere((url) => url.isNotEmpty, orElse: () => '');
    final sources =
        group
            .expand(
              (resource) => [
                resource.source.trim(),
                ...resource.mergedSources.map((source) => source.trim()),
              ],
            )
            .where((source) => source.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return selected.copyWith(
      posterUrl: posterUrl.isEmpty ? null : posterUrl,
      duplicateCount: group.length,
      mergedSources: sources,
    );
  }

  int _compareResourceQuality(Resource a, Resource b) {
    final scoreA = _candidateScore(a);
    final scoreB = _candidateScore(b);
    if (scoreA != scoreB) return scoreB.compareTo(scoreA);
    return b.updatedAt.compareTo(a.updatedAt);
  }

  int _candidateScore(Resource resource) {
    var score = 0;
    score +=
        resource.validation?.level.score ?? LinkValidationLevel.urlFormat.score;
    if (resource.year != null) score += 8;
    if (resource.fileSize != null) score += 6;
    if (resource.posterUrl != null) score += 4;
    if (resource.sharePwd == null || resource.sharePwd!.isEmpty) score += 3;
    score -= _normalizer.titlePollutionPenalty(resource.title);
    return score;
  }
}
