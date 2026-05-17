import 'package:dio/dio.dart';

import '../models/link_validation.dart';
import '../models/resource.dart';
import 'share_link_parser.dart';

class LinkValidator {
  final Dio? _dio;
  final bool enableNetworkCheck;
  final ShareLinkParser _parser;

  const LinkValidator({
    Dio? dio,
    this.enableNetworkCheck = false,
    ShareLinkParser parser = const ShareLinkParser(),
  }) : _dio = dio,
       _parser = parser;

  Future<LinkValidationResult> validate(Resource resource) async {
    final info = _parser.parse(resource.shareUrl);
    final now = DateTime.now();

    if (!info.isValidUrl) {
      return LinkValidationResult(
        level: LinkValidationLevel.invalid,
        reason: 'URL 格式不合法',
        checkedAt: now,
      );
    }

    if (!info.isRecognizedShare) {
      return LinkValidationResult(
        level: LinkValidationLevel.urlFormat,
        reason: 'URL 可解析，但暂未识别为支持的网盘分享',
        checkedAt: now,
      );
    }

    if (_isPlaceholderShareId(info.shareId)) {
      return LinkValidationResult(
        level: LinkValidationLevel.invalid,
        reason: '演示占位链接，不是真实分享',
        checkedAt: now,
      );
    }

    if (!enableNetworkCheck) {
      return LinkValidationResult(
        level: LinkValidationLevel.recognizedShare,
        reason: '已识别为${_providerLabel(info.provider)}分享链接',
        checkedAt: now,
      );
    }

    final reachable = await _checkReachable(
      info.canonicalUrl ?? resource.shareUrl,
    );
    if (!reachable) {
      return LinkValidationResult(
        level: LinkValidationLevel.recognizedShare,
        reason: '已识别为${_providerLabel(info.provider)}分享链接，但当前无法确认可访问',
        checkedAt: DateTime.now(),
      );
    }

    return LinkValidationResult(
      level: LinkValidationLevel.httpReachable,
      reason: '链接页面可访问',
      checkedAt: DateTime.now(),
    );
  }

  Future<List<Resource>> validateAll(List<Resource> resources) async {
    final validated = await Future.wait(
      resources.map((resource) async {
        final result = await validate(resource);
        return resource.copyWith(validation: result);
      }),
    );
    return validated.where((resource) {
      return resource.validation?.level != LinkValidationLevel.invalid;
    }).toList();
  }

  Future<bool> _checkReachable(String url) async {
    final dio =
        _dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );

    if (await _requestReachable(dio, url, 'HEAD')) return true;
    return _requestReachable(dio, url, 'GET');
  }

  Future<bool> _requestReachable(Dio dio, String url, String method) async {
    try {
      final response = await dio.request<dynamic>(
        url,
        options: Options(
          method: method,
          followRedirects: true,
          responseType: ResponseType.plain,
          headers: method == 'GET' ? const {'Range': 'bytes=0-0'} : null,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return response.statusCode != null && response.statusCode! < 400;
    } on DioException {
      return false;
    }
  }

  String _providerLabel(String provider) {
    return switch (provider) {
      'aliyun' => '阿里云盘',
      'quark' => '夸克网盘',
      'baidu' => '百度网盘',
      'uc' => 'UC网盘',
      'xunlei' => '迅雷云盘',
      '115' => '115网盘',
      '123' => '123云盘',
      _ => '网盘',
    };
  }

  bool _isPlaceholderShareId(String? shareId) {
    if (shareId == null) return false;
    return RegExp(
      r'^(example|demo|sample|test)[-_]?\d*$',
      caseSensitive: false,
    ).hasMatch(shareId.trim());
  }
}
