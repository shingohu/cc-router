part of 'analyzer_bootstrap.dart';

/// Fixed paths are the only bootstrap source files managed by write commands.
const _analyzerOwnedFiles = [
  'pubspec.yaml',
  'tools/analyzer_plugin/pubspec.yaml',
  'tools/analyzer_plugin/pubspec.lock',
  'tools/analyzer_plugin/bin/plugin.dart',
];

/// Host-relative wrapper location; it is not a Workspace member.
const _analyzerWrapperPath = 'tool/ccrouter_analyzer_host';

/// Previous wrapper location retained for managed-installation compatibility.
const _legacyAnalyzerWrapperPath = 'tools/ccrouter_analyzer_host';

/// Host Analyzer exclusion for the loader's deliberately isolated Pub graph.
String _analyzerLoaderExcludeFor(String wrapperPath) =>
    '$wrapperPath/tools/analyzer_plugin/**';

/// Records ownership, content hashes, source identity, and reversible YAML leaves.
const _analyzerOwnershipFile = '.ccrouter-analyzer.json';

/// Stable isolated loader; application source never imports plugin internals.
const _analyzerLoader = '''// Managed by ccrouter analyzer. Do not edit.
import 'dart:isolate';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/starter.dart';
import 'package:ccrouter_analyzer_plugin/src/plugin.dart';

void main(List<String> args, SendPort sendPort) {
  ServerPluginStarter(
    CCRouterAnalyzerPlugin(PhysicalResourceProvider.INSTANCE),
  ).start(sendPort);
}
''';

/// Refuses symlink traversal through any target ancestor before reading/writing.
void _checkAnalyzerPath(String target) {
  var current = path.normalize(path.absolute(target));
  while (true) {
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Refusing Analyzer target through a symlink: $current');
    }
    final parent = path.dirname(current);
    if (parent == current) break;
    current = parent;
  }
}

/// Returns a file's bytes, distinguishing absent files from empty files.
List<int>? _analyzerBytes(String filePath) {
  _checkAnalyzerPath(filePath);
  final type = FileSystemEntity.typeSync(filePath, followLinks: false);
  if (type == FileSystemEntityType.notFound) return null;
  if (type != FileSystemEntityType.file) {
    throw StateError('Expected an ordinary file: $filePath');
  }
  return File(filePath).readAsBytesSync();
}

/// Compares snapshots including absent-file identity.
bool _sameAnalyzerBytes(List<int>? left, List<int>? right) =>
    left == null || right == null
    ? left == null && right == null
    : _bytesEqual(left, right);

/// One command's journal, retained on rollback conflict or process interruption.
/// Source writes are checked against the prior snapshot to preserve concurrent
/// user edits. Pub-owned resolution files are snapshotted separately.
final class _AnalyzerFileTransaction {
  _AnalyzerFileTransaction(this.directory);

  final Directory directory;
  final Map<String, List<int>?> _before = {};
  final Map<String, List<int>?> _written = {};
  final Set<String> _createdDirectories = {};
  final Set<String> _unreadablePubFiles = {};
  int _sequence = 0;

  /// Saves each exact original once, before the first command write or Pub run.
  void capture(String filePath) {
    if (_before.containsKey(filePath)) return;
    _before[filePath] = _analyzerBytes(filePath);
    directory.createSync(recursive: true);
    File(path.join(directory.path, 'originals.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        for (final entry in _before.entries)
          entry.key: entry.value == null ? null : base64Encode(entry.value!),
      }),
      flush: true,
    );
  }

  /// Replaces one file atomically, or removes a verified CLI-owned file.
  void write(String filePath, List<int>? bytes) {
    capture(filePath);
    final expected = _written.containsKey(filePath)
        ? _written[filePath]
        : _before[filePath];
    if (!_sameAnalyzerBytes(_analyzerBytes(filePath), expected)) {
      throw StateError('File changed concurrently; preserving $filePath');
    }
    _replace(filePath, bytes);
    _written[filePath] = bytes;
  }

  /// Captures the result of the explicitly invoked Pub command for rollback.
  void recordPubResult(Iterable<String> files) {
    for (final file in files) {
      try {
        _written[file] = _analyzerBytes(file);
      } on Object {
        _unreadablePubFiles.add(file);
      }
    }
    if (_unreadablePubFiles.isNotEmpty) {
      throw StateError(
        'Pub result could not be recorded; recovery journal retained.',
      );
    }
  }

  void _replace(String filePath, List<int>? bytes) {
    _checkAnalyzerPath(filePath);
    final file = File(filePath);
    if (bytes == null) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    var parent = file.parent;
    while (!parent.existsSync()) {
      _createdDirectories.add(parent.path);
      parent = parent.parent;
    }
    file.parent.createSync(recursive: true);
    final staged = File('$filePath.ccrouter-$pid-${_sequence++}.tmp');
    try {
      staged.writeAsBytesSync(bytes, flush: true);
      staged.renameSync(filePath);
    } finally {
      if (staged.existsSync()) staged.deleteSync();
    }
  }

  /// Restores only still-matching writes; unknown edits keep the journal intact.
  void rollback() {
    final conflicts = <String>[..._unreadablePubFiles];
    for (final entry in _written.entries.toList().reversed) {
      try {
        if (!_sameAnalyzerBytes(_analyzerBytes(entry.key), entry.value)) {
          conflicts.add(entry.key);
          continue;
        }
        _replace(entry.key, _before[entry.key]);
      } on Object {
        conflicts.add(entry.key);
      }
    }
    if (conflicts.isNotEmpty) {
      throw StateError(
        'Rollback preserved concurrent edits: ${conflicts.join(', ')}. '
        'Original bytes remain in ${directory.path}.',
      );
    }
    finish();
  }

  /// Removes only this command's private backup after success or full rollback.
  void finish() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    for (final created
        in _createdDirectories.toList()
          ..sort((a, b) => b.length.compareTo(a.length))) {
      final folder = Directory(created);
      if (folder.existsSync() && folder.listSync(followLinks: false).isEmpty)
        folder.deleteSync();
    }
  }
}

/// Reads a YAML object strictly; invalid syntax is never replaced with defaults.
Map<String, Object?> _analyzerYaml(String source, String label) {
  final value = loadYaml(source);
  if (value == null) return <String, Object?>{};
  if (value is! Map) throw FormatException('$label must be a YAML mapping.');
  return _stringKeyedMap(value);
}

/// Updates exactly one leaf while retaining unrelated YAML text and comments.
String _setAnalyzerLeaf(String source, List<String> keys, Object? value) {
  final editor = YamlEditor(source);
  if (editor.parseAt([]).value == null) editor.update([], <String, Object?>{});
  for (var length = 1; length < keys.length; length++) {
    final parent = keys.take(length).toList();
    if (editor.parseAt(parent, orElse: () => YamlScalar.wrap(null)).value ==
        null) {
      editor.update(parent, <String, Object?>{});
    }
  }
  editor.update(keys, value);
  return editor.toString();
}

/// Appends one scalar without replacing comments on existing list entries.
String _appendAnalyzerListItem(String source, List<String> keys, String value) {
  final editor = YamlEditor(source);
  final current = editor
      .parseAt(keys, orElse: () => YamlScalar.wrap(null))
      .value;
  if (current == null) return _setAnalyzerLeaf(source, keys, [value]);
  if (current is! List || current.any((entry) => entry is! String)) {
    throw StateError('${keys.join('.')} must be a YAML string list.');
  }
  editor.appendToList(keys, value);
  return editor.toString();
}

/// Removes one exact scalar and optionally removes its now-empty list leaf.
String _removeAnalyzerListItem(
  String source,
  List<String> keys,
  String value, {
  required bool removeLeaf,
}) {
  final editor = YamlEditor(source);
  final current = editor.parseAt(keys).value;
  if (current is! List || current.any((entry) => entry is! String)) {
    throw StateError('${keys.join('.')} must be a YAML string list.');
  }
  final index = current.indexOf(value);
  if (index < 0) {
    throw StateError('CLI-owned ${keys.join('.')} entry was removed.');
  }
  if (current.length == 1 && removeLeaf) {
    editor.remove(keys);
  } else {
    editor.remove([...keys, index]);
  }
  return editor.toString();
}

/// Removes CLI leaves; parents are removed only if CLI created them and empty.
String _removeAnalyzerLeaf(
  String source,
  List<String> keys, {
  required bool removeParent,
}) {
  final editor = YamlEditor(source)..remove(keys);
  final parent = keys.take(keys.length - 1).toList();
  if (removeParent && (editor.parseAt(parent).value as Map).isEmpty) {
    editor.remove(parent);
  }
  return editor.toString();
}

/// Bounded non-interactive subprocess; timeout always kills and reaps its child.
Future<ProcessResult> _runAnalyzerProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: {
      'CCROUTER_PUB_HOOK_DISABLE': '1',
      'GIT_TERMINAL_PROMPT': '0',
      ...?environment,
    },
  );
  var output = '';
  var errors = '';
  String append(String previous, String value) {
    final next = previous + value;
    return next.length <= 65536 ? next : next.substring(next.length - 65536);
  }

  final outDone = Completer<void>();
  final errDone = Completer<void>();
  final out = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(
        (value) => output = append(output, value),
        onDone: outDone.complete,
        onError: outDone.completeError,
      );
  final err = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(
        (value) => errors = append(errors, value),
        onDone: errDone.complete,
        onError: errDone.completeError,
      );
  try {
    await process.stdin.close();
    final results = await Future.wait<Object?>([
      process.exitCode,
      outDone.future,
      errDone.future,
    ]).timeout(const Duration(minutes: 3));
    final code = results.first as int;
    return ProcessResult(process.pid, code, output, errors);
  } on Object catch (error) {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    if (error is TimeoutException)
      throw StateError(
        'Analyzer subprocess timed out after 3 minutes: ${arguments.take(2).join(' ')}',
      );
    rethrow;
  } finally {
    await out.cancel();
    await err.cancel();
  }
}
