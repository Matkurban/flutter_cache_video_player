import 'package:flutter/foundation.dart';
import '../core/logger.dart';
import '../proxy/proxy_server.dart';

/// 平台播放工厂，根据平台返回代理 URL 或原始 URL。
/// Platform player factory returning a proxy URL on native or the original URL on web.
class PlatformPlayerFactory {
  final ProxyCacheServer? proxyServer;

  PlatformPlayerFactory({this.proxyServer});

  /// 创建播放器所用的媒体 URL。
  /// Windows：IMFMediaEngine 直接使用原始 URL 或本地缓存文件（绕过代理）。
  /// 其他原生端：走本地 HTTP 代理。Web 端：使用原始 URL。
  ///
  /// Creates the media URL for the player.
  /// Windows: IMFMediaEngine loads original URL or cached file directly (bypasses proxy).
  /// Other native: routes through the local HTTP proxy. Web: uses original URL.
  Future<String> createMediaUrl(String originalUrl) async {
    if (kIsWeb || proxyServer == null) {
      return originalUrl;
    }

    // Windows: IMFMediaEngine (WinHTTP) 无法可靠地从 Dart shelf 代理服务器加载，
    // 直接使用本地缓存文件或原始远程 URL。
    // Windows: IMFMediaEngine (WinHTTP) cannot reliably load from the Dart shelf proxy server,
    // so load from cached local file or the original remote URL directly.
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // 1. 检查是否已完全缓存 / Check if fully cached
      final cachedUrl = await proxyServer!.getCachedFileUrl(originalUrl);
      if (cachedUrl != null) {
        Logger.info('Windows: playing from cache: $cachedUrl');
        return cachedUrl;
      }
      // 2. 未缓存：启动后台下载，播放器直接用远程 URL
      // Not cached: start background download, player uses remote URL directly
      proxyServer!.initCache(originalUrl).catchError((e) {
        Logger.error('Windows background cache init failed: $e');
      });
      return originalUrl;
    }

    return proxyServer!.proxyUrl(originalUrl);
  }
}
