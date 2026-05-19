import 'resource.dart';

class SearchHistoryEntry {
  final String query;
  final int total;
  final DateTime searchedAt;

  const SearchHistoryEntry({
    required this.query,
    required this.total,
    required this.searchedAt,
  });

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    final searchedAt = DateTime.tryParse(
      json['searched_at']?.toString() ?? json['searchedAt']?.toString() ?? '',
    );

    return SearchHistoryEntry(
      query: json['query']?.toString() ?? '',
      total: _intValue(json['total']),
      searchedAt: searchedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'query': query,
    'total': total,
    'searched_at': searchedAt.toIso8601String(),
  };
}

class InvalidLinkReport {
  final String title;
  final String shareUrl;
  final String? sharePwd;
  final String reason;
  final DateTime reportedAt;

  const InvalidLinkReport({
    required this.title,
    required this.shareUrl,
    this.sharePwd,
    required this.reason,
    required this.reportedAt,
  });

  factory InvalidLinkReport.fromJson(Map<String, dynamic> json) {
    final reportedAt = DateTime.tryParse(
      json['reported_at']?.toString() ?? json['reportedAt']?.toString() ?? '',
    );

    return InvalidLinkReport(
      title: json['title']?.toString() ?? '',
      shareUrl:
          json['share_url']?.toString() ?? json['shareUrl']?.toString() ?? '',
      sharePwd: json['share_pwd']?.toString() ?? json['sharePwd']?.toString(),
      reason: json['reason']?.toString() ?? '用户标记失效',
      reportedAt: reportedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'share_url': shareUrl,
    'share_pwd': sharePwd,
    'reason': reason,
    'reported_at': reportedAt.toIso8601String(),
  };
}

class LibrarySettings {
  static const defaultRemoteUrls = <String>[];
  static const maxRemoteUrls = 5;
  static const defaultTelegramChannels = <String>[];
  static const maxTelegramChannels = 200;

  final bool enableRemote;
  final List<String> remoteUrls;
  final bool darkMode;
  final List<String> telegramChannels;

  const LibrarySettings({
    this.enableRemote = true,
    this.remoteUrls = defaultRemoteUrls,
    this.darkMode = true,
    this.telegramChannels = defaultTelegramChannels,
  });

  factory LibrarySettings.fromConfigJson(Map<String, dynamic> json) {
    final settings =
        json['settings'] ?? json['library_settings'] ?? json['librarySettings'];
    if (settings is Map<String, dynamic>) {
      return LibrarySettings.fromJson(settings);
    }
    if (settings is Map) {
      return LibrarySettings.fromJson(Map<String, dynamic>.from(settings));
    }
    return LibrarySettings.fromJson(json);
  }

  factory LibrarySettings.fromJson(Map<String, dynamic> json) {
    final rawEnableRemote =
        json['enable_remote'] ?? json['enableRemote'] ?? true;
    final rawDarkMode = json['dark_mode'] ?? json['darkMode'] ?? true;
    final telegramRaw =
        json['telegram_channels'] ??
        json['telegramChannels'] ??
        json['tg_channels'] ??
        json['tgChannels'];
    final telegramChannels = _telegramChannels(telegramRaw);

    final urlsRaw = json['remote_urls'] ?? json['remoteUrls'];
    if (urlsRaw != null) {
      final urls = _stringList(urlsRaw, maxItems: maxRemoteUrls);
      return LibrarySettings(
        enableRemote: _boolValue(rawEnableRemote, fallback: true),
        remoteUrls: urls,
        darkMode: _boolValue(rawDarkMode, fallback: true),
        telegramChannels: telegramChannels,
      );
    }

    // 兼容旧版单 URL 格式
    final singleUrl =
        json['remote_url']?.toString() ?? json['remoteUrl']?.toString() ?? '';
    final trimmed = singleUrl.trim();
    return LibrarySettings(
      enableRemote: _boolValue(rawEnableRemote, fallback: true),
      remoteUrls: trimmed.isEmpty ? [] : [trimmed],
      darkMode: _boolValue(rawDarkMode, fallback: true),
      telegramChannels: telegramChannels,
    );
  }

  LibrarySettings copyWith({
    bool? enableRemote,
    List<String>? remoteUrls,
    bool? darkMode,
    List<String>? telegramChannels,
  }) {
    return LibrarySettings(
      enableRemote: enableRemote ?? this.enableRemote,
      remoteUrls: remoteUrls ?? this.remoteUrls,
      darkMode: darkMode ?? this.darkMode,
      telegramChannels: telegramChannels ?? this.telegramChannels,
    );
  }

  Map<String, dynamic> toJson() => {
    'enable_remote': enableRemote,
    'remote_urls': remoteUrls,
    'dark_mode': darkMode,
    'telegram_channels': telegramChannels,
  };

  Map<String, dynamic> toConfigJson({DateTime? exportedAt}) => {
    'app': 'jusou',
    'schema_version': 1,
    'exported_at': (exportedAt ?? DateTime.now()).toIso8601String(),
    'settings': toJson(),
  };
}

class LocalLibrarySnapshot {
  final List<Resource> favorites;
  final List<Resource> recentlyOpened;
  final List<SearchHistoryEntry> searchHistory;
  final List<InvalidLinkReport> invalidReports;
  final LibrarySettings settings;

  const LocalLibrarySnapshot({
    required this.favorites,
    required this.recentlyOpened,
    required this.searchHistory,
    required this.invalidReports,
    required this.settings,
  });
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

bool _boolValue(dynamic value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return fallback;
}

List<String> _stringList(dynamic value, {int? maxItems}) {
  final rawItems = value is List
      ? value
      : value is String
      ? value.split(RegExp(r'[\n,;]+'))
      : const [];
  final seen = <String>{};
  final items = <String>[];
  for (final raw in rawItems) {
    final item = raw.toString().trim();
    if (item.isEmpty || seen.contains(item)) continue;
    seen.add(item);
    items.add(item);
    if (maxItems != null && items.length >= maxItems) break;
  }
  return items;
}

List<String> _telegramChannels(dynamic value) {
  final channels = <String>[];
  final seen = <String>{};
  for (final item in _stringList(
    value,
    maxItems: LibrarySettings.maxTelegramChannels,
  )) {
    final channel = _normalizeTelegramChannel(item);
    if (channel == null || seen.contains(channel)) continue;
    seen.add(channel);
    channels.add(channel);
  }
  return channels;
}

String? _normalizeTelegramChannel(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  value = value
      .replaceFirst(RegExp(r'^https?://t\.me/s/', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^https?://t\.me/', caseSensitive: false), '')
      .replaceFirst('@', '');
  value = value.split(RegExp(r'[/?#]')).first.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9_]{3,}$').hasMatch(value)) return null;
  return value;
}
