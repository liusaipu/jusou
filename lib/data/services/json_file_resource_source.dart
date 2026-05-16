import 'dart:convert';
import 'dart:io';

import '../models/resource.dart';
import 'resource_source.dart';
import 'resource_text_normalizer.dart';

class JsonFileResourceSource implements ResourceSource {
  final String filePath;
  final String sourceId;
  final String sourceLabel;
  final int sourceTrustScore;
  final ResourceTextNormalizer _normalizer;

  List<Resource>? _resources;

  JsonFileResourceSource({
    required this.filePath,
    required this.sourceId,
    required this.sourceLabel,
    this.sourceTrustScore = 55,
    ResourceTextNormalizer normalizer = const ResourceTextNormalizer(),
  }) : _normalizer = normalizer;

  @override
  String get id => sourceId;

  @override
  String get label => sourceLabel;

  @override
  int get trustScore => sourceTrustScore;

  @override
  Future<SourceSearchResult> search(String query) async {
    final stopwatch = Stopwatch()..start();
    final resources = await _load();
    final q = query.toLowerCase().trim();
    final queryKey = _normalizer.titleKey(query);

    final results = resources.where((resource) {
      final title = resource.title.toLowerCase();
      final titleKey = _normalizer.titleKey(resource.title);
      return title.contains(q) ||
          (queryKey.isNotEmpty && titleKey.contains(queryKey)) ||
          (resource.year?.contains(q) ?? false);
    }).toList();

    stopwatch.stop();
    return SourceSearchResult(
      sourceId: id,
      sourceLabel: label,
      resources: results,
      total: results.length,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  Future<List<Resource>> _load() async {
    if (_resources != null) return _resources!;

    final file = File(filePath);
    if (!file.existsSync()) {
      _resources = [];
      return _resources!;
    }

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      final records = _recordsFrom(decoded);
      _resources = records.map(Resource.fromJson).where((resource) {
        return resource.title.isNotEmpty && resource.shareUrl.isNotEmpty;
      }).toList();
    } on Object {
      _resources = [];
    }

    return _resources!;
  }

  Iterable<Map<String, dynamic>> _recordsFrom(dynamic decoded) {
    if (decoded is List) return decoded.whereType<Map<String, dynamic>>();
    if (decoded is Map<String, dynamic>) {
      final resources =
          decoded['resources'] ?? decoded['items'] ?? decoded['results'];
      if (resources is List) return resources.whereType<Map<String, dynamic>>();
    }
    return const [];
  }

  List<Resource> getAllLoaded() => _resources ?? const [];
}
