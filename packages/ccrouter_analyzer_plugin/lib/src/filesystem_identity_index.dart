import 'dart:io';

import 'package:path/path.dart' as path;

/// Result of one exact filesystem identity poll.
final class CCRouterFilesystemPollResult {
  /// Creates one immutable result from changed registrations and affected paths.
  CCRouterFilesystemPollResult({
    required Iterable<String> changedRegistrations,
    required Iterable<String> affectedPaths,
    required this.inspectedPathCount,
  }) : changedRegistrations = Set.unmodifiable(changedRegistrations),
       affectedPaths = Set.unmodifiable(affectedPaths);

  /// Registration identities whose watched inputs changed.
  final Set<String> changedRegistrations;

  /// Authored paths that must be reanalyzed after those changes.
  final Set<String> affectedPaths;

  /// Unique filesystem paths inspected during this poll.
  final int inspectedPathCount;
}

/// Exact-path identity index shared by Analyzer polling fallbacks.
///
/// Registrations retain their own affected paths while shared watched inputs
/// are inspected once per poll. This class does not discover files or infer
/// dependencies; callers must register paths proven by resolved analysis.
final class CCRouterFilesystemIdentityIndex {
  /// Registrations keyed by caller-owned stable identity.
  final Map<String, _FilesystemRegistration> _registrations = {};

  /// Reverse index allowing one changed path to invalidate all registrations.
  final Map<String, Set<String>> _registrationsByPath = {};

  /// Last exact identity observed for each unique watched path.
  final Map<String, String> _identityByPath = {};

  /// Number of unique exact paths currently retained.
  int get watchedPathCount => _identityByPath.length;

  /// Caller-owned registration identities currently retained by this index.
  Set<String> get registrationIdentities =>
      Set.unmodifiable(_registrations.keys);

  /// All authored paths affected by currently retained registrations.
  Set<String> get affectedPaths => Set.unmodifiable({
    for (final registration in _registrations.values)
      ...registration.affectedPaths,
  });

  /// Adds or atomically replaces one caller-owned registration.
  void replace(
    String registration, {
    required Iterable<String> watchedPaths,
    required Iterable<String> affectedPaths,
  }) {
    remove(registration);
    final watched = {
      for (final watchedPath in watchedPaths) _normalize(watchedPath),
    };
    if (watched.isEmpty) return;
    final entry = _FilesystemRegistration(
      watchedPaths: Set.unmodifiable(watched),
      affectedPaths: Set.unmodifiable(affectedPaths.map(_normalize)),
    );
    _registrations[registration] = entry;
    for (final watchedPath in entry.watchedPaths) {
      final registrations = _registrationsByPath.putIfAbsent(
        watchedPath,
        () => <String>{},
      );
      registrations.add(registration);
      _identityByPath.putIfAbsent(
        watchedPath,
        () => _fileIdentity(watchedPath),
      );
    }
  }

  /// Removes one registration and releases paths no other owner observes.
  void remove(String registration) {
    final previous = _registrations.remove(registration);
    if (previous == null) return;
    for (final watchedPath in previous.watchedPaths) {
      final registrations = _registrationsByPath[watchedPath];
      registrations?.remove(registration);
      if (registrations == null || registrations.isNotEmpty) continue;
      _registrationsByPath.remove(watchedPath);
      _identityByPath.remove(watchedPath);
    }
  }

  /// Inspects every registered path as a fallback for dropped server events.
  CCRouterFilesystemPollResult pollAll() {
    final changedRegistrations = <String>{};
    for (final entry in _identityByPath.entries) {
      final current = _fileIdentity(entry.key);
      if (current == entry.value) continue;
      _identityByPath[entry.key] = current;
      changedRegistrations.addAll(
        _registrationsByPath[entry.key] ?? const <String>{},
      );
    }
    return _result(changedRegistrations, _identityByPath.length);
  }

  /// Inspects one deterministic shard of the registered exact paths.
  ///
  /// Calling every shard index from zero through [shardCount] minus one is
  /// equivalent to one [pollAll] pass, while distributing filesystem calls
  /// across multiple timer ticks.
  CCRouterFilesystemPollResult pollShard({
    required int shardIndex,
    required int shardCount,
  }) {
    if (shardCount <= 0 || shardIndex < 0 || shardIndex >= shardCount) {
      throw RangeError('Require 0 <= shardIndex < shardCount.');
    }
    final changedRegistrations = <String>{};
    var inspected = 0;
    for (final entry in _identityByPath.entries) {
      if (_stableShard(entry.key, shardCount) != shardIndex) continue;
      inspected++;
      final current = _fileIdentity(entry.key);
      if (current == entry.value) continue;
      _identityByPath[entry.key] = current;
      changedRegistrations.addAll(
        _registrationsByPath[entry.key] ?? const <String>{},
      );
    }
    return _result(changedRegistrations, inspected);
  }

  /// Inspects only exact registered [changedPaths] supplied by a file event.
  CCRouterFilesystemPollResult pollPaths(Iterable<String> changedPaths) {
    final changedRegistrations = <String>{};
    final inspected = <String>{};
    for (final candidate in changedPaths) {
      final watchedPath = _normalize(candidate);
      if (!_identityByPath.containsKey(watchedPath) ||
          !inspected.add(watchedPath)) {
        continue;
      }
      final current = _fileIdentity(watchedPath);
      if (current == _identityByPath[watchedPath]) continue;
      _identityByPath[watchedPath] = current;
      changedRegistrations.addAll(
        _registrationsByPath[watchedPath] ?? const <String>{},
      );
    }
    return _result(changedRegistrations, inspected.length);
  }

  /// Expands changed registration identities into authored refresh targets.
  CCRouterFilesystemPollResult _result(
    Set<String> changedRegistrations,
    int inspectedPathCount,
  ) {
    final affected = <String>{};
    for (final registration in changedRegistrations) {
      affected.addAll(
        _registrations[registration]?.affectedPaths ?? const <String>{},
      );
    }
    return CCRouterFilesystemPollResult(
      changedRegistrations: changedRegistrations,
      affectedPaths: affected,
      inspectedPathCount: inspectedPathCount,
    );
  }

  /// Releases every retained registration, path and filesystem identity.
  void clear() {
    _registrations.clear();
    _registrationsByPath.clear();
    _identityByPath.clear();
  }

  /// Normalizes one exact path without resolving symlinks that may disappear.
  static String _normalize(String candidate) =>
      path.normalize(File(candidate).absolute.path);

  /// Returns a stable identity for an existing or missing watched file.
  static String _fileIdentity(String filePath) {
    try {
      final stat = File(filePath).statSync();
      return '${stat.type}:${stat.size}:'
          '${stat.modified.microsecondsSinceEpoch}:'
          '${stat.changed.microsecondsSinceEpoch}';
    } on Object {
      return 'missing';
    }
  }

  /// Assigns a path to a stable process-independent FNV-1a shard.
  static int _stableShard(String value, int shardCount) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash % shardCount;
  }
}

/// One caller-owned mapping from exact inputs to authored refresh targets.
final class _FilesystemRegistration {
  /// Creates an immutable registration captured by the index.
  const _FilesystemRegistration({
    required this.watchedPaths,
    required this.affectedPaths,
  });

  /// Exact generated or metadata inputs observed for this registration.
  final Set<String> watchedPaths;

  /// Authored sources refreshed when any watched input changes.
  final Set<String> affectedPaths;
}
