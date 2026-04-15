# flutter_cache_video_player

[中文文档](README_ZH.md)

A cross-platform Flutter plugin for playing audio and video with **chunk-based caching**. Media is downloaded in chunks
while playing, cached locally, and served through a built-in HTTP proxy — enabling seamless playback with offline
support and minimal bandwidth waste.

## Features

- **Stream-while-download** — media plays immediately while chunks download in the background
- **Chunk-based caching** — media is split into configurable chunks (default 2 MB) and cached individually
- **Multi-threaded downloads** — Isolate-based worker pool (2 workers on mobile, 4 on desktop) for parallel chunk
  downloading
- **Resumable downloads** — interrupted downloads pick up where they left off via chunk bitmap tracking
- **LRU cache eviction** — automatic eviction of least-recently-used media when cache limit is reached (default 2 GB)
- **Smart prefetching** — prefetches upcoming chunks and playlist items ahead of time
- **Priority queue** — seeking triggers urgent (P0) download of the target chunk
- **Native rendering** — platform-specific players with Flutter Texture integration for high-performance video rendering
- **6-platform support** — Android, iOS, macOS, Linux, Windows, and Web
- **Built-in UI** — ready-to-use video/audio player widgets, playlist panel, responsive layouts, and theme support
- **Playback history** — saves and optionally restores playback positions per media

## Platform Engines

| Platform | Native Engine                             |
|----------|-------------------------------------------|
| Android  | ExoPlayer (Media3)                        |
| iOS      | AVPlayer                                  |
| macOS    | AVPlayer                                  |
| Linux    | GStreamer (playbin3)                      |
| Windows  | Media Foundation (IMFMediaEngine + D3D11) |
| Web      | HTML5 `<video>`                           |

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Application                     │
├─────────────────────────────────────────────────┤
│  FlutterCacheVideoPlayer (Facade)               │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │ Player   │ │ Playlist │ │ Theme            │ │
│  │ Service  │ │ Manager  │ │ Controller       │ │
│  └────┬─────┘ └──────────┘ └──────────────────┘ │
│       │                                          │
│  ┌────▼─────────────────┐  ┌──────────────────┐ │
│  │ NativePlayerController│  │ Download Manager │ │
│  │ (MethodChannel)      │  │ (Priority Queue) │ │
│  └────┬─────────────────┘  └────┬─────────────┘ │
│       │                         │                │
│  ┌────▼──────────┐  ┌──────────▼──────────────┐ │
│  │ Proxy Server  │  │ Worker Pool (Isolates)  │ │
│  │ (shelf HTTP)  │  │ ┌──┐ ┌──┐ ┌──┐ ┌──┐    │ │
│  │ 127.0.0.1:0   │  │ │W1│ │W2│ │W3│ │W4│    │ │
│  └───────────────┘  │ └──┘ └──┘ └──┘ └──┘    │ │
│                      └────────────────────────┘ │
│  ┌─────────────────────────────────────────────┐ │
│  │ Cache Repository (ToStore) + Chunk Files    │ │
│  └─────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────┤
│  Native Platform Layer                           │
│  ExoPlayer │ AVPlayer │ GStreamer │ MF │ HTML5   │
└─────────────────────────────────────────────────┘
```

## Getting Started

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_cache_video_player: ^lasted
```

### Platform Setup

#### Android

Android 9+ blocks cleartext HTTP by default. The plugin uses a local HTTP proxy (`127.0.0.1`), so you must allow
localhost cleartext traffic.

1. Create `android/app/src/main/res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
```

2. Reference it in `AndroidManifest.xml`:

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

3. Ensure the INTERNET permission is present:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

#### iOS

Add to `ios/Runner/Info.plist` if loading from HTTP sources:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

#### macOS

Add to `macos/Runner/Release.entitlements` and `DebugProfile.entitlements`:

```xml

<key>com.apple.security.network.client</key>
<true/>
```

Add to `macos/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

#### Linux

Install GStreamer development libraries:

```bash
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
```

## Configuration Reference

| Parameter                | Default | Description                             |
|--------------------------|---------|-----------------------------------------|
| `chunkSize`              | 2 MB    | Size of each download chunk             |
| `maxCacheBytes`          | 2 GB    | Maximum total cache size                |
| `mobileWorkerCount`      | 2       | Parallel download workers on mobile     |
| `desktopWorkerCount`     | 4       | Parallel download workers on desktop    |
| `prefetchCount`          | 3       | Number of chunks to prefetch ahead      |
| `maxRetryCount`          | 3       | Max retries for failed chunk downloads  |
| `retryBaseDelayMs`       | 1000    | Base delay for exponential backoff (ms) |
| `wifiOnlyDownload`       | true    | Restrict downloads to Wi-Fi on mobile   |
| `enablePlaylistPrefetch` | true    | Prefetch next playlist items            |
| `enableChunkChecksum`    | false   | Verify MD5 checksum after download      |

## How It Works

1. **Request** — When `open(url)` is called, the proxy server starts serving the media URL from
   `http://127.0.0.1:{port}`
2. **Download** — The download manager creates a chunk queue and dispatches tasks to the Isolate worker pool based on
   priority
3. **Cache** — Each downloaded chunk is saved as a separate file; a bitmap tracks which chunks are available
4. **Serve** — The proxy server reads cached chunks from disk and streams them to the native player; if a chunk is
   missing, it waits for the download to complete
5. **Play** — The native player (ExoPlayer/AVPlayer/GStreamer/MF/HTML5) renders frames via Flutter Texture

## Example

See the [example](example/) directory for a complete app demonstrating:

- Responsive layout (mobile / tablet / desktop)
- Signals-based reactive state management
- Error state display with retry
- Playlist with shuffle and repeat
- Theme support

## License

See [LICENSE](LICENSE) for details.

