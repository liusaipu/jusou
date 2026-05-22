part of 'home_page.dart';

class _ProviderFilterOption {
  final String key;
  final String label;

  const _ProviderFilterOption({required this.key, required this.label});
}

class _MetaBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MetaBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _providerKeyForResource(Resource resource) {
  final info = _shareLinkParser.parse(resource.shareUrl);
  return info.isRecognizedShare
      ? info.provider
      : ShareLinkParser.unknownProvider;
}

String _providerLabel(String provider) {
  return switch (provider) {
    'aliyun' => '阿里云盘',
    'baidu' => '百度网盘',
    'quark' => '夸克网盘',
    'uc' => 'UC网盘',
    'xunlei' => '迅雷云盘',
    '115' => '115网盘',
    '123' => '123云盘',
    _ => '其他网盘',
  };
}

String _resourceTypeLabel(String type) {
  return switch (type) {
    'movie' => '电影',
    'tv' => '剧集',
    'documentary' => '纪录片',
    'variety' => '综艺',
    _ => '其他',
  };
}

Color _resourceTypeColor(String type) {
  return switch (type) {
    'movie' => const Color(0xFF1677FF),
    'tv' => const Color(0xFF00B51D),
    'documentary' => const Color(0xFFFFB000),
    'variety' => const Color(0xFF00A3FF),
    _ => const Color(0xFF888888),
  };
}

int _providerSortIndex(String provider) {
  return switch (provider) {
    'aliyun' => 0,
    'baidu' => 1,
    'quark' => 2,
    'uc' => 3,
    'xunlei' => 4,
    '115' => 5,
    '123' => 6,
    _ => 99,
  };
}

Color _providerColor(String provider) {
  return switch (provider) {
    'aliyun' => const Color(0xFFFF6A00),
    'baidu' => const Color(0xFF315EFB),
    'quark' => const Color(0xFF00A3FF),
    'uc' => const Color(0xFFFFB000),
    'xunlei' => const Color(0xFF6A5CFF),
    '115' => const Color(0xFF00A870),
    '123' => const Color(0xFF1677FF),
    _ => const Color(0xFF888888),
  };
}

Color _validationColor(LinkValidationLevel level) {
  return switch (level) {
    LinkValidationLevel.invalid => const Color(0xFFFF4D4F),
    LinkValidationLevel.urlFormat => const Color(0xFF888888),
    LinkValidationLevel.recognizedShare => const Color(0xFF1677FF),
    LinkValidationLevel.httpReachable => const Color(0xFF00B51D),
    LinkValidationLevel.availableShare => const Color(0xFF00B51D),
    LinkValidationLevel.metadataReadable => const Color(0xFF00B51D),
  };
}

bool _hasShareCode(Resource resource) {
  return resource.sharePwd != null && resource.sharePwd!.trim().isNotEmpty;
}

String _resourceKey(Resource resource) {
  return ResourceKey.forResource(resource);
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
