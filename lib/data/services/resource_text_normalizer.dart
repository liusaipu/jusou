class ResourceTextNormalizer {
  static final _spacePattern = RegExp(r'\s+');
  static final _bracketPattern = RegExp(r'[\[\]【】（）()「」『』《》]');
  static const _variantCharacters = <String, String>{
    '飚': '飙',
    '飆': '飙',
    '飈': '飙',
    '飇': '飙',
    '颷': '飙',
  };
  static final _qualityWords = RegExp(
    r'(4k|8k|1080p|2160p|720p|hdr|uhd|bluray|web-?dl|高清|超清|蓝光|'
    r'国语|国配|中字|中英|内嵌|无水印|全集|完整版|阿里云盘|阿里|夸克|百度网盘|百度)',
    caseSensitive: false,
  );
  static final _noiseWords = RegExp(
    r'(在线观看|免费下载|免费|资源|网盘|云盘|分享|持续更新|更新至|已完结)',
    caseSensitive: false,
  );

  const ResourceTextNormalizer();

  String normalizeCharacters(String text) {
    var normalized = text;
    for (final entry in _variantCharacters.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized;
  }

  List<String> searchQueryVariants(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final variants = <String>[];
    void addVariant(String value) {
      final variant = value.trim();
      if (variant.isNotEmpty && !variants.contains(variant)) {
        variants.add(variant);
      }
    }

    addVariant(trimmed);
    addVariant(normalizeCharacters(trimmed));

    return variants;
  }

  String titleKey(String title) {
    return normalizeCharacters(title)
        .toLowerCase()
        .replaceAll(_bracketPattern, ' ')
        .replaceAll(_qualityWords, ' ')
        .replaceAll(_noiseWords, ' ')
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5a-z0-9]+'), ' ')
        .replaceAll(_spacePattern, '')
        .trim();
  }

  int keywordMatchScore(String query, String title) {
    final queryKey = titleKey(query);
    final titleValue = titleKey(title);
    if (queryKey.isEmpty || titleValue.isEmpty) return 0;
    if (titleValue == queryKey) return 40;
    if (titleValue.contains(queryKey)) return 32;

    final tokens = _tokens(query);
    if (tokens.isEmpty) return 0;

    final matched = tokens
        .where((token) => titleValue.contains(titleKey(token)))
        .length;
    return (matched / tokens.length * 24).round();
  }

  int titlePollutionPenalty(String title) {
    var penalty = 0;
    final lower = title.toLowerCase();
    final noisyTerms = [
      '在线观看',
      '免费下载',
      '免费',
      '公众号',
      '广告',
      '群',
      '防走丢',
      'www.',
      'http',
    ];

    for (final term in noisyTerms) {
      if (lower.contains(term)) penalty += 6;
    }

    if (title.length > 48) penalty += 5;
    if (title.length > 72) penalty += 8;

    return penalty;
  }

  List<String> _tokens(String input) {
    return input
        .toLowerCase()
        .split(RegExp(r'[^\u4e00-\u9fa5a-z0-9]+'))
        .where((token) => token.trim().isNotEmpty)
        .toList();
  }
}
