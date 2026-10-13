import 'dart:async';
import 'dart:collection';
import 'dart:io';

/// Reads exact snapshot bytes with a shared, bounded file-I/O budget.
///
/// Every capture owns its results; no bytes survive in a cross-cycle cache.
/// Failure drains reads already in flight before returning to rollback code.
final class CCGenerationFileReader {
  /// Creates an independent budget, also usable by differential benchmarks.
  CCGenerationFileReader({this.maxConcurrentReads = 4}) {
    if (maxConcurrentReads < 1 || maxConcurrentReads > 8) {
      throw RangeError.range(maxConcurrentReads, 1, 8, 'maxConcurrentReads');
    }
  }

  /// Restores sequential exact-byte reads for timing and correctness A/B.
  static const killSwitch = 'CCROUTER_DISABLE_PARALLEL_FILE_READS';

  /// Budget shared by simultaneous snapshots in this isolate.
  static final shared = CCGenerationFileReader(
    maxConcurrentReads: Platform.environment[killSwitch] == '1' ? 1 : 4,
  );

  /// Maximum reads in flight across all captures using this reader.
  final int maxConcurrentReads;

  /// Captures awaiting a permit; these hold no open file descriptors.
  final _waiters = ListQueue<Completer<void>>();

  /// Permits currently held, including transfers to queued workers.
  int _active = 0;

  /// Reads all files, preserving the caller's logical names and iteration order.
  ///
  /// Missing, unreadable, or concurrently removed files fail the capture. The
  /// lowest input-position failure among in-flight reads is rethrown with its
  /// original stack after workers settle; partial results are never published.
  Future<Map<String, List<int>>> readAll(Map<String, File> files) async {
    final entries = files.entries.toList(growable: false);
    final contents = List<List<int>?>.filled(entries.length, null);
    var next = 0;
    _ReadFailure? failure;

    Future<void> worker() async {
      while (next < entries.length && failure == null) {
        final index = next++;
        await _acquire();
        try {
          if (failure != null) return;
          contents[index] = await entries[index].value.readAsBytes();
        } catch (error, stack) {
          if (failure == null || index < failure!.index) {
            failure = _ReadFailure(index, error, stack);
          }
        } finally {
          _release();
        }
      }
    }

    final workers = entries.length < maxConcurrentReads
        ? entries.length
        : maxConcurrentReads;
    await Future.wait<void>(List.generate(workers, (_) => worker()));
    final failed = failure;
    if (failed != null) Error.throwWithStackTrace(failed.error, failed.stack);
    return <String, List<int>>{
      for (var index = 0; index < entries.length; index++)
        entries[index].key: contents[index]!,
    };
  }

  /// Acquires a permit or waits in FIFO order without opening a file.
  Future<void> _acquire() async {
    if (_active < maxConcurrentReads) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    await waiter.future;
  }

  /// Transfers ownership to a waiter or releases the completed read's permit.
  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _active--;
    }
  }
}

/// One capture-local failure retained only until its workers finish.
final class _ReadFailure {
  /// Keeps the logical position and original error evidence for propagation.
  const _ReadFailure(this.index, this.error, this.stack);

  /// Input position used to make simultaneous failures deterministic.
  final int index;

  /// Original filesystem error, never converted into missing-file success.
  final Object error;

  /// Original failing read's stack trace.
  final StackTrace stack;
}
