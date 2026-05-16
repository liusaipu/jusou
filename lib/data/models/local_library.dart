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
  static const defaultPanSouBaseUrl = 'https://so.252035.xyz';

  final bool enablePanSou;
  final String panSouBaseUrl;

  const LibrarySettings({
    this.enablePanSou = true,
    this.panSouBaseUrl = defaultPanSouBaseUrl,
  });

  factory LibrarySettings.fromJson(Map<String, dynamic> json) {
    final rawEnablePanSou = json['enable_pansou'] ?? json['enablePanSou'];
    final baseUrl =
        json['pansou_base_url']?.toString() ??
        json['panSouBaseUrl']?.toString() ??
        defaultPanSouBaseUrl;

    return LibrarySettings(
      enablePanSou: rawEnablePanSou is bool ? rawEnablePanSou : true,
      panSouBaseUrl: baseUrl.trim().isEmpty
          ? defaultPanSouBaseUrl
          : baseUrl.trim(),
    );
  }

  LibrarySettings copyWith({bool? enablePanSou, String? panSouBaseUrl}) {
    return LibrarySettings(
      enablePanSou: enablePanSou ?? this.enablePanSou,
      panSouBaseUrl: panSouBaseUrl ?? this.panSouBaseUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'enable_pansou': enablePanSou,
    'pansou_base_url': panSouBaseUrl,
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
