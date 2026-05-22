import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../models/resource.dart';
import 'dio_factory.dart';

/// Telegram 公开频道爬虫。
///
/// 抓取 t.me/s/{channel} 页面，提取网盘分享链接，输出到 ~/.jusou/sources/telegram.json。
/// 不依赖 Node.js，直接使用 Dart/Dio 进行 HTTP 请求。
class TelegramCrawler {
  static const _maxMessagesPerChannel = 30;
  static const _requestDelayMs = 2000;
  static const _concurrency = 3;

  final Dio _dio;
  final String _outputDir;

  TelegramCrawler({Dio? dio, String? outputDir})
    : _dio = dio ?? DioFactory.create(),
      _outputDir = outputDir ?? _defaultOutputDir;

  /// 运行爬虫，返回 (新增资源数, 新增频道数, 错误信息)。
  Future<(int newResources, int newChannels, String? error)> run(
    List<String> channels,
  ) async {
    if (channels.isEmpty) return (0, 0, '没有配置 Telegram 频道');

    try {
      final existing = await _loadExistingOutput();
      final seenUrls = {for (final r in existing) r.shareUrl};
      final allNewChannels = <String>{};
      var totalNew = 0;

      for (var i = 0; i < channels.length; i += _concurrency) {
        final batch = channels.skip(i).take(_concurrency);
        final futures = batch.map((name) => _crawlChannel(name));
        final results = await Future.wait(futures);

        for (final result in results) {
          for (final resource in result.resources) {
            if (!seenUrls.contains(resource.shareUrl)) {
              seenUrls.add(resource.shareUrl);
              existing.add(resource);
              totalNew++;
            }
          }
          allNewChannels.addAll(result.newChannels);
        }

        if (i + _concurrency < channels.length) {
          await Future.delayed(const Duration(milliseconds: _requestDelayMs));
        }
      }

      await _saveOutput(existing);

      final currentChannels = Set<String>.from(channels);
      final addedChannels = allNewChannels
          .where((c) => !currentChannels.contains(c))
          .toList();

      return (totalNew, addedChannels.length, null);
    } on Object catch (e) {
      return (0, 0, e.toString());
    }
  }

  Future<_CrawlResult> _crawlChannel(String name) async {
    try {
      final response = await _dio.get<String>(
        'https://t.me/s/$name',
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': 'Mozilla/5.0'},
        ),
      );
      final html = response.data ?? '';
      final messages = _extractMessageBodies(html);
      final newChannels = _extractChannelNames(html);

      final resources = <Resource>[];
      final msgCount =
          messages.length > _maxMessagesPerChannel
              ? _maxMessagesPerChannel
              : messages.length;

      for (var i = 0; i < msgCount; i++) {
        final text = messages[i];
        final links = _extractShareLinks(text);
        if (links.isEmpty) continue;
        final title = _extractTitle(text);
        for (final link in links) {
          resources.add(
            Resource(
              id:
                  'tg_${base64Url.encode(utf8.encode(link.url)).replaceAll('=', '').substring(0, 40)}',
              title: title,
              type: 'movie',
              shareUrl: link.url,
              sharePwd: link.sharePwd,
              source: 'tg:$name',
              updatedAt: DateTime.now(),
              mergedSources: const ['tg'],
            ),
          );
        }
      }

      return _CrawlResult(resources: resources, newChannels: newChannels);
    } on Object {
      return const _CrawlResult(resources: [], newChannels: []);
    }
  }

  static List<String> _extractMessageBodies(String html) {
    final pattern = RegExp(
      r'<div class="tgme_widget_message_text[^"]*"[^>]*>([\s\S]*?)</div>',
      caseSensitive: false,
    );
    final messages = <String>[];
    for (final match in pattern.allMatches(html)) {
      var text = _cleanHtml(match.group(1) ?? '');
      if (text.length > 5) messages.add(text);
    }
    return messages;
  }

  static List<String> _extractChannelNames(String html) {
    final pattern = RegExp(
      r'https?://t\.me/([a-zA-Z0-9_]+)',
      caseSensitive: false,
    );
    final names = <String>{};
    for (final match in pattern.allMatches(html)) {
      final name = match.group(1)?.toLowerCase() ?? '';
      if (name != 's' && name != 'share' && name.length >= 3) {
        names.add(name);
      }
    }
    return names.toList();
  }

  static List<_ShareLink> _extractShareLinks(String text) {
    final patterns = <(RegExp, String)>[
      (RegExp(r'https?://\S*?alipan\.com/s/\S+', caseSensitive: false), 'alipan'),
      (RegExp(r'https?://\S*?aliyundrive\.com/s/\S+', caseSensitive: false), 'aliyun'),
      (RegExp(r'https?://\S*?pan\.quark\.cn/s/\S+', caseSensitive: false), 'quark'),
      (RegExp(r'https?://\S*?drive\.uc\.cn/s/\S+', caseSensitive: false), 'uc'),
      (RegExp(r'https?://\S*?pan\.xunlei\.com/s/\S+', caseSensitive: false), 'xunlei'),
      (RegExp(r'https?://\S*?(?:115cdn|115)\.com/s/\S+', caseSensitive: false), '115'),
      (RegExp(r'https?://\S*?123pan\.com/s/\S+', caseSensitive: false), '123pan'),
      (RegExp(r'https?://\S*?123865\.com/s/\S+', caseSensitive: false), '123pan'),
      (RegExp(r'https?://\S*?pan\.baidu\.com/s/\S+', caseSensitive: false), 'baidu'),
      (RegExp(r'https?://\S*?mypikpak\.com/s/\S+', caseSensitive: false), 'pikpak'),
    ];

    final links = <String, _ShareLink>{};
    for (final (regex, provider) in patterns) {
      for (final match in regex.allMatches(text)) {
        var url = match.group(0) ?? '';
        final spaceIndex = url.indexOf(' ');
        if (spaceIndex > 0) url = url.substring(0, spaceIndex);
        url = url.replaceAll(RegExp(r'[.,;)">]+$'), '');

        final canonical = url.split('?').first.split('#').first;
        if (!links.containsKey(canonical)) {
          final pwdMatch = RegExp(
            r'(?:提取码|密码|pwd|password)[：:=]\s*(\w+)',
            caseSensitive: false,
          ).firstMatch(text);
          links[canonical] = _ShareLink(
            url: canonical,
            provider: provider,
            sharePwd: pwdMatch?.group(1),
          );
        }
      }
    }
    return links.values.toList();
  }

  static String _extractTitle(String text) {
    final patterns = [
      RegExp(r'[🎬📺🎥🎞️📀💿🔹🔥]{1,3}\s*(.+?)(?:\n|$|https?://|[🎬📺🎥])'),
      RegExp(r'【(.+?)】'),
      RegExp(r'《(.+?)》'),
      RegExp(r'^#?\s*(.+?)(?:\n|https?://|$)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final candidate = match.group(1)?.trim() ?? '';
        if (candidate.length > 2 && candidate.length < 80) return candidate;
      }
    }
    final firstLine = text.split('\n').first.replaceAll(
      RegExp(r'[🎬📺🎥🎞️📀💿🔹🔥]'),
      '',
    ).trim();
    return firstLine.length > 2 ? firstLine : '未命名资源';
  }

  static String _cleanHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  Future<List<Resource>> _loadExistingOutput() async {
    try {
      final file = File(p.join(_outputDir, 'telegram.json'));
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Resource.fromJson)
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> _saveOutput(List<Resource> resources) async {
    final dir = Directory(_outputDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(_outputDir, 'telegram.json'));
    final encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(resources.map((r) => r.toJson()).toList()),
    );
  }

  static String get _defaultOutputDir {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return p.join(home, '.jusou', 'sources');
  }
}

class _CrawlResult {
  final List<Resource> resources;
  final List<String> newChannels;

  const _CrawlResult({required this.resources, required this.newChannels});
}

class _ShareLink {
  final String url;
  final String provider;
  final String? sharePwd;

  const _ShareLink({required this.url, required this.provider, this.sharePwd});
}
