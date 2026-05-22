import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:pointycastle/export.dart';

import '../models/resource.dart';
import 'dio_factory.dart';
import 'resource_source.dart';

class AlipansouSearchSource implements ResourceSource {
  static const _cookieName = 'ck_ml_sea_';
  static const _challengeKey = '1234567812345678';

  final String baseUrl;
  final int maxResults;
  final bool resolveShareLinks;
  final Dio? _dio;

  const AlipansouSearchSource({
    this.baseUrl = 'https://alipansou.com',
    this.maxResults = 120,
    this.resolveShareLinks = true,
    Dio? dio,
  }) : _dio = dio;

  @override
  String get id => 'remote:alipansou';

  @override
  String get label => '猫狸盘搜';

  @override
  int get trustScore => 62;

  static bool supports(String url) {
    final uri = _uriFromUrl(url);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'alipansou.com' || host == 'www.alipansou.com';
  }

  @override
  Future<SourceSearchResult> search(String query) async {
    final trimmedQuery = query.trim();
    if (baseUrl.trim().isEmpty || trimmedQuery.isEmpty) {
      return SourceSearchResult(
        sourceId: id,
        sourceLabel: label,
        resources: const [],
        total: 0,
        elapsedMs: 0,
      );
    }

    final stopwatch = Stopwatch()..start();
    final response = await _getWithChallenge(
      '/search',
      queryParameters: {'k': trimmedQuery},
    );
    final html = response.data ?? '';
    final items = _parseSearchHtml(html).take(maxResults).toList();

    final resources = await Future.wait(
      items.map((item) => _resourceFromItem(item)),
    );

    stopwatch.stop();
    return SourceSearchResult(
      sourceId: id,
      sourceLabel: label,
      resources: resources,
      total: resources.length,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  Future<Response<String>> _getWithChallenge(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool followRedirects = true,
    Map<String, String>? headers,
  }) async {
    final response = await _get(
      path,
      queryParameters: queryParameters,
      followRedirects: followRedirects,
      headers: headers,
    );
    final body = response.data ?? '';
    if (!_isChallengePage(body)) return response;

    final challenge = _challengeToken(body);
    if (challenge == null) {
      throw const FormatException('alipansou.com 返回了访问校验页，但无法解析校验参数');
    }

    final cookieValue = challengeCookieValue(challenge);
    return _get(
      path,
      queryParameters: queryParameters,
      followRedirects: followRedirects,
      headers: {...?headers, 'Cookie': '$_cookieName=$cookieValue'},
    );
  }

  Future<Response<String>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool followRedirects = true,
    Map<String, String>? headers,
  }) {
    return _client.get<String>(
      path,
      queryParameters: queryParameters,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: followRedirects,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          ...?headers,
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );
  }

  Dio get _client {
    final existing = _dio;
    if (existing != null) return existing;

    return DioFactory.create(baseUrl: _normalizedBaseUrl);
  }

  List<_AlipansouItem> _parseSearchHtml(String html) {
    final items = <_AlipansouItem>[];
    final linkPattern = RegExp(
      r'''<a\s+[^>]*href=["'](/s/[^"']+)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    );

    for (final match in linkPattern.allMatches(html)) {
      final detailPath = match.group(1)?.trim();
      final block = match.group(2) ?? '';
      if (detailPath == null || detailPath.isEmpty) continue;

      final title = _extractTitle(block);
      if (title.isEmpty) continue;

      final metadataText = _cleanHtmlText(
        RegExp(
              r'''<template\s+#bottom>([\s\S]*?)</template>''',
              caseSensitive: false,
            ).firstMatch(block)?.group(1) ??
            block,
      );

      final token = detailPath.split('/').where((part) => part.isNotEmpty).last;
      items.add(
        _AlipansouItem(
          token: token,
          title: title,
          detailUrl: _absoluteUrl(detailPath),
          downloadUrl: _absoluteUrl('/cv/$token'),
          updatedAt: _parseDate(metadataText),
          format: _extractMetadata(metadataText, '格式'),
          fileSize: _normalizeFileSize(_extractMetadata(metadataText, '大小')),
        ),
      );
    }

    return items;
  }

  /// 优先用 DOM 解析标题，失败时 fallback 到正则。
  static String _extractTitle(String block) {
    try {
      final doc = parse(block);
      final el = doc.querySelector('[name="content-title"]');
      return _cleanHtmlText(el?.innerHtml ?? '');
    } on Object {
      final titleHtml = RegExp(
        r'''name=["']content-title["'][^>]*>([\s\S]*?)</div>''',
        caseSensitive: false,
      ).firstMatch(block)?.group(1);
      return _cleanHtmlText(titleHtml ?? '');
    }
  }

  Future<Resource> _resourceFromItem(_AlipansouItem item) async {
    final shareUrl = resolveShareLinks
        ? await _resolveShareUrl(item) ?? item.downloadUrl
        : item.downloadUrl;

    return Resource(
      id: 'remote_alipansou_${base64Url.encode(utf8.encode(shareUrl)).replaceAll('=', '')}',
      title: item.title,
      year: _extractYear(item.title),
      type: _guessType(item),
      episodeCount: _extractEpisodeCount(item.title),
      posterUrl: null,
      shareUrl: shareUrl,
      sharePwd: null,
      fileSize: item.fileSize,
      source: 'remote:alipansou',
      updatedAt: item.updatedAt ?? DateTime(1970),
      mergedSources: const ['remote:alipansou'],
    );
  }

  Future<String?> _resolveShareUrl(_AlipansouItem item) async {
    try {
      final response = await _getWithChallenge(
        '/cv/${item.token}',
        followRedirects: false,
        headers: {'Referer': item.detailUrl},
      );
      final status = response.statusCode ?? 0;
      final location = response.headers.value('location');
      if (status >= 300 && status < 400 && location != null) {
        return _absoluteUrl(location);
      }

      final body = response.data ?? '';
      final link = RegExp(
        r'''href=["'](https?://[^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(body)?.group(1);
      return link;
    } on Object {
      return null;
    }
  }

  static String challengeCookieValue(String challenge) {
    final key = Uint8List.fromList(utf8.encode(_challengeKey));
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), key),
          null,
        ),
      );
    final encrypted = cipher.process(
      Uint8List.fromList(utf8.encode(challenge)),
    );
    return encrypted.map((byte) {
      return byte.toRadixString(16).padLeft(2, '0');
    }).join();
  }

  static bool _isChallengePage(String html) {
    return html.contains('id="ori"') &&
        html.contains('start_load(') &&
        html.contains(_cookieName);
  }

  static String? _challengeToken(String html) {
    return RegExp(
      r'''start_load\(["']([^"']+)["']\)''',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
  }

  String _absoluteUrl(String pathOrUrl) {
    final parsed = Uri.tryParse(pathOrUrl);
    if (parsed != null && parsed.hasScheme) return pathOrUrl;
    return Uri.parse(_normalizedBaseUrl).resolve(pathOrUrl).toString();
  }

  String get _normalizedBaseUrl {
    final uri = _uriFromUrl(baseUrl);
    if (uri == null || uri.host.isEmpty) return 'https://alipansou.com';
    final normalized = Uri(scheme: uri.scheme, host: uri.host).toString();
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  static Uri? _uriFromUrl(String url) {
    var trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.contains('://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  static String _cleanHtmlText(String html) {
    return _decodeHtmlEntities(
      html
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
          final value = int.tryParse(match.group(1)!, radix: 16);
          return value == null ? match.group(0)! : String.fromCharCode(value);
        })
        .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
          final value = int.tryParse(match.group(1)!);
          return value == null ? match.group(0)! : String.fromCharCode(value);
        })
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static DateTime? _parseDate(String text) {
    final value = _extractMetadata(text, '时间');
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  static String? _extractMetadata(String text, String label) {
    final match = RegExp('$label[:：]\\s*([^\\s]+)').firstMatch(text);
    return match?.group(1)?.trim();
  }

  static String? _normalizeFileSize(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)\s*([KMGT]B?)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return value;

    final number = match.group(1)!;
    final unit = match.group(2)!.toUpperCase();
    final normalizedUnit = switch (unit) {
      'T' || 'TB' => 'TB',
      'G' || 'GB' => 'GB',
      'M' || 'MB' => 'MB',
      'K' || 'KB' => 'KB',
      _ => unit,
    };
    return '$number$normalizedUnit';
  }

  static String? _extractYear(String text) {
    return RegExp(r'(19\d{2}|20\d{2})').firstMatch(text)?.group(1);
  }

  static int? _extractEpisodeCount(String text) {
    final match = RegExp(r'(?:更新至|全)?\s*(\d+)\s*集').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static String _guessType(_AlipansouItem item) {
    final text = '${item.title} ${item.format ?? ''}'.toLowerCase();
    if (text.contains('电视剧') ||
        text.contains('短剧') ||
        text.contains('更新至') ||
        RegExp(r'\d+\s*集').hasMatch(text)) {
      return 'tv';
    }
    if (text.contains('综艺')) return 'variety';
    if (text.contains('纪录片')) return 'documentary';
    return 'movie';
  }
}

class _AlipansouItem {
  final String token;
  final String title;
  final String detailUrl;
  final String downloadUrl;
  final DateTime? updatedAt;
  final String? format;
  final String? fileSize;

  const _AlipansouItem({
    required this.token,
    required this.title,
    required this.detailUrl,
    required this.downloadUrl,
    required this.updatedAt,
    required this.format,
    required this.fileSize,
  });
}
