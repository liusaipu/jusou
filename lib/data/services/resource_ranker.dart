import '../models/link_validation.dart';
import '../models/resource.dart';
import 'resource_source.dart';
import 'resource_text_normalizer.dart';

class ResourceRanker {
  final ResourceTextNormalizer _normalizer;

  const ResourceRanker({
    ResourceTextNormalizer normalizer = const ResourceTextNormalizer(),
  }) : _normalizer = normalizer;

  List<Resource> rank(
    List<Resource> resources, {
    required String query,
    required List<ResourceSource> sources,
  }) {
    final trustScores = {
      for (final source in sources) source.id: source.trustScore,
      for (final source in sources) source.label: source.trustScore,
    };

    final ranked =
        resources.map((resource) {
          final score = _score(
            resource,
            query: query,
            trustScores: trustScores,
          );
          return resource.copyWith(qualityScore: score);
        }).toList()..sort((a, b) {
          final scoreCompare = b.qualityScore.compareTo(a.qualityScore);
          if (scoreCompare != 0) return scoreCompare;
          return b.updatedAt.compareTo(a.updatedAt);
        });

    return ranked;
  }

  double _score(
    Resource resource, {
    required String query,
    required Map<String, int> trustScores,
  }) {
    var score = 0.0;

    score += _normalizer.keywordMatchScore(query, resource.title);
    score +=
        (resource.validation?.level ?? LinkValidationLevel.urlFormat).score *
        0.45;
    score += _sourceTrust(resource, trustScores) * 0.2;

    if (resource.year != null) score += 5;
    if (resource.fileSize != null) score += 4;
    if (resource.episodeCount != null) score += 3;
    if (resource.posterUrl != null) score += 2;
    if (resource.sharePwd != null && resource.sharePwd!.isNotEmpty) score -= 2;

    score += _freshnessScore(resource.updatedAt);
    final duplicateBoost = resource.duplicateCount - 1;
    score +=
        (duplicateBoost < 0
            ? 0
            : duplicateBoost > 4
            ? 4
            : duplicateBoost) *
        4;
    score -= _normalizer.titlePollutionPenalty(resource.title);

    return score;
  }

  int _sourceTrust(Resource resource, Map<String, int> trustScores) {
    final candidates = [resource.source, ...resource.mergedSources];

    var score = 45;
    for (final candidate in candidates) {
      final trust = trustScores[candidate];
      if (trust != null && trust > score) score = trust;
    }
    return score;
  }

  double _freshnessScore(DateTime updatedAt) {
    final days = DateTime.now().difference(updatedAt).inDays;
    if (days <= 7) return 8;
    if (days <= 30) return 5;
    if (days <= 180) return 2;
    return 0;
  }
}
