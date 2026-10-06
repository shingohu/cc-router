import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Immutable Package identity resolved for one analyzed source file.
final class CCRouterSourcePackageContext {
  /// Creates a context rooted at the Package owning an analyzed source.
  const CCRouterSourcePackageContext({required this.root, required this.name});

  /// Absolute Package root containing `pubspec.yaml`.
  final String root;

  /// Package name read from the owning manifest.
  final String name;
}

/// Cached Package identity plus a cheap manifest change fingerprint.
final class _CCRouterPackageContextCacheEntry {
  /// Creates one entry from a resolved context and current manifest stat.
  const _CCRouterPackageContextCacheEntry({
    required this.context,
    required this.modifiedMilliseconds,
    required this.size,
  });

  /// Resolved Package identity returned to the analyzer.
  final CCRouterSourcePackageContext context;

  /// Last manifest modification time observed by the cache.
  final int modifiedMilliseconds;

  /// Last manifest byte size observed by the cache.
  final int size;
}

/// Bounded Plugin-owned cache for source directory to Package identity.
///
/// Entries retain only path strings and Package names. They do not retain AST,
/// source buffers, AnalysisContext, ResourceProvider, or application objects.
/// Pubspec watch events explicitly invalidate affected entries, while the LRU
/// bound prevents an Analysis Server process from growing with every Package
/// ever opened during its lifetime.
final class CCRouterPackageContextCache {
  /// Creates a cache with a positive maximum number of source directories.
  CCRouterPackageContextCache({this.maximumEntries = 128})
    : assert(maximumEntries > 0);

  /// Maximum retained source-directory lookups.
  final int maximumEntries;

  /// Least-recently-used contexts keyed by normalized source directory.
  final LinkedHashMap<String, _CCRouterPackageContextCacheEntry> _entries =
      LinkedHashMap<String, _CCRouterPackageContextCacheEntry>();

  /// Number of currently retained directory lookups.
  int get entryCount => _entries.length;

  /// Resolves the nearest Package and refreshes its LRU position.
  CCRouterSourcePackageContext? resolve(String filePath) {
    final directory = path.normalize(File(filePath).absolute.parent.path);
    final cached = _entries.remove(directory);
    if (cached != null && _manifestMatches(cached)) {
      _entries[directory] = cached;
      return cached.context;
    }
    final resolved = _discover(directory);
    if (resolved == null) return null;
    final entry = _entryFor(resolved);
    if (entry == null) return null;
    _entries[directory] = entry;
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
    return entry.context;
  }

  /// Invalidates contexts owned by changed Package identity or role inputs.
  void invalidate(String changedPath) {
    if (!const {
      'pubspec.yaml',
      '.metadata',
      'ccrouter.yaml',
    }.contains(path.basename(changedPath))) {
      return;
    }
    final root = path.normalize(File(changedPath).absolute.parent.path);
    _entries.removeWhere((_, entry) => entry.context.root == root);
  }

  /// Releases all retained path and Package identity strings.
  void clear() => _entries.clear();

  /// Discovers one Package by walking toward the filesystem root.
  static CCRouterSourcePackageContext? _discover(String directory) {
    var current = Directory(directory);
    while (true) {
      final manifest = File(path.join(current.path, 'pubspec.yaml'));
      final name = _readPackageName(manifest);
      if (name != null) {
        return CCRouterSourcePackageContext(root: current.path, name: name);
      }
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
  }

  /// Verifies that a cached Package still exists with the same name.
  static bool _manifestMatches(_CCRouterPackageContextCacheEntry entry) {
    final manifest = File(path.join(entry.context.root, 'pubspec.yaml'));
    if (!manifest.existsSync()) return false;
    final stat = manifest.statSync();
    return stat.modified.millisecondsSinceEpoch == entry.modifiedMilliseconds &&
        stat.size == entry.size;
  }

  /// Captures one manifest fingerprint without retaining the file object.
  static _CCRouterPackageContextCacheEntry? _entryFor(
    CCRouterSourcePackageContext context,
  ) {
    final manifest = File(path.join(context.root, 'pubspec.yaml'));
    if (!manifest.existsSync()) return null;
    final stat = manifest.statSync();
    return _CCRouterPackageContextCacheEntry(
      context: context,
      modifiedMilliseconds: stat.modified.millisecondsSinceEpoch,
      size: stat.size,
    );
  }

  /// Reads one valid Package name without propagating malformed YAML.
  static String? _readPackageName(File manifest) {
    if (!manifest.existsSync()) return null;
    try {
      final document = loadYaml(manifest.readAsStringSync());
      final name = document is YamlMap ? document['name'] : null;
      return name is String && name.isNotEmpty ? name : null;
    } on Object {
      return null;
    }
  }
}
