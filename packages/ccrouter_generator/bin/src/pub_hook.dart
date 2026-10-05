import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'pub_hook_watch_coordination.dart';

/// The operation requested from the pub hook command.
enum CCPubHookAction {
  /// Installs a reversible wrapper around the selected Flutter SDK.
  install,

  /// Restores the original Flutter SDK entrypoints.
  uninstall,

  /// Reports whether the selected Flutter SDK is currently wrapped.
  status,

  /// Runs generation for a project after `flutter pub` or before `flutter run/build`.
  run,
}

/// Parsed options for the `ccrouter pub-hook` command.
final class CCPubHookRequest {
  /// Creates a pub hook request.
  const CCPubHookRequest({
    required this.action,
    this.sdkPath,
    this.projectRoot,
    this.pubCommand,
  });

  /// The requested pub hook operation.
  final CCPubHookAction action;

  /// Optional Flutter SDK root. When absent, the current SDK is discovered.
  final String? sdkPath;

  /// Project root used by the post-pub generation runner.
  final String? projectRoot;

  /// Pub subcommand that caused the hook, for diagnostics only.
  final String? pubCommand;
}

/// Installs and executes the CCRouter post-pub integration without changing
/// Flutter's internal tool snapshot or shared shell implementation.
final class CCPubHookManager {
  /// Creates a manager for [sdkRoot].
  CCPubHookManager(this.sdkRoot);

  /// The absolute Flutter SDK root being managed.
  final Directory sdkRoot;

  static const _originalPosixName = 'flutter.ccrouter-original';
  static const _originalWindowsName = 'flutter.ccrouter-original.bat';
  static const _markerName = '.ccrouter_pub_hook.json';

  /// Resolves the current Flutter SDK root from an explicit path, environment,
  /// the nearest FVM link, or the `flutter` executable on PATH, in that order.
  static Directory resolveSdk([String? explicitPath]) {
    final candidate = explicitPath ?? Platform.environment['FLUTTER_ROOT'];
    if (candidate != null && candidate.trim().isNotEmpty) {
      return _canonicalDirectory(candidate);
    }
    final fvmSdk = _findNearestFvmSdk(Directory.current);
    if (fvmSdk != null) return fvmSdk;
    final result = Process.runSync(Platform.isWindows ? 'where' : 'which', [
      'flutter',
    ]);
    if (result.exitCode == 0) {
      final executable = '${result.stdout}'
          .trim()
          .split(RegExp(r'[\r\n]+'))
          .first;
      if (executable.isNotEmpty) {
        final resolved = File(executable).resolveSymbolicLinksSync();
        return _canonicalDirectory(path.dirname(path.dirname(resolved)));
      }
    }
    throw const FileSystemException(
      'Unable to resolve the current Flutter SDK. Pass --sdk <path> or set FLUTTER_ROOT.',
    );
  }

  /// Installs wrappers and returns the selected SDK path.
  Future<Directory> install() async {
    final bin = Directory(path.join(sdkRoot.path, 'bin'));
    _validateSdk(bin);
    final marker = File(path.join(bin.path, _markerName));
    if (marker.existsSync()) {
      if (status()) return sdkRoot;
      throw const FileSystemException(
        'CCRouter pub hook marker exists but the SDK wrapper is inconsistent; refusing to overwrite it.',
      );
    }

    final posix = File(path.join(bin.path, 'flutter'));
    final posixOriginal = File(path.join(bin.path, _originalPosixName));
    final windows = File(path.join(bin.path, 'flutter.bat'));
    final windowsOriginal = File(path.join(bin.path, _originalWindowsName));
    _ensureBackupAbsent(posixOriginal, windowsOriginal);
    final moved = <({File source, File backup})>[];
    try {
      await posix.rename(posixOriginal.path);
      moved.add((source: posix, backup: posixOriginal));
      if (windows.existsSync()) {
        await windows.rename(windowsOriginal.path);
        moved.add((source: windows, backup: windowsOriginal));
      }
      await posix.writeAsString(_posixWrapper);
      await _makeExecutable(posix);
      if (windowsOriginal.existsSync()) {
        await windows.writeAsString(_windowsWrapper);
      }
      await marker.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object>{
          'schema': 3,
          'entrypoint': 'flutter',
          'generator': 'ccrouter_generator',
          'features': const <String>['pub', 'run', 'build', 'run-watch'],
        }),
      );
    } catch (_) {
      if (posix.existsSync()) await posix.delete();
      if (windows.existsSync()) await windows.delete();
      for (final item in moved.reversed) {
        if (item.backup.existsSync()) {
          await item.backup.rename(item.source.path);
        }
      }
      rethrow;
    }
    stdout.writeln(
      'Installed CCRouter pub hook in Flutter SDK: ${sdkRoot.path}',
    );
    stdout.writeln(
      'The hook runs after successful Flutter pub commands and before `flutter run/build`.',
    );
    if (!status()) {
      throw const FileSystemException(
        'CCRouter pub hook was written but failed verification.',
      );
    }
    return sdkRoot;
  }

  /// Restores the original entrypoints and removes the install marker.
  Future<bool> uninstall() async {
    final bin = Directory(path.join(sdkRoot.path, 'bin'));
    final marker = File(path.join(bin.path, _markerName));
    final posix = File(path.join(bin.path, 'flutter'));
    final posixOriginal = File(path.join(bin.path, _originalPosixName));
    final windows = File(path.join(bin.path, 'flutter.bat'));
    final windowsOriginal = File(path.join(bin.path, _originalWindowsName));
    if (!marker.existsSync()) {
      stdout.writeln('CCRouter pub hook is not installed: ${sdkRoot.path}');
      return false;
    }
    if (!posix.existsSync() ||
        !posixOriginal.existsSync() ||
        !_isPosixWrapper(posix)) {
      throw const FileSystemException(
        'CCRouter pub hook installation is incomplete; refusing to delete the SDK entrypoint.',
      );
    }
    if (windowsOriginal.existsSync() &&
        (!_isWindowsWrapper(windows) || !windows.existsSync())) {
      throw const FileSystemException(
        'CCRouter Windows pub hook installation is incomplete; refusing to delete the SDK entrypoint.',
      );
    }
    await posix.delete();
    await posixOriginal.rename(posix.path);
    if (windowsOriginal.existsSync()) {
      if (windows.existsSync()) await windows.delete();
      await windowsOriginal.rename(windows.path);
    }
    await marker.delete();
    stdout.writeln(
      'Removed CCRouter pub hook from Flutter SDK: ${sdkRoot.path}',
    );
    return true;
  }

  /// Prints the current install state without modifying the SDK.
  bool status() {
    final bin = Directory(path.join(sdkRoot.path, 'bin'));
    final marker = File(path.join(bin.path, _markerName));
    final posix = File(path.join(bin.path, 'flutter'));
    final posixOriginal = File(path.join(bin.path, _originalPosixName));
    final windows = File(path.join(bin.path, 'flutter.bat'));
    final windowsOriginal = File(path.join(bin.path, _originalWindowsName));
    final markerValid = _isMarker(marker);
    final posixValid = _isPosixWrapper(posix);
    final posixBackupPresent = posixOriginal.existsSync();
    final windowsExpected =
        windows.existsSync() || windowsOriginal.existsSync();
    final windowsValid =
        !windowsExpected ||
        (windows.existsSync() &&
            windowsOriginal.existsSync() &&
            _isWindowsWrapper(windows));
    final preflightEnabled =
        _supportsPreflight(posix) &&
        (!windowsExpected || _supportsPreflight(windows));
    final runWatchEnabled =
        _supportsRunWatch(posix) &&
        (!windowsExpected || _supportsRunWatch(windows));
    final installed =
        markerValid &&
        posixBackupPresent &&
        posixValid &&
        windowsValid &&
        preflightEnabled &&
        runWatchEnabled;
    stdout.writeln('CCRouter pub hook SDK: ${sdkRoot.path}');
    stdout.writeln(
      '  marker: ${marker.path} (${markerValid ? 'valid' : 'missing or invalid'})',
    );
    stdout.writeln(
      '  POSIX wrapper: ${posix.path} (${posixValid ? 'verified' : 'missing or invalid'})',
    );
    stdout.writeln(
      '  POSIX backup: ${posixOriginal.path} (${posixBackupPresent ? 'present' : 'missing'})',
    );
    if (windowsExpected) {
      stdout.writeln(
        '  Windows wrapper: ${windows.path} (${windowsValid ? 'verified' : 'missing or invalid'})',
      );
      stdout.writeln(
        '  Windows backup: ${windowsOriginal.path} (${windowsOriginal.existsSync() ? 'present' : 'missing'})',
      );
    }
    stdout.writeln(
      '  run/build preflight: ${preflightEnabled ? 'enabled' : 'missing'}, '
      'run watch: ${runWatchEnabled ? 'enabled' : 'missing'}, '
      'pub post-hook: ${posixValid ? 'enabled' : 'missing'}',
    );
    stdout.writeln(
      'CCRouter pub hook result: ${installed ? 'installed and verified' : 'not installed or inconsistent'}',
    );
    return installed;
  }

  bool _isMarker(File file) {
    if (!file.existsSync()) return false;
    try {
      final value = jsonDecode(file.readAsStringSync());
      return value is Map &&
          value['schema'] == 3 &&
          value['generator'] == 'ccrouter_generator';
    } on Object {
      return false;
    }
  }

  bool _isPosixWrapper(File file) {
    if (!file.existsSync()) return false;
    try {
      return file.readAsStringSync().contains('CCRouter pub hook wrapper');
    } on Object {
      return false;
    }
  }

  bool _isWindowsWrapper(File file) {
    if (!file.existsSync()) return false;
    try {
      return file.readAsStringSync().contains('CCRouter pub hook wrapper');
    } on Object {
      return false;
    }
  }

  bool _supportsPreflight(File file) {
    if (!file.existsSync()) return false;
    try {
      return file.readAsStringSync().contains('CCRouter preflight hook');
    } on Object {
      return false;
    }
  }

  bool _supportsRunWatch(File file) {
    if (!file.existsSync()) return false;
    try {
      return file.readAsStringSync().contains('--watch=auto');
    } on Object {
      return false;
    }
  }

  void _validateSdk(Directory bin) {
    if (!sdkRoot.existsSync() || !bin.existsSync()) {
      throw FileSystemException('Flutter SDK does not exist: ${sdkRoot.path}');
    }
    final flutter = File(path.join(bin.path, 'flutter'));
    if (!flutter.existsSync()) {
      throw FileSystemException(
        'Flutter POSIX entrypoint was not found: ${flutter.path}',
      );
    }
  }

  void _ensureBackupAbsent(File posixOriginal, File windowsOriginal) {
    if (posixOriginal.existsSync() || windowsOriginal.existsSync()) {
      throw const FileSystemException(
        'A CCRouter pub hook backup already exists; run status or uninstall before reinstalling.',
      );
    }
  }

  static Directory _canonicalDirectory(String value) {
    final directory = Directory(value).absolute;
    if (!directory.existsSync()) {
      throw FileSystemException(
        'Flutter SDK does not exist: ${directory.path}',
      );
    }
    return Directory(directory.resolveSymbolicLinksSync());
  }

  static Directory? _findNearestFvmSdk(Directory start) {
    var current = Directory(start.absolute.path);
    while (true) {
      final link = Directory(path.join(current.path, '.fvm', 'flutter_sdk'));
      if (link.existsSync()) return _canonicalDirectory(link.path);
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
  }

  static Future<void> _makeExecutable(File file) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', ['+x', file.path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Unable to make the Flutter wrapper executable: ${file.path}',
      );
    }
  }
}

/// Runs generation after a successful Pub command or before run/build.
///
/// Non-CCRouter projects are intentionally a low-cost no-op once their resolved
/// Package config is read. Successful output is concise; failure output retains
/// only a bounded recent diagnostic tail.
Future<bool> runCCPubHook({
  required Directory projectRoot,
  String? pubCommand,
}) async {
  final root = projectRoot.absolute;
  final packageConfig = _findPackageConfig(root);
  if (packageConfig == null) {
    stdout.writeln('CCRouter pub hook skipped: no resolved Package config.');
    return true;
  }
  final decoded = jsonDecode(await packageConfig.readAsString());
  final packageNames = <String>{};
  if (decoded is Map && decoded['packages'] is List) {
    for (final package in decoded['packages'] as List) {
      if (package is Map && package['name'] is String) {
        packageNames.add(package['name'] as String);
      }
    }
  }
  if (!packageNames.contains('ccrouter') ||
      !packageNames.contains('ccrouter_generator')) {
    stdout.writeln('CCRouter pub hook skipped: project does not use CCRouter.');
    return true;
  }
  if (!_declaresDirectDependency(root, 'ccrouter')) {
    stdout.writeln(
      'CCRouter pub hook skipped: current Package does not directly depend '
      'on ccrouter (Workspace aggregators are not Hosts).',
    );
    return true;
  }
  final stopwatch = Stopwatch()..start();
  final operation = _CCPubHookOperation.fromCommand(pubCommand);
  stdout.writeln(
    'CCRouter ${operation.label} started for ${operation.target}.',
  );
  if (operation.isPostPub) {
    final watch = await _waitForPostPubWatch(root, packageConfig.parent.parent);
    if (watch != null) {
      stopwatch.stop();
      if (watch.succeeded) {
        stdout.writeln(
          'CCRouter ${operation.label} reused active watch cycle '
          '${watch.cycle}.',
        );
        stdout.writeln(
          'CCRouter ${operation.label} finished: '
          'elapsed=${stopwatch.elapsedMilliseconds}ms.',
        );
      } else {
        stderr.writeln(
          'CCRouter ${operation.label} failed for ${operation.target}: '
          '${watch.message}, elapsed=${stopwatch.elapsedMilliseconds}ms.',
        );
        if (watch.diagnostics case final diagnostics?) {
          stderr.writeln('Generator output:');
          stderr.writeln(diagnostics);
        }
        stderr.writeln('Watch log: ${watch.logFile.path}');
      }
      return watch.succeeded;
    }
  }
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    'ccrouter_generator:ccrouter',
    'generate',
    root.path,
  ], workingDirectory: root.path);
  final output = _CCPubHookOutput();
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => output.add(line, isError: false))
      .asFuture<void>();
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => output.add(line, isError: true))
      .asFuture<void>();
  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);
  stopwatch.stop();
  if (exitCode == 0) {
    output.writeSummary();
    stdout.writeln(
      'CCRouter ${operation.label} finished: '
      'elapsed=${stopwatch.elapsedMilliseconds}ms.',
    );
  } else {
    stderr.writeln(
      'CCRouter ${operation.label} failed for ${operation.target}: '
      'exitCode=$exitCode, elapsed=${stopwatch.elapsedMilliseconds}ms.',
    );
    output.writeFailureTail();
  }
  return exitCode == 0;
}

/// Whether [root]'s own manifest declares [packageName] as a dependency.
///
/// Package config contains the complete resolved Workspace graph, so it cannot
/// distinguish a Host from an aggregator. Requiring a direct declaration keeps
/// root Workspace commands from accidentally generating against the aggregator
/// while retaining explicit component and Host Package workflows.
bool _declaresDirectDependency(Directory root, String packageName) {
  final pubspec = File(path.join(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  try {
    final document = loadYaml(pubspec.readAsStringSync());
    if (document is! YamlMap) return false;
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final dependencies = document[section];
      if (dependencies is YamlMap && dependencies.containsKey(packageName)) {
        return true;
      }
    }
  } on YamlException {
    return false;
  } on FileSystemException {
    return false;
  }
  return false;
}

/// User-facing naming for one Hook-triggered generation pass.
final class _CCPubHookOperation {
  /// Creates one immutable operation label.
  const _CCPubHookOperation({
    required this.label,
    required this.target,
    required this.isPostPub,
  });

  /// Selects preflight terminology for `run/build` and post-pub terminology
  /// for dependency commands.
  factory _CCPubHookOperation.fromCommand(String? command) {
    final normalized = command?.trim();
    final isPreflight = normalized == 'run' || normalized == 'build';
    final target = normalized == null || normalized.isEmpty
        ? '`ccrouter generate`'
        : isPreflight
        ? '`flutter $normalized`'
        : '`flutter pub $normalized`';
    return _CCPubHookOperation(
      label: isPreflight ? 'preflight' : 'post-pub generation',
      target: target,
      isPostPub: !isPreflight,
    );
  }

  /// Concise phase name written to the console.
  final String label;

  /// Triggering Flutter command without project or argument details.
  final String target;

  /// Whether an active watch may satisfy this dependency-change generation.
  final bool isPostPub;
}

/// Result of waiting for the active Host watch after a successful Pub command.
final class _CCPubHookWatchResult {
  const _CCPubHookWatchResult({
    required this.succeeded,
    required this.cycle,
    required this.message,
    required this.logFile,
    this.diagnostics,
  });

  final bool succeeded;
  final int cycle;
  final String message;
  final File logFile;
  final String? diagnostics;
}

/// Reuses one active Host watch instead of racing it with a one-shot generate.
///
/// Pub may rewrite Workspace resolution files before this process starts. Only
/// a terminal watch event for their exact current contents can satisfy the Hook.
Future<_CCPubHookWatchResult?> _waitForPostPubWatch(
  Directory hostRoot,
  Directory buildRoot,
) async {
  final statusFile = File(
    path.join(
      hostRoot.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      'status.json',
    ),
  );
  var status = await _readPubHookWatchStatus(statusFile);
  if (status == null) {
    if (!await _pubHookWatchOwnerIsHeld(buildRoot)) return null;
    return _CCPubHookWatchResult(
      succeeded: false,
      cycle: 0,
      message: 'active watch status is unavailable',
      logFile: _pubHookWatchLogFile(hostRoot),
    );
  }
  if (!_pubHookStatusMatchesHost(status, hostRoot)) {
    return null;
  }
  if (!await _pubHookWatchIsActive(status)) return null;

  final requiredResolutionFingerprint =
      await CCPubResolutionFingerprint.capture(
        hostRoot: hostRoot,
        buildRoot: buildRoot,
      );
  final timeout = Stopwatch()..start();
  const maximumWait = Duration(minutes: 5);
  while (timeout.elapsed < maximumWait) {
    status = await _readPubHookWatchStatus(statusFile);
    if (status == null || !_pubHookStatusMatchesHost(status, hostRoot)) {
      return _CCPubHookWatchResult(
        succeeded: false,
        cycle: 0,
        message: 'active watch status became unavailable',
        logFile: _pubHookWatchLogFile(hostRoot),
      );
    }
    final cycle = status['cycle'] as int;
    final lastEvent = status['lastEvent'] as String;
    final matchesResolution =
        status['resolutionFingerprint'] == requiredResolutionFingerprint;
    if (matchesResolution &&
        (lastEvent == 'aggregationSucceeded' || lastEvent == 'ready')) {
      return _CCPubHookWatchResult(
        succeeded: true,
        cycle: cycle,
        message: 'active watch aggregation succeeded',
        logFile: _pubHookWatchLogFile(hostRoot),
      );
    }
    if (matchesResolution && lastEvent == 'failed') {
      return _CCPubHookWatchResult(
        succeeded: false,
        cycle: cycle,
        message:
            'active watch cycle $cycle failed at '
            '${status['failureStage'] ?? 'generation'}',
        diagnostics: status['failureDiagnostics'] as String?,
        logFile: _pubHookWatchLogFile(hostRoot),
      );
    }
    if (!await _pubHookWatchIsActive(status)) {
      return _CCPubHookWatchResult(
        succeeded: false,
        cycle: cycle,
        message: 'active watch stopped before post-pub aggregation completed',
        diagnostics: status['failureDiagnostics'] as String?,
        logFile: _pubHookWatchLogFile(hostRoot),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final latestStatus = status!;
  return _CCPubHookWatchResult(
    succeeded: false,
    cycle: latestStatus['cycle'] as int,
    message:
        'active watch did not complete post-pub aggregation within '
        '${maximumWait.inMinutes} minutes',
    diagnostics: latestStatus['failureDiagnostics'] as String?,
    logFile: _pubHookWatchLogFile(hostRoot),
  );
}

Future<Map<String, Object?>?> _readPubHookWatchStatus(File file) async {
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['active'] is! bool ||
        decoded['lastEvent'] is! String ||
        decoded['cycle'] is! int ||
        decoded['updatedAt'] is! String ||
        decoded['hostRoot'] is! String ||
        decoded['buildRoot'] is! String) {
      return null;
    }
    return decoded.cast<String, Object?>();
  } on Object {
    return null;
  }
}

bool _pubHookStatusMatchesHost(
  Map<String, Object?> status,
  Directory hostRoot,
) => path.equals(
  path.normalize('${status['hostRoot']}'),
  path.normalize(hostRoot.absolute.path),
);

Future<bool> _pubHookWatchIsActive(Map<String, Object?> status) async {
  if (status['active'] != true) return false;
  return _pubHookWatchOwnerIsHeld(Directory(status['buildRoot'] as String));
}

Future<bool> _pubHookWatchOwnerIsHeld(Directory buildRoot) async {
  final owner = File(
    path.join(
      buildRoot.path,
      '.dart_tool',
      'ccrouter',
      'v1',
      'watch',
      'owner.lock',
    ),
  );
  if (!owner.existsSync()) return false;
  RandomAccessFile? opened;
  try {
    opened = await owner.open(mode: FileMode.append);
    await opened.lock(FileLock.shared);
    await opened.unlock();
    return false;
  } on FileSystemException {
    return true;
  } finally {
    await opened?.close();
  }
}

File _pubHookWatchLogFile(Directory hostRoot) => File(
  path.join(
    hostRoot.path,
    '.dart_tool',
    'ccrouter',
    'v1',
    'watch',
    'flutter-run.log',
  ),
);

/// Bounded child-process output retained until generation succeeds or fails.
final class _CCPubHookOutput {
  /// Maximum recent lines retained for failure diagnostics.
  static const int _maximumLines = 200;

  /// Maximum recent characters retained for failure diagnostics.
  static const int _maximumCharacters = 64 * 1024;

  /// Lines that summarize a successful generation without Builder noise.
  final List<String> _summary = [];

  /// Recent stdout and stderr lines retained in arrival order.
  final List<_CCPubHookOutputLine> _tail = [];

  /// Total character count currently retained by [_tail].
  int _tailCharacters = 0;

  /// Whether older output was discarded to respect the fixed bounds.
  bool _truncated = false;

  /// Records one child line and selects stable success-summary lines.
  void add(String line, {required bool isError}) {
    if (!isError && _isSummary(line)) _summary.add(line);
    final item = _CCPubHookOutputLine(line);
    _tail.add(item);
    _tailCharacters += item.characterCount;
    while (_tail.length > _maximumLines ||
        _tailCharacters > _maximumCharacters) {
      _tailCharacters -= _tail.removeAt(0).characterCount;
      _truncated = true;
    }
  }

  /// Writes only stable validation and timing information on success.
  void writeSummary() {
    for (final line in _summary) {
      stdout.writeln(line);
    }
  }

  /// Writes bounded recent diagnostics after a failed child process.
  void writeFailureTail() {
    if (_tail.isEmpty) {
      stderr.writeln('No generator diagnostics were produced.');
      return;
    }
    stderr.writeln(
      _truncated
          ? 'Recent generator output (older lines omitted):'
          : 'Generator output:',
    );
    for (final item in _tail) {
      stderr.writeln(item.line);
    }
  }

  /// Recognizes concise, version-stable generator completion messages.
  bool _isSummary(String line) =>
      line.startsWith('Validated ') ||
      line == 'CCRouter generated artifacts are up to date.' ||
      line.startsWith('CCRouter generation fast path hit;') ||
      line.startsWith('CCRouter generation aggregate-only path;') ||
      line.startsWith('Bootstrapped generated component APIs ');
}

/// One retained line plus its encoded-size approximation.
final class _CCPubHookOutputLine {
  /// Creates one retained child-process line.
  const _CCPubHookOutputLine(this.line);

  /// Exact decoded line without its newline terminator.
  final String line;

  /// Bounded-buffer cost including one newline character.
  int get characterCount => line.length + 1;
}

File? _findPackageConfig(Directory start) {
  var current = start;
  while (true) {
    final candidate = File(
      path.join(current.path, '.dart_tool', 'package_config.json'),
    );
    if (candidate.existsSync()) return candidate;
    final parent = current.parent;
    if (parent.path == current.path) return null;
    current = parent;
  }
}

/// POSIX wrapper installed as `bin/flutter`.
const _posixWrapper = r'''#!/usr/bin/env bash
# CCRouter pub hook wrapper. The original Flutter entrypoint is kept beside this file.
# CCRouter preflight hook: run/build generation is deliberately fail-closed.
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ORIGINAL="$SCRIPT_DIR/flutter.ccrouter-original"
DART="$SCRIPT_DIR/dart"

if [ "${CCROUTER_PUB_HOOK_DISABLE:-0}" = "1" ]; then
  exec "$ORIGINAL" "$@"
fi

find_flutter_command() {
  FLUTTER_COMMAND=""
  for ARG in "$@"; do
    case "$ARG" in
      pub|run|build)
        FLUTTER_COMMAND="$ARG"
        return 0
        ;;
    esac
  done
}

resolve_project_root() {
  HOOK_DIR="$PWD"
  EXPECTING_DIRECTORY=0
  for ARG in "$@"; do
    if [ "$EXPECTING_DIRECTORY" -eq 1 ]; then
      HOOK_DIR="$ARG"
      EXPECTING_DIRECTORY=0
    elif [ "$ARG" = "--directory" ] || [ "$ARG" = "-C" ]; then
      EXPECTING_DIRECTORY=1
    elif [[ "$ARG" == --directory=* ]]; then
      HOOK_DIR="${ARG#--directory=}"
    fi
  done
  if [[ "$HOOK_DIR" != /* ]]; then
    HOOK_DIR="$PWD/$HOOK_DIR"
  fi
  while [ ! -f "$HOOK_DIR/pubspec.yaml" ] && [ "$HOOK_DIR" != "/" ]; do
    HOOK_DIR="$(dirname -- "$HOOK_DIR")"
  done
  if [ ! -f "$HOOK_DIR/pubspec.yaml" ]; then
    return 1
  fi
  PROJECT_ROOT="$HOOK_DIR"
  PACKAGE_CONFIG="$HOOK_DIR/.dart_tool/package_config.json"
  while [ ! -f "$PACKAGE_CONFIG" ] && [ "$HOOK_DIR" != "/" ]; do
    HOOK_DIR="$(dirname -- "$HOOK_DIR")"
    PACKAGE_CONFIG="$HOOK_DIR/.dart_tool/package_config.json"
  done
  if [ ! -f "$PACKAGE_CONFIG" ] || \
     ! grep -Eq '"name"[[:space:]]*:[[:space:]]*"ccrouter_generator"' "$PACKAGE_CONFIG"; then
    return 1
  fi
  return 0
}

run_generator_hook() {
  HOOK_COMMAND="$1"
  shift
  if ! resolve_project_root "$@"; then
    return 0
  fi
  "$DART" run --verbosity=error ccrouter_generator:ccrouter pub-hook run \
    --project-root "$PROJECT_ROOT" --pub-command "$HOOK_COMMAND"
}

find_flutter_command "$@"
if [ "$FLUTTER_COMMAND" = "run" ] || [ "$FLUTTER_COMMAND" = "build" ]; then
  run_generator_hook "$FLUTTER_COMMAND" "$@"
  HOOK_EXIT=$?
  if [ "$HOOK_EXIT" -ne 0 ]; then
    echo "CCRouter preflight hook failed before flutter $FLUTTER_COMMAND (exit $HOOK_EXIT)." >&2
    exit "$HOOK_EXIT"
  fi
  if [ "$FLUTTER_COMMAND" = "build" ] || [ "${CCROUTER_DISABLE_BUILD_WATCH:-0}" = "1" ]; then
    exec "$ORIGINAL" "$@"
  fi
  WATCH_DIR="$PROJECT_ROOT/.dart_tool/ccrouter/v1/watch"
  WATCH_LEASE="$WATCH_DIR/flutter-run-$$-${RANDOM:-0}.lease"
  mkdir -p "$WATCH_DIR"
  : > "$WATCH_LEASE"
  "$DART" run --verbosity=error ccrouter_generator:ccrouter generate \
    "$PROJECT_ROOT" --watch=auto --machine --watch-lease "$WATCH_LEASE" \
    >> "$WATCH_DIR/flutter-run.log" 2>&1 &
  WATCH_PID=$!
  echo "CCRouter watch starting (pid=$WATCH_PID). Status: $WATCH_DIR/status.json; log: $WATCH_DIR/flutter-run.log"
  cleanup_ccrouter_watch() {
    rm -f "$WATCH_LEASE"
    if kill -0 "$WATCH_PID" 2>/dev/null; then
      kill "$WATCH_PID" 2>/dev/null || true
      wait "$WATCH_PID" 2>/dev/null || true
    fi
  }
  trap cleanup_ccrouter_watch EXIT INT TERM
  "$ORIGINAL" "$@"
  ORIGINAL_EXIT=$?
  cleanup_ccrouter_watch
  trap - EXIT INT TERM
  exit "$ORIGINAL_EXIT"
fi

if [ "$FLUTTER_COMMAND" != "pub" ]; then
  exec "$ORIGINAL" "$@"
fi

"$ORIGINAL" "$@"
PUB_EXIT=$?
if [ "$PUB_EXIT" -ne 0 ]; then
  exit "$PUB_EXIT"
fi

PUB_COMMAND=""
for ARG in "$@"; do
  case "$ARG" in
    get|upgrade|downgrade|add|remove)
      PUB_COMMAND="$ARG"
      break
      ;;
  esac
done
if [ -z "$PUB_COMMAND" ]; then
  exit 0
fi
run_generator_hook "$PUB_COMMAND" "$@"
HOOK_EXIT=$?
if [ "$HOOK_EXIT" -ne 0 ]; then
  echo "CCRouter pub hook failed after successful flutter pub (exit $HOOK_EXIT)." >&2
fi
exit "$HOOK_EXIT"
''';

/// Windows wrapper installed as `bin/flutter.bat`.
const _windowsWrapper = r'''@echo off
rem CCRouter pub hook wrapper. The original Flutter entrypoint is kept beside this file.
rem CCRouter preflight hook: run/build generation is deliberately fail-closed.
set "SCRIPT_DIR=%~dp0"
set "ORIGINAL=%SCRIPT_DIR%flutter.ccrouter-original.bat"
if "%CCROUTER_PUB_HOOK_DISABLE%"=="1" goto invoke_original

set "FLUTTER_COMMAND="
for %%A in (%*) do (
  if /I "%%~A"=="pub" if not defined FLUTTER_COMMAND set "FLUTTER_COMMAND=pub"
  if /I "%%~A"=="run" if not defined FLUTTER_COMMAND set "FLUTTER_COMMAND=run"
  if /I "%%~A"=="build" if not defined FLUTTER_COMMAND set "FLUTTER_COMMAND=build"
)
if /I "%FLUTTER_COMMAND%"=="run" goto preflight
if /I "%FLUTTER_COMMAND%"=="build" goto preflight
if /I not "%FLUTTER_COMMAND%"=="pub" goto invoke_original

call "%ORIGINAL%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
set "PUB_COMMAND="
for %%A in (%*) do (
  if /I "%%~A"=="get" if not defined PUB_COMMAND set "PUB_COMMAND=get"
  if /I "%%~A"=="upgrade" if not defined PUB_COMMAND set "PUB_COMMAND=upgrade"
  if /I "%%~A"=="downgrade" if not defined PUB_COMMAND set "PUB_COMMAND=downgrade"
  if /I "%%~A"=="add" if not defined PUB_COMMAND set "PUB_COMMAND=add"
  if /I "%%~A"=="remove" if not defined PUB_COMMAND set "PUB_COMMAND=remove"
)
if not defined PUB_COMMAND exit /b 0
set "HOOK_COMMAND=%PUB_COMMAND%"
goto run_hook

:preflight
set "HOOK_COMMAND=%FLUTTER_COMMAND%"
goto run_hook

:run_hook
set "HOOK_DIR=%CD%"
if not exist "%HOOK_DIR%\pubspec.yaml" goto invoke_original
set "PROJECT_ROOT=%CD%"
:find_package_config
if exist "%HOOK_DIR%\.dart_tool\package_config.json" goto package_config_found
for %%i in ("%HOOK_DIR%\..") do set "PARENT_DIR=%%~fi"
if /I "%PARENT_DIR%"=="%HOOK_DIR%" goto invoke_original
set "HOOK_DIR=%PARENT_DIR%"
goto find_package_config
:package_config_found
findstr /R /C:"\"name\"[ ]*:[ ]*\"ccrouter_generator\"" "%HOOK_DIR%\.dart_tool\package_config.json" >nul
if not "%ERRORLEVEL%"=="0" goto invoke_original
call "%SCRIPT_DIR%dart.bat" run --verbosity=error ccrouter_generator:ccrouter pub-hook run --project-root "%PROJECT_ROOT%" --pub-command "%HOOK_COMMAND%"
if not "%ERRORLEVEL%"=="0" goto hook_failed
if /I "%HOOK_COMMAND%"=="build" goto invoke_original
if /I not "%HOOK_COMMAND%"=="run" exit /b 0
if "%CCROUTER_DISABLE_BUILD_WATCH%"=="1" goto invoke_original
set "WATCH_DIR=%PROJECT_ROOT%\.dart_tool\ccrouter\v1\watch"
if not exist "%WATCH_DIR%" mkdir "%WATCH_DIR%"
set "WATCH_LEASE=%WATCH_DIR%\flutter-run-%RANDOM%-%RANDOM%.lease"
type nul > "%WATCH_LEASE%"
start "" /b "%SCRIPT_DIR%dart.bat" run --verbosity=error ccrouter_generator:ccrouter generate "%PROJECT_ROOT%" --watch=auto --machine --watch-lease "%WATCH_LEASE%" 1>>"%WATCH_DIR%\flutter-run.log" 2>>&1
echo CCRouter watch starting. Status: %WATCH_DIR%\status.json; log: %WATCH_DIR%\flutter-run.log
call "%ORIGINAL%" %*
set "ORIGINAL_EXIT=%ERRORLEVEL%"
del /q "%WATCH_LEASE%" >nul 2>&1
exit /b %ORIGINAL_EXIT%

:hook_failed
echo CCRouter hook failed for flutter %HOOK_COMMAND%. 1>&2
exit /b %ERRORLEVEL%

:invoke_original
call "%ORIGINAL%" %*
exit /b %ERRORLEVEL%
''';
