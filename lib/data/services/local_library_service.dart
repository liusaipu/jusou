import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;

import '../models/link_validation.dart';
import '../models/local_library.dart';
import '../models/resource.dart';
import 'resource_key.dart';

class LocalLibraryService {
  static const _boxName = 'jusou_local_library';
  static const _favoritesKey = 'favorites';
  static const _recentlyOpenedKey = 'recently_opened';
  static const _searchHistoryKey = 'search_history';
  static const _invalidReportsKey = 'invalid_reports';
  static const _settingsKey = 'settings';
  static const _validationCacheKey = 'validation_cache';
  static const _lastAutoValidationKey = 'last_auto_validation';
  static const autoValidationIntervalDays = 7;
  static const autoValidationSampleSize = 20;

  final bool enablePersistence;
  Box<dynamic>? _box;
  bool _initialized = false;
  final Map<String, dynamic> _memoryStore = {};

  LocalLibraryService({this.enablePersistence = true});

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!enablePersistence) return;

    try {
      await Hive.initFlutter();
      _box = await Hive.openBox<dynamic>(_boxName);
    } on Object {
      _box = null;
    }
  }

  Future<LocalLibrarySnapshot> snapshot() async {
    await initialize();
    return LocalLibrarySnapshot(
      favorites: _readResourceList(_favoritesKey),
      recentlyOpened: _readResourceList(_recentlyOpenedKey),
      searchHistory: _readHistory(),
      invalidReports: _readInvalidReports(),
      settings: _readSettings(),
    );
  }

  Future<bool> toggleFavorite(Resource resource) async {
    await initialize();
    final favorites = _readResourceList(_favoritesKey);
    final existingIndex = favorites.indexWhere(
      (item) => _resourceKey(item) == _resourceKey(resource),
    );

    if (existingIndex >= 0) {
      favorites.removeAt(existingIndex);
      await _writeResourceList(_favoritesKey, favorites);
      return false;
    }

    await _writeResourceList(
      _favoritesKey,
      [resource, ...favorites].take(100).toList(),
    );
    return true;
  }

  Future<void> recordOpened(Resource resource) async {
    await initialize();
    final items = _readResourceList(
      _recentlyOpenedKey,
    ).where((item) => _resourceKey(item) != _resourceKey(resource)).toList();
    await _writeResourceList(
      _recentlyOpenedKey,
      [resource, ...items].take(30).toList(),
    );
  }

  Future<void> recordSearch(String query, int total) async {
    await initialize();
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;

    final items = _readHistory()
        .where((item) => item.query != normalizedQuery)
        .toList();
    final next = [
      SearchHistoryEntry(
        query: normalizedQuery,
        total: total,
        searchedAt: DateTime.now(),
      ),
      ...items,
    ].take(20).toList();
    await _write(_searchHistoryKey, next.map((item) => item.toJson()).toList());
  }

  Future<void> reportInvalid(
    Resource resource, {
    String reason = '用户标记失效',
  }) async {
    await initialize();
    final key = _resourceKey(resource);
    final reports = _readInvalidReports()
        .where((item) => _invalidReportKey(item) != key)
        .toList();
    final next = [
      InvalidLinkReport(
        title: resource.title,
        shareUrl: resource.shareUrl,
        sharePwd: resource.sharePwd,
        reason: reason,
        reportedAt: DateTime.now(),
      ),
      ...reports,
    ].take(100).toList();
    await _write(
      _invalidReportsKey,
      next.map((item) => item.toJson()).toList(),
    );
  }

  Future<void> cacheValidation(Resource resource) async {
    await initialize();
    final validation = resource.validation;
    if (validation == null) return;

    final cache = _readValidationCache();
    cache[_resourceKey(resource)] = validation.toJson();
    await _write(_validationCacheKey, cache);
  }

  Future<void> cacheValidations(Iterable<Resource> resources) async {
    await initialize();
    final cache = _readValidationCache();
    var changed = false;
    for (final resource in resources) {
      final validation = resource.validation;
      if (validation == null) continue;
      cache[_resourceKey(resource)] = validation.toJson();
      changed = true;
    }
    if (changed) await _write(_validationCacheKey, cache);
  }

  Future<void> updateSettings(LibrarySettings settings) async {
    await initialize();
    await _write(_settingsKey, settings.toJson());
  }

  Future<String> exportConfig({DateTime? exportedAt}) async {
    await initialize();
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(
      _readSettings().toConfigJson(exportedAt: exportedAt),
    );
  }

  Future<LibrarySettings> importConfigFile(String path) async {
    await initialize();
    final content = await File(path).readAsString();
    return importConfig(content);
  }

  Future<LibrarySettings> importConfig(String content) async {
    await initialize();
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('配置必须是 JSON 对象');
    }
    final settings = LibrarySettings.fromConfigJson(
      Map<String, dynamic>.from(decoded),
    );
    await updateSettings(settings);
    return settings;
  }

  Future<File> writeConfigFile({LibrarySettings? settings}) async {
    return writeConfigFileAt(
      p.join(
        Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.',
        '.jusou',
        'config.json',
      ),
      settings: settings,
    );
  }

  Future<File> writeConfigFileAt(
    String path, {
    LibrarySettings? settings,
  }) async {
    await initialize();
    final file = File(path);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final source = settings ?? _readSettings();
    await file.writeAsString(encoder.convert(source.toConfigJson()));
    return file;
  }

  Future<void> clearHistory() async {
    await initialize();
    await _write(_searchHistoryKey, const []);
  }

  Future<void> clearRecentlyOpened() async {
    await initialize();
    await _write(_recentlyOpenedKey, const []);
  }

  /// 检查是否距离上次自动验证已超过 [autoValidationIntervalDays] 天。
  bool shouldAutoValidate() {
    final last = _read(_lastAutoValidationKey);
    if (last == null) return true;
    final lastDate = DateTime.tryParse(last.toString());
    if (lastDate == null) return true;
    return DateTime.now().difference(lastDate).inDays >= autoValidationIntervalDays;
  }

  /// 记录本次自动验证的时间戳。
  Future<void> recordAutoValidation() async {
    await initialize();
    await _write(_lastAutoValidationKey, DateTime.now().toIso8601String());
  }

  /// 返回收藏和最近打开中需要去重合并后的候选资源，用于自动抽样验证。
  List<Resource> getCandidatesForAutoValidation() {
    final favorites = _readResourceList(_favoritesKey);
    final recent = _readResourceList(_recentlyOpenedKey);
    final seen = <String>{};
    final candidates = <Resource>[];
    for (final resource in [...favorites, ...recent]) {
      final key = _resourceKey(resource);
      if (seen.contains(key)) continue;
      seen.add(key);
      candidates.add(resource);
      if (candidates.length >= autoValidationSampleSize) break;
    }
    return candidates;
  }

  Future<List<Resource>> applyCachedValidation(List<Resource> resources) async {
    await initialize();
    final cache = _readValidationCache();
    return resources.map((resource) {
      final cached = ResourceKey.candidatesForResource(resource)
          .map((key) => cache[key])
          .firstWhere((value) => value != null, orElse: () => null);
      if (cached is Map<String, dynamic>) {
        return resource.copyWith(
          validation: LinkValidationResult.fromJson(cached),
        );
      }
      if (cached is Map) {
        return resource.copyWith(
          validation: LinkValidationResult.fromJson(
            Map<String, dynamic>.from(cached),
          ),
        );
      }
      return resource;
    }).toList();
  }

  List<Resource> _readResourceList(String key) {
    final value = _read(key);
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Resource.fromJson(Map<String, dynamic>.from(item)))
        .where(
          (resource) =>
              resource.title.isNotEmpty && resource.shareUrl.isNotEmpty,
        )
        .toList();
  }

  List<SearchHistoryEntry> _readHistory() {
    final value = _read(_searchHistoryKey);
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) =>
              SearchHistoryEntry.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.query.isNotEmpty)
        .toList();
  }

  List<InvalidLinkReport> _readInvalidReports() {
    final value = _read(_invalidReportsKey);
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => InvalidLinkReport.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.shareUrl.isNotEmpty)
        .toList();
  }

  LibrarySettings _readSettings() {
    final value = _read(_settingsKey);
    if (value is Map<String, dynamic>) return LibrarySettings.fromJson(value);
    if (value is Map) {
      return LibrarySettings.fromJson(Map<String, dynamic>.from(value));
    }
    return const LibrarySettings();
  }

  Map<String, dynamic> _readValidationCache() {
    final value = _read(_validationCacheKey);
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Future<void> _writeResourceList(String key, List<Resource> resources) async {
    await _write(key, resources.map((resource) => resource.toJson()).toList());
  }

  dynamic _read(String key) => _box?.get(key) ?? _memoryStore[key];

  Future<void> _write(String key, dynamic value) async {
    final box = _box;
    if (box != null) {
      await box.put(key, value);
      return;
    }
    _memoryStore[key] = value;
  }

  String _resourceKey(Resource resource) {
    return ResourceKey.forResource(resource);
  }

  String _invalidReportKey(InvalidLinkReport report) {
    return ResourceKey.forShare(id: report.shareUrl, shareUrl: report.shareUrl);
  }
}
