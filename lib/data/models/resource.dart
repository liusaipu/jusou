import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'link_validation.dart';

class Resource extends Equatable {
  final String id;
  final String title;
  final String? year;
  final String type; // "movie" 或 "tv"
  final int? episodeCount;
  final String? posterUrl;
  final String shareUrl;
  final String? sharePwd;
  final String? fileSize;
  final String source;
  final DateTime updatedAt;
  final LinkValidationResult? validation;
  final double qualityScore;
  final int duplicateCount;
  final List<String> mergedSources;

  const Resource({
    required this.id,
    required this.title,
    this.year,
    required this.type,
    this.episodeCount,
    this.posterUrl,
    required this.shareUrl,
    this.sharePwd,
    this.fileSize,
    required this.source,
    required this.updatedAt,
    this.validation,
    this.qualityScore = 0,
    this.duplicateCount = 1,
    this.mergedSources = const [],
  });

  factory Resource.fromJson(Map<String, dynamic> json) {
    final title = _readString(json, 'title') ?? '';
    final shareUrl =
        _readString(json, 'share_url', fallbackKey: 'shareUrl') ?? '';

    return Resource(
      id:
          _readString(json, 'id') ??
          _fallbackId(title: title, shareUrl: shareUrl),
      title: title,
      year: _readString(json, 'year'),
      type: _readString(json, 'type') ?? 'movie',
      episodeCount: _readInt(
        json,
        'episode_count',
        fallbackKey: 'episodeCount',
      ),
      posterUrl: _readString(json, 'poster_url', fallbackKey: 'posterUrl'),
      shareUrl: shareUrl,
      sharePwd: _readString(json, 'share_pwd', fallbackKey: 'sharePwd'),
      fileSize: _readString(json, 'file_size', fallbackKey: 'fileSize'),
      source: _readString(json, 'source') ?? '',
      updatedAt:
          _readDateTime(json, 'updated_at', fallbackKey: 'updatedAt') ??
          DateTime.now(),
      validation: _readValidation(json['validation']),
      qualityScore: _readDouble(
        json,
        'quality_score',
        fallbackKey: 'qualityScore',
      ),
      duplicateCount:
          _readInt(json, 'duplicate_count', fallbackKey: 'duplicateCount') ?? 1,
      mergedSources: _readStringList(
        json,
        'merged_sources',
        fallbackKey: 'mergedSources',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'year': year,
    'type': type,
    'episode_count': episodeCount,
    'poster_url': posterUrl,
    'share_url': shareUrl,
    'share_pwd': sharePwd,
    'file_size': fileSize,
    'source': source,
    'updated_at': updatedAt.toIso8601String(),
    if (validation != null) 'validation': validation!.toJson(),
    'quality_score': qualityScore,
    'duplicate_count': duplicateCount,
    'merged_sources': mergedSources,
  };

  Resource copyWith({
    String? id,
    String? title,
    String? year,
    String? type,
    int? episodeCount,
    String? posterUrl,
    String? shareUrl,
    String? sharePwd,
    String? fileSize,
    String? source,
    DateTime? updatedAt,
    LinkValidationResult? validation,
    double? qualityScore,
    int? duplicateCount,
    List<String>? mergedSources,
  }) {
    return Resource(
      id: id ?? this.id,
      title: title ?? this.title,
      year: year ?? this.year,
      type: type ?? this.type,
      episodeCount: episodeCount ?? this.episodeCount,
      posterUrl: posterUrl ?? this.posterUrl,
      shareUrl: shareUrl ?? this.shareUrl,
      sharePwd: sharePwd ?? this.sharePwd,
      fileSize: fileSize ?? this.fileSize,
      source: source ?? this.source,
      updatedAt: updatedAt ?? this.updatedAt,
      validation: validation ?? this.validation,
      qualityScore: qualityScore ?? this.qualityScore,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      mergedSources: mergedSources ?? this.mergedSources,
    );
  }

  static String? _readString(
    Map<String, dynamic> json,
    String key, {
    String? fallbackKey,
  }) {
    final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _readInt(
    Map<String, dynamic> json,
    String key, {
    String? fallbackKey,
  }) {
    final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double _readDouble(
    Map<String, dynamic> json,
    String key, {
    String? fallbackKey,
  }) {
    final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static List<String> _readStringList(
    Map<String, dynamic> json,
    String key, {
    String? fallbackKey,
  }) {
    final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static DateTime? _readDateTime(
    Map<String, dynamic> json,
    String key, {
    String? fallbackKey,
  }) {
    final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static LinkValidationResult? _readValidation(dynamic value) {
    if (value is Map<String, dynamic>) {
      return LinkValidationResult.fromJson(value);
    }
    return null;
  }

  static String _fallbackId({required String title, required String shareUrl}) {
    final source = shareUrl.isNotEmpty ? shareUrl : title;
    final encoded = base64Url.encode(utf8.encode(source)).replaceAll('=', '');
    final token = encoded.length > 24 ? encoded.substring(0, 24) : encoded;
    return 'resource_$token';
  }

  @override
  List<Object?> get props => [id, shareUrl];
}
