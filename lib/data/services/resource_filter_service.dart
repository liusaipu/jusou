import '../models/link_validation.dart';
import '../models/resource.dart';
import 'share_link_parser.dart';

enum SortMode {
  relevance('相关度'),
  latest('最新'),
  multiSource('多源可信'),
  fileSize('文件大小');

  const SortMode(this.label);
  final String label;
}

enum TypeFilter {
  all('全部类型', null),
  movie('电影', 'movie'),
  tv('剧集', 'tv'),
  documentary('纪录片', 'documentary'),
  variety('综艺', 'variety');

  const TypeFilter(this.label, this.value);
  final String label;
  final String? value;
}

enum CodeFilter {
  all('提取码不限'),
  withCode('需要提取码'),
  withoutCode('无提取码');

  const CodeFilter(this.label);
  final String label;
}

enum ValidationFilter {
  all('校验不限'),
  verified('已识别'),
  reachable('可访问'),
  unchecked('未校验'),
  invalid('已失效');

  const ValidationFilter(this.label);
  final String label;
}

class FilterCriteria {
  final String provider;
  final String year;
  final SortMode sortMode;
  final TypeFilter typeFilter;
  final CodeFilter codeFilter;
  final ValidationFilter validationFilter;
  final bool onlyMergedSources;

  const FilterCriteria({
    this.provider = 'all',
    this.year = 'all',
    this.sortMode = SortMode.relevance,
    this.typeFilter = TypeFilter.all,
    this.codeFilter = CodeFilter.all,
    this.validationFilter = ValidationFilter.all,
    this.onlyMergedSources = false,
  });
}

class ResourceFilterService {
  static const _allProviderKey = 'all';
  static const _allYearKey = 'all';
  static const _parser = ShareLinkParser();

  const ResourceFilterService();

  List<Resource> apply(List<Resource> resources, FilterCriteria criteria) {
    final filtered = resources.where((resource) {
      if (criteria.provider != _allProviderKey &&
          _providerKey(resource) != criteria.provider) {
        return false;
      }
      if (criteria.typeFilter != TypeFilter.all &&
          resource.type != _typeValue(criteria.typeFilter)) {
        return false;
      }
      if (criteria.year != _allYearKey && resource.year != criteria.year) {
        return false;
      }
      if (criteria.codeFilter == CodeFilter.withCode &&
          !_hasShareCode(resource)) {
        return false;
      }
      if (criteria.codeFilter == CodeFilter.withoutCode &&
          _hasShareCode(resource)) {
        return false;
      }
      if (criteria.onlyMergedSources && resource.duplicateCount <= 1) {
        return false;
      }
      return _matchesValidation(resource, criteria.validationFilter);
    }).toList();

    switch (criteria.sortMode) {
      case SortMode.relevance:
        return filtered;
      case SortMode.latest:
        return filtered..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case SortMode.multiSource:
        return filtered..sort((a, b) {
          final duplicateCompare = b.duplicateCount.compareTo(a.duplicateCount);
          if (duplicateCompare != 0) return duplicateCompare;
          return b.qualityScore.compareTo(a.qualityScore);
        });
      case SortMode.fileSize:
        return filtered
          ..sort((a, b) => _fileSizeBytes(b).compareTo(_fileSizeBytes(a)));
    }
  }

  static String _providerKey(Resource resource) {
    final info = _parser.parse(resource.shareUrl);
    return info.isRecognizedShare
        ? info.provider
        : ShareLinkParser.unknownProvider;
  }

  static String? _typeValue(TypeFilter filter) {
    return switch (filter) {
      TypeFilter.movie => 'movie',
      TypeFilter.tv => 'tv',
      TypeFilter.documentary => 'documentary',
      TypeFilter.variety => 'variety',
      TypeFilter.all => null,
    };
  }

  static bool _hasShareCode(Resource resource) {
    return resource.sharePwd != null && resource.sharePwd!.trim().isNotEmpty;
  }

  static bool _matchesValidation(
    Resource resource,
    ValidationFilter filter,
  ) {
    final level = resource.validation?.level;
    return switch (filter) {
      ValidationFilter.all => true,
      ValidationFilter.verified =>
        level != null && level != LinkValidationLevel.invalid,
      ValidationFilter.reachable =>
        level != null && level.score >= LinkValidationLevel.httpReachable.score,
      ValidationFilter.unchecked => level == null,
      ValidationFilter.invalid => level == LinkValidationLevel.invalid,
    };
  }

  static int _fileSizeBytes(Resource resource) {
    final text = resource.fileSize?.trim();
    if (text == null || text.isEmpty) return -1;

    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(TB|GB|MB|KB|B)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return -1;

    final value = double.tryParse(match.group(1) ?? '');
    if (value == null) return -1;

    final unit = (match.group(2) ?? '').toUpperCase();
    final multiplier = switch (unit) {
      'TB' => 1024 * 1024 * 1024 * 1024,
      'GB' => 1024 * 1024 * 1024,
      'MB' => 1024 * 1024,
      'KB' => 1024,
      _ => 1,
    };
    return (value * multiplier).round();
  }
}
