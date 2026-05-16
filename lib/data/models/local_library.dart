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

  final bool enableRemote;
  final List<String> remoteUrls;

  const LibrarySettings({
    this.enableRemote = true,
    this.remoteUrls = defaultRemoteUrls,
  });

  factory LibrarySettings.fromJson(Map<String, dynamic> json) {
    final rawEnableRemote = json['enable_remote'] ?? json['enableRemote'] ?? true;

    final urlsRaw = json['remote_urls'] ?? json['remoteUrls'];
    if (urlsRaw is List) {
      final urls = urlsRaw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return LibrarySettings(
        enableRemote: rawEnableRemote is bool ? rawEnableRemote : true,
        remoteUrls: urls,
      );
    }

    // 兼容旧版单 URL 格式
    final singleUrl =
        json['remote_url']?.toString() ??
        json['remoteUrl']?.toString() ??
        '';
    final trimmed = singleUrl.trim();
    return LibrarySettings(
      enableRemote: rawEnableRemote is bool ? rawEnableRemote : true,
      remoteUrls: trimmed.isEmpty ? [] : [trimmed],
    );
  }

  LibrarySettings copyWith({bool? enableRemote, List<String>? remoteUrls}) {
    return LibrarySettings(
      enableRemote: enableRemote ?? this.enableRemote,
      remoteUrls: remoteUrls ?? this.remoteUrls,
    );
  }

  Map<String, dynamic> toJson() => {
    'enable_remote': enableRemote,
    'remote_urls': remoteUrls,
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
