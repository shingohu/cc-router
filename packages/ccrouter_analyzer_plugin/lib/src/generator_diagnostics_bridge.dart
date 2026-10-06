import 'dart:convert';
import 'dart:io';

import 'package:analyzer/source/line_info.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:ccrouter_analyzer_plugin/src/project_context.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Environment switch that disables only Analyzer consumption of watch state.
const String ccrouterAnalyzerWatchBridgeKillSwitch =
    'CCROUTER_DISABLE_ANALYZER_WATCH_BRIDGE';

/// One validated Generator diagnostic mapped to an authored Dart file.
final class CCRouterBridgedGeneratorDiagnostic {
  /// Creates a source-positioned diagnostic from a trusted watch snapshot.
  const CCRouterBridgedGeneratorDiagnostic({
    required this.path,
    required this.line,
    required this.column,
    required this.length,
    required this.code,
    required this.message,
    required this.correction,
    required this.severity,
  });

  /// Absolute authored Dart path resolved through `package_config.json`.
  final String path;

  /// One-based source line recorded by generated metadata.
  final int line;

  /// One-based source column recorded by generated metadata.
  final int column;

  /// Positive source length for the IDE underline.
  final int length;

  /// Stable Generator diagnostic identity.
  final String code;

  /// Human-readable root-cause message.
  final String message;

  /// Conservative corrective action supplied by the Generator.
  final String correction;

  /// Analysis Server severity translated from the Generator schema.
  final AnalysisErrorSeverity severity;

  /// Converts one-based metadata coordinates to the current source buffer.
  CCRouterAnalyzerDiagnostic toAnalyzerDiagnostic(
    String source,
    LineInfo lineInfo,
  ) {
    final lineIndex = (line - 1).clamp(0, lineInfo.lineCount - 1);
    final lineOffset = lineInfo.getOffsetOfLine(lineIndex);
    final nextLineOffset = lineIndex + 1 < lineInfo.lineCount
        ? lineInfo.getOffsetOfLine(lineIndex + 1)
        : source.length;
    final offset = (lineOffset + column - 1).clamp(lineOffset, nextLineOffset);
    final effectiveLength = length.clamp(1, source.length - offset + 1);
    return CCRouterAnalyzerDiagnostic(
      offset: offset,
      length: effectiveLength,
      code: code,
      message: message,
      correction: correction,
      severity: severity,
    );
  }
}

/// Narrow warning that a saved manifest no longer matches Pub resolution.
final class CCRouterPubResolutionHint {
  /// Creates one `pubspec.yaml` warning at an exact source span.
  const CCRouterPubResolutionHint({
    required this.offset,
    required this.length,
    required this.message,
    required this.correction,
  });

  /// UTF-16 offset in `pubspec.yaml`.
  final int offset;

  /// Positive span covering the dependency section label.
  final int length;

  /// Bounded mismatch summary without ownership conclusions.
  final String message;

  /// Pub command required to refresh the resolved graph.
  final String correction;
}

/// Read-only bridge from versioned watch snapshots to Analysis Server input.
///
/// The bridge accepts diagnostics only when `status.json` and
/// `diagnostics.json` agree on Host, session, cycle, event revision, and exact
/// resolution fingerprint. It never parses console output or runs generation.
final class CCRouterGeneratorDiagnosticsBridge {
  /// Creates a bridge using the process environment or a deterministic test
  /// override to evaluate its independent kill switch once.
  CCRouterGeneratorDiagnosticsBridge({Map<String, String>? environment})
    : enabled =
          (environment ??
              Platform.environment)[ccrouterAnalyzerWatchBridgeKillSwitch] !=
          '1';

  /// File name of the atomically published structured diagnostics snapshot.
  static const String diagnosticsFileName = 'diagnostics.json';

  /// File name of the watch identity and lifecycle snapshot.
  static const String statusFileName = 'status.json';

  /// Last source paths published per Host, retained only to clear recovered
  /// diagnostics after the current snapshot becomes empty or invalid.
  final Map<String, Set<String>> _publishedPathsByHost =
      <String, Set<String>>{};

  /// Last watch snapshot file identity observed by the polling fallback.
  final Map<String, String> _observedSnapshotByHost = <String, String>{};

  /// Last manifest and resolved-graph file identity observed per Host.
  final Map<String, String> _observedResolutionInputByHost = <String, String>{};

  /// Whether the bridge is enabled for this Analysis Server process.
  final bool enabled;

  /// Whether [changedPath] can alter bridged diagnostics or resolution hints.
  bool isBridgeInput(String changedPath) {
    final normalized = path.normalize(changedPath);
    return normalized.endsWith(
          path.join('.dart_tool', 'ccrouter', 'v1', 'watch', statusFileName),
        ) ||
        normalized.endsWith(
          path.join(
            '.dart_tool',
            'ccrouter',
            'v1',
            'watch',
            diagnosticsFileName,
          ),
        ) ||
        path.basename(normalized) == 'pubspec.yaml' ||
        path.basename(normalized) == '.metadata' ||
        path.basename(normalized) == 'ccrouter.yaml' ||
        normalized.endsWith(
          path.join('.dart_tool', 'pub', 'workspace_ref.json'),
        ) ||
        normalized.endsWith(path.join('.dart_tool', 'package_graph.json')) ||
        normalized.endsWith(path.join('.dart_tool', 'package_config.json'));
  }

  /// Resolves every authored Dart file mentioned by the current snapshot.
  Set<String> affectedDartPaths(String changedPath) {
    if (!enabled || !isBridgeInput(changedPath)) return const <String>{};
    final hostRoot = _hostRootForInput(changedPath);
    if (hostRoot == null) return const <String>{};
    return _affectedDartPathsForHost(hostRoot);
  }

  /// Polls the two bounded watch snapshots when Analysis Server excludes
  /// `.dart_tool` changes from its filesystem event stream.
  Set<String> pollAffectedDartPaths(Directory hostRoot) {
    if (!enabled) return const <String>{};
    final key = _canonicalDirectoryIdentity(hostRoot.path);
    final signature =
        '${_fileIdentity(_statusFile(hostRoot))}|'
        '${_fileIdentity(_diagnosticsFile(hostRoot))}';
    if (_observedSnapshotByHost[key] == signature) {
      return const <String>{};
    }
    _observedSnapshotByHost[key] = signature;
    return _affectedDartPathsForHost(hostRoot);
  }

  /// Reports whether project role inputs or the resolved Package graph changed.
  ///
  /// The first observation establishes a baseline because initial context
  /// setup already publishes the current hint.
  bool pollPubResolutionChanged(Directory hostRoot) {
    if (!enabled) return false;
    final context = CCRouterAnalyzerProjectContext.resolve(hostRoot.path);
    if (context == null) return false;
    final requestedRoot = context.requestedRoot;
    final resolutionRoot = context.resolutionRoot;
    final signature = [
      _fileIdentity(File(path.join(requestedRoot.path, 'pubspec.yaml'))),
      _fileIdentity(File(path.join(requestedRoot.path, '.metadata'))),
      _fileIdentity(File(path.join(requestedRoot.path, 'ccrouter.yaml'))),
      _fileIdentity(
        File(
          path.join(
            requestedRoot.path,
            '.dart_tool',
            'pub',
            'workspace_ref.json',
          ),
        ),
      ),
      _fileIdentity(
        File(
          path.join(resolutionRoot.path, '.dart_tool', 'package_graph.json'),
        ),
      ),
      _fileIdentity(
        File(
          path.join(resolutionRoot.path, '.dart_tool', 'package_config.json'),
        ),
      ),
    ].join('|');
    final key = _canonicalDirectoryIdentity(requestedRoot.path);
    final previous = _observedResolutionInputByHost[key];
    _observedResolutionInputByHost[key] = signature;
    return previous != null && previous != signature;
  }

  /// Resolves both newly published and previously visible diagnostic paths.
  Set<String> _affectedDartPathsForHost(Directory hostRoot) {
    final snapshot = _validatedSnapshot(hostRoot);
    final current = snapshot == null
        ? <String>{}
        : {
            for (final diagnostic in _decodeDiagnostics(snapshot))
              diagnostic.path,
          };
    final key = _canonicalDirectoryIdentity(hostRoot.path);
    final affected = <String>{...?_publishedPathsByHost[key], ...current};
    if (current.isEmpty) {
      _publishedPathsByHost.remove(key);
    } else {
      _publishedPathsByHost[key] = Set.unmodifiable(current);
    }
    return affected;
  }

  /// Returns current Generator diagnostics whose primary source is [filePath].
  List<CCRouterBridgedGeneratorDiagnostic> diagnosticsFor(String filePath) {
    if (!enabled) return const <CCRouterBridgedGeneratorDiagnostic>[];
    final hostRoot = _discoverHostRoot(filePath);
    if (hostRoot == null) {
      return const <CCRouterBridgedGeneratorDiagnostic>[];
    }
    final snapshot = _validatedSnapshot(hostRoot);
    if (snapshot == null) {
      return const <CCRouterBridgedGeneratorDiagnostic>[];
    }
    final sourcePath = path.normalize(File(filePath).absolute.path);
    final sourceIdentity = _canonicalFileIdentity(sourcePath);
    final diagnostics = _decodeDiagnostics(snapshot)
        .where(
          (diagnostic) => path.equals(
            _canonicalFileIdentity(diagnostic.path),
            sourceIdentity,
          ),
        )
        .toList(growable: false);
    if (diagnostics.isNotEmpty) {
      final key = _canonicalDirectoryIdentity(hostRoot.path);
      _publishedPathsByHost[key] = Set.unmodifiable({
        ...?_publishedPathsByHost[key],
        sourcePath,
      });
    }
    return diagnostics;
  }

  /// Drops process-local publication memory when Analysis contexts reset.
  void clear() {
    _publishedPathsByHost.clear();
    _observedSnapshotByHost.clear();
    _observedResolutionInputByHost.clear();
  }

  /// Compares one participating Package manifest with its resolved direct graph.
  CCRouterPubResolutionHint? pubResolutionHint(File pubspec) {
    if (!enabled || !pubspec.existsSync()) return null;
    final context = CCRouterAnalyzerProjectContext.resolve(pubspec.path);
    if (context == null || context.role == CCRouterAnalyzerProjectRole.skip) {
      return null;
    }
    final graph = _readObject(
      File(
        path.join(
          context.resolutionRoot.path,
          '.dart_tool',
          'package_graph.json',
        ),
      ),
    );
    if (graph == null) return null;
    late final String contents;
    late final Object? manifest;
    try {
      contents = pubspec.readAsStringSync();
      manifest = loadYaml(contents);
    } on Object {
      return null;
    }
    if (manifest is! YamlMap) return null;
    final packageName = manifest['name'];
    final dependencies = manifest['dependencies'];
    if (packageName is! String || dependencies is! YamlMap) return null;
    final declared = dependencies.keys.whereType<String>().toSet();
    Map? resolvedPackage;
    final packages = graph['packages'];
    if (packages is List) {
      for (final candidate in packages.whereType<Map>()) {
        if (candidate['name'] == packageName) {
          resolvedPackage = candidate;
          break;
        }
      }
    }
    if (resolvedPackage == null) return null;
    final resolved = switch (resolvedPackage['dependencies']) {
      final List values => values.whereType<String>().toSet(),
      _ => <String>{},
    };
    if (!declared.contains('ccrouter') &&
        !resolved.contains('ccrouter') &&
        !declared.contains('ccrouter_contracts') &&
        !resolved.contains('ccrouter_contracts')) {
      return null;
    }
    final unresolvedAdds = declared.difference(resolved).toList()..sort();
    final unresolvedRemovals = resolved.difference(declared).toList()..sort();
    if (unresolvedAdds.isEmpty && unresolvedRemovals.isEmpty) return null;
    final dependencyOffset = contents.indexOf(
      RegExp(r'^dependencies\s*:', multiLine: true),
    );
    final offset = dependencyOffset < 0 ? 0 : dependencyOffset;
    final summary = <String>[
      if (unresolvedAdds.isNotEmpty)
        'not resolved: ${unresolvedAdds.take(5).join(', ')}',
      if (unresolvedRemovals.isNotEmpty)
        'still resolved: ${unresolvedRemovals.take(5).join(', ')}',
    ].join('; ');
    final roleLabel = context.role == CCRouterAnalyzerProjectRole.host
        ? 'Host'
        : 'Package';
    final pubTool = context.isFlutterProject ? 'flutter' : 'dart';
    return CCRouterPubResolutionHint(
      offset: offset,
      length: dependencyOffset < 0 ? 1 : 'dependencies'.length,
      message:
          'Saved $roleLabel dependencies do not match the resolved Pub graph '
          '($summary). CCRouter ownership conclusions are suspended until Pub '
          'resolution is refreshed.',
      correction:
          'Run `fvm $pubTool pub get` for this ${roleLabel.toLowerCase()}.',
    );
  }

  /// Resolves one diagnostics snapshot only when its paired status is current.
  Map<String, Object?>? _validatedSnapshot(Directory hostRoot) {
    final status = _readObject(_statusFile(hostRoot));
    final snapshot = _readObject(_diagnosticsFile(hostRoot));
    if (status == null || snapshot == null) return null;
    if (status['schemaVersion'] != 1 || snapshot['schemaVersion'] != 1) {
      return null;
    }
    if (status['active'] != true ||
        snapshot['lastEvent'] != 'failed' ||
        snapshot['cycleResolutionState'] != 'matched') {
      return null;
    }
    final statusHostRoot = status['hostRoot'];
    final snapshotHostRoot = snapshot['hostRoot'];
    final statusBuildRoot = status['buildRoot'];
    final snapshotBuildRoot = snapshot['buildRoot'];
    if (statusHostRoot is! String ||
        snapshotHostRoot is! String ||
        statusBuildRoot is! String ||
        snapshotBuildRoot is! String ||
        !_hasSameDirectoryIdentity(statusHostRoot, snapshotHostRoot) ||
        !_hasSameDirectoryIdentity(statusBuildRoot, snapshotBuildRoot) ||
        !_hasSameDirectoryIdentity(statusHostRoot, hostRoot.path)) {
      return null;
    }
    for (final key in const <String>[
      'sessionId',
      'eventRevision',
      'cycle',
      'resolutionFingerprint',
    ]) {
      if (status[key] != snapshot[key]) return null;
    }
    final diagnostics = snapshot['diagnostics'];
    return diagnostics is List ? snapshot : null;
  }

  /// Decodes bounded primary and related locations from one trusted snapshot.
  List<CCRouterBridgedGeneratorDiagnostic> _decodeDiagnostics(
    Map<String, Object?> snapshot,
  ) {
    final buildRootValue = snapshot['buildRoot'];
    final diagnostics = snapshot['diagnostics'];
    if (buildRootValue is! String || diagnostics is! List) {
      return const <CCRouterBridgedGeneratorDiagnostic>[];
    }
    final roots = _packageRoots(Directory(buildRootValue));
    final result = <CCRouterBridgedGeneratorDiagnostic>[];
    for (final raw in diagnostics.whereType<Map>().take(100)) {
      final diagnostic = raw.cast<Object?, Object?>();
      final location = diagnostic['primaryLocation'];
      if (location is! Map) continue;
      final resolved = _resolveLocation(location, roots);
      if (resolved == null || !resolved.path.endsWith('.dart')) continue;
      result.add(
        CCRouterBridgedGeneratorDiagnostic(
          path: resolved.path,
          line: resolved.line,
          column: resolved.column,
          length: resolved.length,
          code: '${diagnostic['code'] ?? 'ccrouter_generation_failed'}',
          message: '${diagnostic['message'] ?? 'CCRouter generation failed.'}',
          correction:
              '${diagnostic['correction'] ?? 'Run CCRouter generation and inspect its diagnostics.'}',
          severity: switch (diagnostic['severity']) {
            'warning' => AnalysisErrorSeverity.WARNING,
            'information' => AnalysisErrorSeverity.INFO,
            _ => AnalysisErrorSeverity.ERROR,
          },
        ),
      );
    }
    return List.unmodifiable(result);
  }

  /// Reads Package roots used to resolve portable diagnostic URIs.
  Map<String, Uri> _packageRoots(Directory buildRoot) {
    final configFile = File(
      path.join(buildRoot.path, '.dart_tool', 'package_config.json'),
    );
    final config = _readObject(configFile);
    final packages = config?['packages'];
    if (packages is! List) return const <String, Uri>{};
    final result = <String, Uri>{};
    for (final raw in packages.whereType<Map>()) {
      final name = raw['name'];
      final rootUri = raw['rootUri'];
      final packageUri = raw['packageUri'];
      if (name is! String || rootUri is! String) continue;
      final root = configFile.uri.resolve(rootUri);
      result[name] = root.resolve(packageUri is String ? packageUri : 'lib/');
    }
    return result;
  }

  /// Resolves one `package:` location through the current Package config.
  ({String path, int line, int column, int length})? _resolveLocation(
    Map location,
    Map<String, Uri> roots,
  ) {
    final uriValue = location['uri'];
    if (uriValue is! String || !uriValue.startsWith('package:')) return null;
    final uri = Uri.tryParse(uriValue);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    final packageRoot = roots[uri.pathSegments.first];
    if (packageRoot == null) return null;
    final relative = uri.pathSegments.skip(1).join('/');
    final resolved = packageRoot.resolve(relative);
    if (resolved.scheme != 'file') return null;
    return (
      path: path.normalize(resolved.toFilePath()),
      line: _positiveInt(location['line']) ?? 1,
      column: _positiveInt(location['column']) ?? 1,
      length: _positiveInt(location['length']) ?? 1,
    );
  }

  /// Finds the nearest Host carrying a watch diagnostics directory.
  Directory? _discoverHostRoot(String filePath) {
    var current = File(filePath).absolute.parent;
    while (true) {
      if (_diagnosticsFile(current).existsSync() ||
          _statusFile(current).existsSync()) {
        return current;
      }
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
  }

  /// Extracts a Host root from an exact watch snapshot path.
  Directory? _hostRootForInput(String changedPath) {
    final normalized = path.normalize(File(changedPath).absolute.path);
    final watchSuffix = path.join('.dart_tool', 'ccrouter', 'v1', 'watch');
    final marker = '${path.separator}$watchSuffix${path.separator}';
    final markerIndex = normalized.lastIndexOf(marker);
    if (markerIndex >= 0) {
      return Directory(normalized.substring(0, markerIndex));
    }
    return _discoverHostRoot(changedPath);
  }

  /// Reads a JSON object and treats replacement races as unavailable evidence.
  Map<String, Object?>? _readObject(File file) {
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }

  /// Uses stable filesystem metadata to avoid repeatedly parsing Package graph.
  String _fileIdentity(File file) {
    try {
      final stat = file.statSync();
      return '${stat.type}:${stat.size}:'
          '${stat.modified.microsecondsSinceEpoch}:'
          '${stat.changed.microsecondsSinceEpoch}';
    } on Object {
      return 'missing';
    }
  }

  /// Returns a positive integer or null for malformed external state.
  int? _positiveInt(Object? value) => value is int && value > 0 ? value : null;

  /// Current Host watch status file.
  File _statusFile(Directory hostRoot) => File(
    path.join(
      hostRoot.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      statusFileName,
    ),
  );

  /// Current Host structured diagnostics file.
  File _diagnosticsFile(Directory hostRoot) => File(
    path.join(
      hostRoot.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      diagnosticsFileName,
    ),
  );
}

/// Returns one stable directory identity across symlinks and platform aliases.
String _canonicalDirectoryIdentity(String value) {
  final directory = Directory(value).absolute;
  try {
    return path.normalize(directory.resolveSymbolicLinksSync());
  } on FileSystemException {
    return path.normalize(directory.path);
  }
}

/// Returns one stable file identity while preserving missing-path diagnostics.
String _canonicalFileIdentity(String value) {
  final file = File(value).absolute;
  try {
    return path.normalize(file.resolveSymbolicLinksSync());
  } on FileSystemException {
    return path.normalize(file.path);
  }
}

/// Reports whether two directory spellings identify the same filesystem root.
bool _hasSameDirectoryIdentity(String first, String second) => path.equals(
  _canonicalDirectoryIdentity(first),
  _canonicalDirectoryIdentity(second),
);
