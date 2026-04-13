import 'package:flutter/foundation.dart';
import '../core/logger.dart';
import '../proxy/proxy_server.dart';

/// 平台播放工厂，根据平台返回代理 URL 或原始 URL。
/// Platform player factory returning a proxy URL on native or the original URL on web.
class PlatformPlayerFactory {
  final ProxyCacheServer? proxyServer;

  PlatformPlayerFactory({this.proxyServer});

  /// 创建播放器所用的媒体 URL。
  /// 原生端：先预初始化缓存元数据，然后始终走本地 HTTP 代理（代理会发送正确的 Content-Type）。
  /// Web 端：使用原始 URL。
  ///
  /// Creates the media URL for the player.
  /// Native: pre-initializes cache metadata, then always uses local HTTP proxy
  /// (proxy sends correct Content-Type headers, avoiding file-extension issues).
  /// Web: uses original URL.
  Future<String> createMediaUrl(String originalUrl) async {
    if (kIsWeb || proxyServer == null) {
      return originalUrl;
    }

    // 预初始化：在返回代理 URL 前先从源服务器获取元数据（大小、MIME 类型）。
    // 这样当原生播放器连接代理时，MediaIndex 已就绪，代理可立即响应。
    // 如果初始化失败（网络异常等），退化为直接使用原始 URL 播放。
    // Pre-initialize: fetch metadata (size, MIME type) from origin server before
    // returning the proxy URL. When the native player connects, existing
    // MediaIndex lets the proxy respond immediately instead of blocking.
    // On failure (network error etc.), fall back to the original URL.
    try {
      await proxyServer!.initCache(originalUrl);
    } catch (e) {
      Logger.warning('initCache failed, falling back to direct URL: $e');
      return originalUrl;
    }

    return proxyServer!.proxyUrl(originalUrl);
  }
}
