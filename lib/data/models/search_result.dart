import 'package:equatable/equatable.dart';
import 'resource.dart';

class SearchResult extends Equatable {
  final List<Resource> resources;
  final String query;
  final int totalCount;
  final int elapsedMs;

  const SearchResult({
    required this.resources,
    required this.query,
    this.totalCount = 0,
    this.elapsedMs = 0,
  });

  @override
  List<Object?> get props => [query, resources];
}
