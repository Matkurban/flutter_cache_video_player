import 'package:universal_platform/universal_platform.dart';

import 'platform_processor.dart';

/// 应用平台类型枚举。
/// Enumeration of supported application platform types.
enum AppPlatformType { android, ios, windows, macos, linux, web }

/// 平台检测工具类，提供统一的平台判断能力。
/// 底层基于 [UniversalPlatform]，同时兼容原生与 Web。
///
/// Platform detection utility providing unified platform queries.
/// Backed by [UniversalPlatform] so it works on both native and web targets.
sealed class PlatformDetector {
  /// 是否运行在 Web 平台。
  /// Whether the app is running on the web platform.
  static bool get isWeb => UniversalPlatform.isWeb;

  /// 是否运行在原生平台（非 Web）。
  /// Whether the app is running on a native (non-web) platform.
  static bool get isNative => !UniversalPlatform.isWeb;

  /// 是否为 Android。
  /// Whether the current platform is Android.
  static bool get isAndroid => UniversalPlatform.isAndroid;

  /// 是否为 iOS。
  /// Whether the current platform is iOS.
  static bool get isIOS => UniversalPlatform.isIOS;

  /// 是否为 Windows。
  /// Whether the current platform is Windows.
  static bool get isWindows => UniversalPlatform.isWindows;

  /// 是否为 macOS。
  /// Whether the current platform is macOS.
  static bool get isMacOS => UniversalPlatform.isMacOS;

  /// 是否为 Linux。
  /// Whether the current platform is Linux.
  static bool get isLinux => UniversalPlatform.isLinux;

  /// 是否为移动平台（Android / iOS）。
  /// Whether the current platform is mobile (Android / iOS).
  static bool get isMobile => UniversalPlatform.isAndroid || UniversalPlatform.isIOS;

  /// 是否为桌面平台（Windows / macOS / Linux）。
  /// Whether the current platform is desktop (Windows / macOS / Linux).
  static bool get isDesktop =>
      UniversalPlatform.isWindows || UniversalPlatform.isMacOS || UniversalPlatform.isLinux;

  /// 获取当前平台类型。
  /// Returns the current platform type.
  static AppPlatformType get current {
    if (UniversalPlatform.isWeb) return AppPlatformType.web;
    if (UniversalPlatform.isAndroid) return AppPlatformType.android;
    if (UniversalPlatform.isIOS) return AppPlatformType.ios;
    if (UniversalPlatform.isWindows) return AppPlatformType.windows;
    if (UniversalPlatform.isMacOS) return AppPlatformType.macos;
    if (UniversalPlatform.isLinux) return AppPlatformType.linux;
    return AppPlatformType.linux;
  }

  /// 逻辑 CPU 核心数（Web 或不可用时回退为 4）。
  /// Number of logical processor cores (falls back to 4 on web / unavailable).
  static int get processorCores {
    if (isWeb) return 4;
    return processorCoreCount;
  }

  /// 是否为 Linux 服务端环境（与 tostore 一致，用于并发策略）。
  /// Whether this is a Linux server environment (aligned with tostore).
  static bool get isServerEnvironment => isLinux;

  /// 获取建议的 Worker 并发数（对齐 tostore recommendedConcurrency）。
  /// Returns the recommended worker count (aligned with tostore).
  static int get recommendedWorkerCount {
    if (isWeb) return 0;

    final cores = processorCores;
    if (isServerEnvironment) {
      return cores.clamp(8, 128);
    } else if (isDesktop) {
      return cores.clamp(4, 64);
    } else if (isMobile) {
      return cores.clamp(4, 16);
    } else {
      return cores.clamp(2, 8);
    }
  }
}
