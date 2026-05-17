import '../models/resource.dart';
import 'share_link_parser.dart';

class ResourceKey {
  static const _parser = ShareLinkParser();

  ResourceKey._();

  static String forResource(Resource resource) {
    return forShare(id: resource.id, shareUrl: resource.shareUrl);
  }

  static String forShare({required String id, required String shareUrl}) {
    final trimmedUrl = shareUrl.trim();
    if (trimmedUrl.isEmpty) return id;

    final info = _parser.parse(trimmedUrl);
    if (info.isRecognizedShare && info.shareId != null) {
      return 'share:${info.provider}:${info.shareId}';
    }
    if (info.canonicalUrl != null) return 'url:${info.canonicalUrl}';

    return trimmedUrl.toLowerCase();
  }

  static List<String> candidatesForResource(Resource resource) {
    final trimmedUrl = resource.shareUrl.trim();
    final canonical = forResource(resource);
    return {
      canonical,
      if (trimmedUrl.isNotEmpty) trimmedUrl.toLowerCase(),
      if (resource.id.trim().isNotEmpty) resource.id.trim(),
    }.where((key) => key.isNotEmpty).toList();
  }
}
