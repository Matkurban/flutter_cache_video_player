import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../core/constants.dart';
import 'download_task.dart';
import 'download_worker.dart';

/// 单个 Worker 的内部句柄，维护 Isolate 及其状态。
/// Internal handle for a single worker, maintaining its Isolate and state.
class _WorkerHandle {
  final int id;
  final Isolate isolate;
  final SendPort sendPort;
  bool isBusy = false;
  int? currentChunkIndex;

  _WorkerHandle({required this.id, required this.isolate, required this.sendPort});
}

/// Isolate 工作线程池，按 tostore 风格懒加载并按需扩容 Worker。
/// Isolate worker pool with tostore-style lazy initialization and expansion.
class DownloadWorkerPool {
  static const _workerDebugNamePrefix = 'flutter_cache_video_player_worker';

  final int maxPoolSize;
  final CacheConfig config;
  final Map<int, _WorkerHandle> _workers = {};
  final latestEvent = signal<WorkerEvent?>(null);
  final _progressController = StreamController<ChunkProgress>.broadcast(sync: true);
  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  int _nextRoundRobin = 0;
  bool _isShuttingDown = false;
  bool _backgroundExpansionStarted = false;
  int _expansionGeneration = 0;
  Timer? _idleReclaimTimer;
  bool Function()? _hasPendingTasksChecker;

  DownloadWorkerPool({required this.maxPoolSize, required this.config});

  bool get isReady => _isInitialized;
  Stream<ChunkProgress> get progressStream => _progressController.stream;

  /// 当前存活的 Worker id 集合（测试用）。
  @visibleForTesting
  Set<int> get liveWorkerIds => _workers.keys.toSet();

  /// 注册待处理任务检查器，闲置回收计时器触发时会再次调用。
  void setHasPendingTasksChecker(bool Function() checker) {
    _hasPendingTasksChecker = checker;
  }

  /// 有新下载活动时取消闲置回收计时。
  void notifyActivity() {
    _idleReclaimTimer?.cancel();
    _idleReclaimTimer = null;
  }

  /// 在队列排空且无 busy Worker 时启动闲置回收计时。
  void scheduleIdleReclamation({required bool hasPendingTasks}) {
    if (_isShuttingDown || config.workerIdleTimeout <= Duration.zero) return;
    if (hasPendingTasks || activeChunkIndices.isNotEmpty) return;
    if (!_hasExtraWorkersToReclaim) return;

    _idleReclaimTimer?.cancel();
    _idleReclaimTimer = Timer(config.workerIdleTimeout, () {
      _idleReclaimTimer = null;
      final stillPending = _hasPendingTasksChecker?.call() ?? false;
      if (stillPending || activeChunkIndices.isNotEmpty || _isShuttingDown) return;
      unawaited(_reclaimExtraWorkers());
    });
  }

  bool get _hasExtraWorkersToReclaim {
    return _workers.keys.any((id) => id >= 1 && !(_workers[id]?.isBusy ?? true));
  }

  /// 确保至少第一个 Worker 已就绪（首次下载时调用）。
  /// Ensures at least the first worker is ready (called on first download).
  Future<void> ensureReady() async {
    if (_isShuttingDown || maxPoolSize <= 0) return;
    notifyActivity();
    await _ensureInitialized();
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      if (maxPoolSize > 0) {
        await _spawnWorker(0);
      }
      _isInitialized = true;
      _createRemainingWorkersInBackground();
      _initCompleter!.complete();
    } catch (e, st) {
      _initCompleter!.completeError(e, st);
      _initCompleter = null;
      _isInitialized = false;
      rethrow;
    }
  }

  /// 后台异步创建剩余 Worker，避免阻塞首次任务。
  /// Creates remaining workers in the background without blocking startup.
  void _createRemainingWorkersInBackground() {
    if (_backgroundExpansionStarted || maxPoolSize <= 1) return;
    _backgroundExpansionStarted = true;

    final generation = _expansionGeneration;
    for (int i = 1; i < maxPoolSize; i++) {
      unawaited(() async {
        if (_isShuttingDown || generation != _expansionGeneration || _workers.containsKey(i)) {
          return;
        }
        try {
          await _spawnWorker(i, expansionGeneration: generation);
          if (generation == _expansionGeneration && _workers.containsKey(i)) {
            latestEvent.set(const WorkerReady(), force: true);
          }
        } catch (_) {}
      }());
    }
  }

  Future<_WorkerHandle?> _spawnWorker(int index, {int? expansionGeneration}) async {
    final receivePort = ReceivePort();
    final completer = Completer<SendPort>();

    final isolate = await Isolate.spawn(
      DownloadWorkerEntry.workerMain,
      receivePort.sendPort,
      debugName: '$_workerDebugNamePrefix-$index',
      errorsAreFatal: false,
    );

    isolate.addErrorListener(receivePort.sendPort);

    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is Map<String, dynamic>) {
        final event = message['event'] as String?;
        if (event == 'ready') {
          latestEvent.set(const WorkerReady(), force: true);
        } else if (event != null) {
          _handleWorkerEvent(index, WorkerEvent.fromMessage(message));
        }
      } else if (message is List && message.length == 2) {
        unawaited(_respawnWorker(index));
      }
    });

    final sendPort = await completer.future;
    if (_isShuttingDown) {
      isolate.kill(priority: Isolate.immediate);
      return null;
    }
    if (index >= 1 && expansionGeneration != null && expansionGeneration != _expansionGeneration) {
      isolate.kill(priority: Isolate.immediate);
      return null;
    }

    final handle = _WorkerHandle(id: index, isolate: isolate, sendPort: sendPort);
    _workers[index] = handle;
    return handle;
  }

  void _handleWorkerEvent(int workerIndex, WorkerEvent event) {
    final handle = _workers[workerIndex];
    if (handle != null) {
      if (event is ChunkCompleted || event is ChunkFailed || event is WorkerCancelled) {
        final eventChunk = switch (event) {
          ChunkCompleted e => e.chunkIndex,
          ChunkFailed e => e.chunkIndex,
          WorkerCancelled e => e.chunkIndex,
          _ => null,
        };
        if (handle.currentChunkIndex == eventChunk) {
          handle.isBusy = false;
          handle.currentChunkIndex = null;
        }
      }
    }
    if (event is ChunkProgress) {
      _progressController.add(event);
      return;
    }
    if (event is! ChunkProgress) {
      latestEvent.set(event, force: true);
    }
  }

  Future<void> _respawnWorker(int index) async {
    if (_isShuttingDown) return;
    try {
      _workers[index]?.isolate.kill(priority: Isolate.immediate);
    } catch (_) {}
    if (_isShuttingDown) return;
    await _spawnWorker(index);
  }

  Future<void> _reclaimExtraWorkers() async {
    if (_isShuttingDown || config.workerIdleTimeout <= Duration.zero) return;
    if (activeChunkIndices.isNotEmpty || !_hasExtraWorkersToReclaim) return;

    _expansionGeneration++;
    _backgroundExpansionStarted = false;

    final extraIds = _workers.keys
        .where((id) => id >= 1 && !(_workers[id]?.isBusy ?? true))
        .toList();
    for (final id in extraIds) {
      final handle = _workers.remove(id);
      if (handle != null) {
        handle.sendPort.send({'command': 'shutdown'});
      }
    }
  }

  /// 提交下载任务到空闲 Worker；无空闲 Worker 时返回 false。
  /// Submits a download task to an available worker; returns false when none are idle.
  Future<bool> submitTask(DownloadTask task) async {
    if (_isShuttingDown || maxPoolSize <= 0) return false;

    notifyActivity();
    await ensureReady();

    final worker = _findAvailableWorker();
    if (worker == null) return false;

    worker.isBusy = true;
    worker.currentChunkIndex = task.chunkIndex;
    final msg = task.toMessage();
    msg['command'] = 'download';
    worker.sendPort.send(msg);
    return true;
  }

  _WorkerHandle? _findAvailableWorker() {
    if (_workers.isEmpty || maxPoolSize <= 0) return null;

    for (int i = 0; i < maxPoolSize; i++) {
      final int id = (_nextRoundRobin + i) % maxPoolSize;
      final handle = _workers[id];
      if (handle != null && !handle.isBusy) {
        _nextRoundRobin = (id + 1) % maxPoolSize;
        return handle;
      }
    }
    return null;
  }

  bool get hasAvailableWorker {
    if (_workers.values.any((w) => !w.isBusy)) return true;
    if (!_isShuttingDown && _workers.length < maxPoolSize) return true;
    return false;
  }

  /// 取消指定分片的下载（不立即释放 Worker，等待 cancelled 事件）。
  /// Cancels the download of the specified chunk (worker released upon cancelled event).
  void cancelChunk(int chunkIndex) {
    notifyActivity();
    for (final w in _workers.values) {
      if (w.currentChunkIndex == chunkIndex) {
        w.sendPort.send({'command': 'cancel'});
        break;
      }
    }
  }

  /// 取消所有正在进行的下载并立即释放 Worker。
  /// Cancels all in-progress downloads and immediately marks workers as available.
  void cancelAll() {
    notifyActivity();
    for (final w in _workers.values) {
      if (w.isBusy) {
        w.sendPort.send({'command': 'cancel'});
        w.isBusy = false;
        w.currentChunkIndex = null;
      }
    }
  }

  Set<int> get activeChunkIndices {
    return _workers.values
        .where((w) => w.isBusy && w.currentChunkIndex != null)
        .map((w) => w.currentChunkIndex!)
        .toSet();
  }

  /// 关闭所有 Worker 并释放资源。
  /// Shuts down all workers and releases resources.
  Future<void> shutdown() async {
    _isShuttingDown = true;
    notifyActivity();
    for (final w in _workers.values) {
      w.sendPort.send({'command': 'shutdown'});
    }
    _workers.clear();
    _isInitialized = false;
    _initCompleter = null;
    _backgroundExpansionStarted = false;
    _nextRoundRobin = 0;
    _hasPendingTasksChecker = null;
    if (!_progressController.isClosed) {
      await _progressController.close();
    }
  }
}
