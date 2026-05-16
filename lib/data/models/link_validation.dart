import 'package:equatable/equatable.dart';

enum LinkValidationLevel {
  invalid(0, '链接无效'),
  urlFormat(20, '格式有效'),
  recognizedShare(40, '网盘链接'),
  httpReachable(60, '可访问'),
  availableShare(80, '分享有效'),
  metadataReadable(100, '信息完整');

  const LinkValidationLevel(this.score, this.label);

  final int score;
  final String label;
}

class LinkValidationResult extends Equatable {
  final LinkValidationLevel level;
  final String reason;
  final DateTime checkedAt;

  const LinkValidationResult({
    required this.level,
    required this.reason,
    required this.checkedAt,
  });

  factory LinkValidationResult.fromJson(Map<String, dynamic> json) {
    final rawLevel = json['level']?.toString();
    final level = LinkValidationLevel.values.firstWhere(
      (value) => value.name == rawLevel,
      orElse: () => LinkValidationLevel.urlFormat,
    );
    final rawCheckedAt = json['checked_at'] ?? json['checkedAt'];
    final checkedAt = rawCheckedAt is String
        ? DateTime.tryParse(rawCheckedAt) ??
              DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(0);

    return LinkValidationResult(
      level: level,
      reason: json['reason']?.toString() ?? '',
      checkedAt: checkedAt,
    );
  }

  bool get isValid => level != LinkValidationLevel.invalid;

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'reason': reason,
    'checked_at': checkedAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [level, reason, checkedAt];
}
