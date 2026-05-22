import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/resource.dart';
import 'dio_factory.dart';
import 'resource_source.dart';

class RemoteSearchSource implements ResourceSource {
  final String baseUrl;
  final int maxResults;

  RemoteSearchSource({this.baseUrl = '', this.maxResults = 120});

  @override
  String get id => 'remote:generic';

  @override
  String get label => '远程搜索';

  @override
  int get trustScore => 64;

  @override
  Future<SourceSearchResult> search(String query) async {
    if (baseUrl.isEmpty) {
      return SourceSearchResult(
        sourceId: id,
        sourceLabel: label,
        resources: const [],
        total: 0,
        elapsedMs: 0,
      );
    }

    final dio = DioFactory.create(baseUrl: baseUrl);

    final stopwatch = Stopwatch()..start();
    final response = await dio.get<dynamic>(
      '/api/search',
      queryParameters: {'kw': query.trim()},
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final body = _decodeResponse(response.data);
    final resources = _parseResources(body).take(maxResults).toList();

    stopwatch.stop();
    return SourceSearchResult(
      sourceId: id,
      sourceLabel: label,
      resources: resources,
      total: resources.length,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  Map<String, dynamic> _decodeResponse(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.trim().isNotEmpty) {
      if (_looksLikeHtml(data)) {
        throw const FormatException(
          '远程地址返回的是网页，不是 Jusou JSON API。请使用 /api/search?kw=... 兼容接口，或为该站点添加专用适配器。',
        );
      }
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return const {};
  }

  bool _looksLikeHtml(String text) {
    final trimmed = text.trimLeft().toLowerCase();
    return trimmed.startsWith('<!doctype html') ||
        trimmed.startsWith('<html') ||
        trimmed.contains('<body');
  }

  Iterable<Resource> _parseResources(Map<String, dynamic> body) sync* {
    final data = body['data'];
    if (data is! Map<String, dynamic>) return;

    final mergedByType = data['merged_by_type'];
    if (mergedByType is Map<String, dynamic>) {
      for (final entry in mergedByType.entries) {
        final provider = entry.key;
        final items = entry.value;
        if (items is! List) continue;

        for (final item in items.whereType<Map<String, dynamic>>()) {
          final resource = _resourceFromItem(provider, item);
          if (resource != null) yield resource;
        }
      }
      return;
    }

    final results = data['results'] ?? data['items'];
    if (results is List) {
      for (final item in results.whereType<Map<String, dynamic>>()) {
        final resource = _resourceFromItem('remote', item);
        if (resource != null) yield resource;
      }
    }
  }

  Resource? _resourceFromItem(String provider, Map<String, dynamic> item) {
    final shareUrl = _stringValue(item['url'] ?? item['share_url']);
    if (shareUrl == null || shareUrl.isEmpty) return null;

    final note = _stringValue(item['note'] ?? item['title']) ?? shareUrl;
    final title = _cleanTitle(note);
    if (title.isEmpty) return null;

    final source = _stringValue(item['source']) ?? provider;
    final images = item['images'];
    final posterUrl = images is List && images.isNotEmpty
        ? _stringValue(images.first)
        : null;

    return Resource(
      id: 'remote_${base64Url.encode(utf8.encode(shareUrl)).replaceAll('=', '')}',
      title: title,
      year: _extractYear(note),
      type: _guessType(note),
      episodeCount: _extractEpisodeCount(note),
      posterUrl: posterUrl,
      shareUrl: shareUrl,
      sharePwd: _stringValue(item['password']),
      fileSize: _extractFileSize(note),
      source: 'remote:$source',
      updatedAt: _parseDateTime(item['datetime']),
      mergedSources: const ['remote:generic'],
    );
  }

  String _cleanTitle(String note) {
    var text = note
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(RegExp(r'^资源标题[:：]\s*'), '')
        .replaceFirst(RegExp(r'^【标题】[:：]\s*'), '')
        .trim();

    for (final separator in ['📁', '🏷', '💾', '⬇️', '|']) {
      final index = text.indexOf(separator);
      if (index > 0) {
        text = text.substring(0, index).trim();
      }
    }

    if (text.startsWith('#')) {
      final match = RegExp(r'^[#\S]+\s*(.+)$').firstMatch(text);
      text = match?.group(1)?.trim() ?? text;
    }

    if (text.length > 80) {
      text = '${text.substring(0, 80).trim()}...';
    }
    return text;
  }

  String _guessType(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('电视剧') ||
        lower.contains('国产剧') ||
        lower.contains('短剧') ||
        lower.contains('集全') ||
        RegExp(r'\d+\s*集').hasMatch(lower)) {
      return 'tv';
    }
    return 'movie';
  }

  String? _extractYear(String text) {
    return RegExp(r'(19\d{2}|20\d{2})').firstMatch(text)?.group(1);
  }

  int? _extractEpisodeCount(String text) {
    final match = RegExp(r'(\d+)\s*集').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String? _extractFileSize(String text) {
    return RegExp(
      r'\d+(?:\.\d+)?\s*(?:GB|MB|TB)',
      caseSensitive: false,
    ).firstMatch(text)?.group(0);
  }

  DateTime _parseDateTime(dynamic value) {
    final text = _stringValue(value);
    if (text == null || text.startsWith('0001-')) return DateTime(1970);
    return DateTime.tryParse(text) ?? DateTime(1970);
  }

  String? _stringValue(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
