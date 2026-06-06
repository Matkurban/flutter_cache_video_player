import 'package:flutter_cache_video_player/src/core/constants.dart';
import 'package:flutter_cache_video_player/src/download/download_worker_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadWorkerPool idle reclaim', () {
    late DownloadWorkerPool pool;

    tearDown(() async {
      await pool.shutdown();
    });

    Future<void> waitForWorkers(
      Set<int> expected, {
      Duration timeout = const Duration(seconds: 5),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (pool.liveWorkerIds.containsAll(expected) &&
            pool.liveWorkerIds.length >= expected.length) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('Timed out waiting for workers $expected, got ${pool.liveWorkerIds}');
    }

    test('workerIdleTimeout zero disables reclaim', () async {
      pool = DownloadWorkerPool(
        maxPoolSize: 2,
        config: const CacheConfig(desktopWorkerCount: 2, workerIdleTimeout: Duration.zero),
      );

      await pool.ensureReady();
      await waitForWorkers({0, 1});

      pool.scheduleIdleReclamation(hasPendingTasks: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(pool.liveWorkerIds, containsAll([0, 1]));
    });

    test('reclaims expanded workers after idle timeout', () async {
      pool = DownloadWorkerPool(
        maxPoolSize: 2,
        config: const CacheConfig(
          desktopWorkerCount: 2,
          workerIdleTimeout: Duration(milliseconds: 50),
        ),
      );

      await pool.ensureReady();
      await waitForWorkers({0, 1});

      pool.scheduleIdleReclamation(hasPendingTasks: false);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(pool.liveWorkerIds, {0});
    });

    test('notifyActivity cancels pending reclaim', () async {
      pool = DownloadWorkerPool(
        maxPoolSize: 2,
        config: const CacheConfig(
          desktopWorkerCount: 2,
          workerIdleTimeout: Duration(milliseconds: 80),
        ),
      );

      await pool.ensureReady();
      await waitForWorkers({0, 1});

      pool.scheduleIdleReclamation(hasPendingTasks: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      pool.notifyActivity();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(pool.liveWorkerIds, containsAll([0, 1]));
    });

    test('does not reclaim when hasPendingTasks is true', () async {
      pool = DownloadWorkerPool(
        maxPoolSize: 2,
        config: const CacheConfig(
          desktopWorkerCount: 2,
          workerIdleTimeout: Duration(milliseconds: 50),
        ),
      );
      pool.setHasPendingTasksChecker(() => true);

      await pool.ensureReady();
      await waitForWorkers({0, 1});

      pool.scheduleIdleReclamation(hasPendingTasks: false);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(pool.liveWorkerIds, containsAll([0, 1]));
    });
  });
}
