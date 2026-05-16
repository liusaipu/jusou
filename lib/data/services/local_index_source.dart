import 'dart:convert';
import 'dart:io';

import '../models/resource.dart';
import 'resource_source.dart';
import 'resource_text_normalizer.dart';

class LocalIndexSource implements ResourceSource {
  final String indexPath;
  final ResourceTextNormalizer _normalizer;

  List<Resource>? _resources;

  LocalIndexSource({
    required this.indexPath,
    ResourceTextNormalizer normalizer = const ResourceTextNormalizer(),
  }) : _normalizer = normalizer;

  @override
  String get id => 'local_index';

  @override
  String get label => '本地索引';

  @override
  int get trustScore => 72;

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

    final file = File(indexPath);
    if (!file.existsSync()) {
      _resources = [];
      return _resources!;
    }

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) {
        _resources = [];
        return _resources!;
      }

      _resources = decoded
          .whereType<Map<String, dynamic>>()
          .map(Resource.fromJson)
          .where((resource) {
            return resource.title.isNotEmpty && resource.shareUrl.isNotEmpty;
          })
          .toList();
    } on Object {
      _resources = [];
    }

    return _resources!;
  }

  List<Resource> getAllLoaded() => _resources ?? const [];
}
