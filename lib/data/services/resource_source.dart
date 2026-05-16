import 'package:equatable/equatable.dart';

import '../models/resource.dart';

abstract class ResourceSource {
  String get id;

  String get label;

  int get trustScore;

  Future<SourceSearchResult> search(String query);
}

class SourceSearchResult extends Equatable {
  final String sourceId;
  final String sourceLabel;
  final List<Resource> resources;
  final int total;
  final int elapsedMs;

  const SourceSearchResult({
    required this.sourceId,
    required this.sourceLabel,
    required this.resources,
    required this.total,
    required this.elapsedMs,
  });

  @override
  List<Object?> get props => [sourceId, resources, total, elapsedMs];
}

class SourceSearchFailure extends Equatable {
  final String sourceId;
  final String sourceLabel;
  final Object error;

  const SourceSearchFailure({
    required this.sourceId,
    required this.sourceLabel,
    required this.error,
  });

  @override
  List<Object?> get props => [sourceId, sourceLabel, error];
}
