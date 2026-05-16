class ShareLinkInfo {
  final Uri? uri;
  final String provider;
  final String? shareId;
  final String? canonicalUrl;

  const ShareLinkInfo({
    required this.uri,
    required this.provider,
    required this.shareId,
    required this.canonicalUrl,
  });

  bool get isValidUrl => uri != null;

  bool get isRecognizedShare => provider != ShareLinkParser.unknownProvider;
}

class ShareLinkParser {
  static const unknownProvider = 'unknown';

  const ShareLinkParser();

  ShareLinkInfo parse(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return const ShareLinkInfo(
        uri: null,
        provider: unknownProvider,
        shareId: null,
        canonicalUrl: null,
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return ShareLinkInfo(
        uri: uri,
        provider: unknownProvider,
        shareId: null,
        canonicalUrl: null,
      );
    }

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    final shareId = _shareIdFromSegments(segments);

    if (_isAliyunHost(host) && shareId != null) {
      return ShareLinkInfo(
        uri: uri,
        provider: 'aliyun',
        shareId: shareId,
        canonicalUrl: 'https://www.alipan.com/s/$shareId',
      );
    }

    if (host == 'pan.quark.cn' && shareId != null) {
      return ShareLinkInfo(
        uri: uri,
        provider: 'quark',
        shareId: shareId,
        canonicalUrl: 'https://pan.quark.cn/s/$shareId',
      );
    }

    if (host == 'pan.baidu.com' && shareId != null) {
      return ShareLinkInfo(
        uri: uri,
        provider: 'baidu',
        shareId: shareId,
        canonicalUrl: 'https://pan.baidu.com/s/$shareId',
      );
    }

    if (host == 'drive.uc.cn' && shareId != null) {
      return ShareLinkInfo(
        uri: uri,
        provider: 'uc',
        shareId: shareId,
        canonicalUrl: 'https://drive.uc.cn/s/$shareId',
      );
    }

    if (host == 'pan.xunlei.com' && shareId != null) {
      return ShareLinkInfo(
        uri: uri,
        provider: 'xunlei',
        shareId: shareId,
        canonicalUrl: 'https://pan.xunlei.com/s/$shareId',
      );
    }

    if (_is115Host(host) && shareId != null) {
      return ShareLinkInfo(
        uri: uri,
        provider: '115',
        shareId: shareId,
        canonicalUrl: 'https://115cdn.com/s/$shareId',
      );
    }

    if (_is123PanHost(host) && shareId != null) {
      return ShareLinkInfo(
        uri: uri,
        provider: '123',
        shareId: shareId,
        canonicalUrl: 'https://123pan.com/s/$shareId',
      );
    }

    return ShareLinkInfo(
      uri: uri,
      provider: unknownProvider,
      shareId: null,
      canonicalUrl: _canonicalUrl(uri),
    );
  }

  static bool _isAliyunHost(String host) {
    return host == 'aliyundrive.com' ||
        host == 'www.aliyundrive.com' ||
        host == 'alipan.com' ||
        host == 'www.alipan.com';
  }

  static bool _is115Host(String host) {
    return host == '115cdn.com' || host == '115.com' || host == 'www.115.com';
  }

  static bool _is123PanHost(String host) {
    return host == '123pan.com' ||
        host == 'www.123pan.com' ||
        host == '123865.com' ||
        host == 'www.123865.com';
  }

  static String? _shareIdFromSegments(List<String> segments) {
    final index = segments.indexOf('s');
    if (index < 0 || index + 1 >= segments.length) return null;
    final shareId = segments[index + 1].trim();
    return shareId.isEmpty ? null : shareId;
  }

  static String _canonicalUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return Uri(scheme: scheme, host: host, path: path).toString();
  }
}
