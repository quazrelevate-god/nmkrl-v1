import 'package:flutter/material.dart';

import '../core/env.dart';

/// Port of mediaUrl() in frontend/lib/api.js, adapted for mobile:
///   * http(s) URLs pass through untouched
///   * "/community/…" paths are static demo photos BUNDLED with the app
///     (the web served them from its own /public; mobile has no web origin)
///   * everything else ("/uploads/…") resolves against the backend base URL
sealed class MediaRef {
  const MediaRef();
}

class NetworkMedia extends MediaRef {
  const NetworkMedia(this.url);

  final String url;
}

class AssetMedia extends MediaRef {
  const AssetMedia(this.asset);

  final String asset;
}

MediaRef? mediaRef(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return NetworkMedia(path);
  if (path.startsWith('/community/')) {
    // The bundled copy of community-01 was converted AVIF → JPG (Flutter's
    // image codecs don't decode AVIF).
    final name = path.substring(1).replaceFirst('.avif', '.jpg');
    return AssetMedia('assets/$name');
  }
  return NetworkMedia('${Env.apiBase}$path');
}

/// ImageProvider for an issue photo / story image, or null when absent.
ImageProvider? mediaImage(String? path) => switch (mediaRef(path)) {
      NetworkMedia(:final url) => NetworkImage(url),
      AssetMedia(:final asset) => AssetImage(asset),
      null => null,
    };
