import 'dart:convert';
import 'dart:io';

import 'package:ccrouter_generator/src/project_context.dart';
import 'package:ccrouter_generator/src/project_role.dart';
import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'canonical_directory_identity.dart';
import 'coordination_home.dart';
import 'pub_hook_watch_coordination.dart';

const _pubHookWatchFailureFenceKillSwitch =
    'CCROUTER_DISABLE_PUB_HOOK_WATCH_FAILURE_FENCE';
const _packageWatchReuseKillSwitch = 'CCROUTER_DISABLE_PACKAGE_WATCH_REUSE';
const _oneShotWatchReuseKillSwitch = 'CCROUTER_DISABLE_ONE_SHOT_WATCH_REUSE';

/// Disables only the pre-clean active-watch guard for A/B diagnosis.
const ccrouterFlutterCleanGuardKillSwitch =
    'CCROUTER_DISABLE_FLUTTER_CLEAN_GUARD';

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

  /// Refuses `flutter clean` while its build root has a live watch owner.
  cleanGuard,
}

/// Returns false when `flutter clean` would unlink active watch state.
Future<bool> guardCCFlutterClean(Directory projectRoot) async {
  if (Platform.environment[ccrouterFlutterCleanGuardKillSwitch] == '1') {
    return true;
  }
  final context = CCProjectContext.resolve(projectRoot);
  final buildRoot = context.resolutionRoot;
  final selectedOwner = ccrouterWatchOwnerLockFile(buildRoot);
  final legacyOwner = legacyCCRouterWatchOwnerLockFile(buildRoot);
  final selectedHeld = await _pubHookOwnerFileIsHeld(selectedOwner);
  final legacyHeld = path.equals(selectedOwner.path, legacyOwner.path)
      ? false
      : await _pubHookOwnerFileIsHeld(legacyOwner);
  if (!selectedHeld && !legacyHeld) return true;
  stderr.writeln(
    'error: An active CCRouter generation watch owns ${buildRoot.path}. '
    'Stop the Flutter run/watch before `flutter clean`, then retry. '
    'Set $ccrouterFlutterCleanGuardKillSwitch=1 only to bypass this guard '
    'for an explicit A/B or recovery run.',
  );
  return false;
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
  static const _originalDartPosixName = 'dart.ccrouter-original';
  static const _originalDartWindowsName = 'dart.ccrouter-original.bat';
  static const _markerName = '.ccrouter_pub_hook.json';
  static const _markerSchema = 5;

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
    final dartPosix = _dartPosixEntrypoint(bin);
    final dartPosixOriginal = File(
      path.join(dartPosix.parent.path, _originalDartPosixName),
    );
    final dartWindows = File(path.join(bin.path, 'dart.bat'));
    final dartWindowsOriginal = File(
      path.join(bin.path, _originalDartWindowsName),
    );
    _ensureBackupAbsent([
      posixOriginal,
      windowsOriginal,
      dartPosixOriginal,
      dartWindowsOriginal,
    ]);
    final moved = <({File source, File backup})>[];
    try {
      await posix.rename(posixOriginal.path);
      moved.add((source: posix, backup: posixOriginal));
      if (windows.existsSync()) {
        await windows.rename(windowsOriginal.path);
        moved.add((source: windows, backup: windowsOriginal));
      }
      if (dartPosix.existsSync()) {
        await dartPosix.rename(dartPosixOriginal.path);
        moved.add((source: dartPosix, backup: dartPosixOriginal));
      }
      if (dartWindows.existsSync()) {
        await dartWindows.rename(dartWindowsOriginal.path);
        moved.add((source: dartWindows, backup: dartWindowsOriginal));
      }
      await posix.writeAsString(_posixWrapper);
      await _makeExecutable(posix);
      if (windowsOriginal.existsSync()) {
        await windows.writeAsString(_windowsWrapper);
      }
      if (dartPosixOriginal.existsSync()) {
        await dartPosix.writeAsString(_dartPosixWrapper);
        await _makeExecutable(dartPosix);
      }
      if (dartWindowsOriginal.existsSync()) {
        await dartWindows.writeAsString(_dartWindowsWrapper);
      }
      await marker.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object>{
          'schema': _markerSchema,
          'entrypoints': <String>['flutter', 'dart'],
          'generator': 'ccrouter_generator',
          'features': const <String>[
            'pub',
            'dart-pub',
            'run',
            'build',
            'run-watch',
            'watch-startup-handshake',
            'machine-reload-gate',
            'windows-run-supervisor',
          ],
        }),
      );
    } catch (_) {
      if (marker.existsSync()) await marker.delete();
      for (final item in moved.reversed) {
        if (item.backup.existsSync()) {
          if (item.source.existsSync()) await item.source.delete();
          await item.backup.rename(item.source.path);
        }
      }
      rethrow;
    }
    stdout.writeln(
      'Installed CCRouter pub hook in Flutter SDK: ${sdkRoot.path}',
    );
    stdout.writeln(
      'The hook runs after successful Flutter/Dart pub commands and before `flutter run/build`.',
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
    final dartPosix = _dartPosixEntrypoint(bin);
    final dartPosixOriginal = File(
      path.join(dartPosix.parent.path, _originalDartPosixName),
    );
    final dartWindows = File(path.join(bin.path, 'dart.bat'));
    final dartWindowsOriginal = File(
      path.join(bin.path, _originalDartWindowsName),
    );
    if (!marker.existsSync()) {
      stdout.writeln('CCRouter pub hook is not installed: ${sdkRoot.path}');
      return false;
    }
    final markerSchema = _readMarkerSchema(marker);
    if (markerSchema != 4 && markerSchema != _markerSchema) {
      throw const FileSystemException(
        'CCRouter pub hook marker is invalid; refusing to modify SDK entrypoints.',
      );
    }
    if (markerSchema == 4 &&
        (dartPosixOriginal.existsSync() || dartWindowsOriginal.existsSync())) {
      throw const FileSystemException(
        'Legacy CCRouter pub hook unexpectedly has Dart backups; refusing to '
        'guess their ownership.',
      );
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
    if (markerSchema == _markerSchema &&
        !Platform.isWindows &&
        !dartPosixOriginal.existsSync()) {
      throw const FileSystemException(
        'CCRouter Dart POSIX hook backup is missing; refusing to delete the '
        'SDK entrypoint.',
      );
    }
    if (markerSchema == _markerSchema &&
        Platform.isWindows &&
        !dartWindowsOriginal.existsSync()) {
      throw const FileSystemException(
        'CCRouter Dart Windows hook backup is missing; refusing to delete the '
        'SDK entrypoint.',
      );
    }
    if (markerSchema == _markerSchema &&
        dartPosixOriginal.existsSync() &&
        !_isDartPosixWrapper(dartPosix)) {
      throw const FileSystemException(
        'CCRouter Dart POSIX hook installation is incomplete; refusing to '
        'delete the SDK entrypoint.',
      );
    }
    if (markerSchema == _markerSchema &&
        dartWindowsOriginal.existsSync() &&
        !_isDartWindowsWrapper(dartWindows)) {
      throw const FileSystemException(
        'CCRouter Dart Windows hook installation is incomplete; refusing to '
        'delete the SDK entrypoint.',
      );
    }
    await posix.delete();
    await posixOriginal.rename(posix.path);
    if (windowsOriginal.existsSync()) {
      if (windows.existsSync()) await windows.delete();
      await windowsOriginal.rename(windows.path);
    }
    if (markerSchema == _markerSchema && dartPosixOriginal.existsSync()) {
      if (dartPosix.existsSync()) await dartPosix.delete();
      await dartPosixOriginal.rename(dartPosix.path);
    }
    if (markerSchema == _markerSchema && dartWindowsOriginal.existsSync()) {
      if (dartWindows.existsSync()) await dartWindows.delete();
      await dartWindowsOriginal.rename(dartWindows.path);
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
    final dartPosix = _dartPosixEntrypoint(bin);
    final dartPosixOriginal = File(
      path.join(dartPosix.parent.path, _originalDartPosixName),
    );
    final dartWindows = File(path.join(bin.path, 'dart.bat'));
    final dartWindowsOriginal = File(
      path.join(bin.path, _originalDartWindowsName),
    );
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
    final dartPosixExpected =
        dartPosix.existsSync() || dartPosixOriginal.existsSync();
    final dartPosixValid =
        !dartPosixExpected ||
        (dartPosixOriginal.existsSync() && _isDartPosixWrapper(dartPosix));
    final dartWindowsExpected =
        dartWindows.existsSync() || dartWindowsOriginal.existsSync();
    final dartWindowsValid =
        !dartWindowsExpected ||
        (dartWindowsOriginal.existsSync() &&
            _isDartWindowsWrapper(dartWindows));
    final preflightEnabled =
        _supportsPreflight(posix) &&
        (!windowsExpected || _supportsPreflight(windows));
    final runWatchEnabled =
        _supportsRunWatch(posix) &&
        (!windowsExpected || _supportsRunWatch(windows));
    final cleanGuardEnabled =
        _supportsCleanGuard(posix) &&
        (!windowsExpected || _supportsCleanGuard(windows));
    final reloadGateEnabled =
        _supportsReloadGate(posix) &&
        (!windowsExpected || _supportsReloadGate(windows));
    final watchStartupHandshakeEnabled =
        _supportsWatchStartupHandshake(posix) &&
        (!windowsExpected || _supportsWatchStartupHandshake(windows));
    final runSupervisorEnabled =
        _supportsRunSupervisor(posix) &&
        (!windowsExpected || _supportsRunSupervisor(windows));
    final installed =
        markerValid &&
        posixBackupPresent &&
        posixValid &&
        windowsValid &&
        (Platform.isWindows ? dartWindowsExpected : dartPosixExpected) &&
        dartPosixValid &&
        dartWindowsValid &&
        preflightEnabled &&
        runWatchEnabled &&
        cleanGuardEnabled &&
        watchStartupHandshakeEnabled &&
        runSupervisorEnabled &&
        reloadGateEnabled;
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
    if (dartPosixExpected) {
      stdout.writeln(
        '  Dart POSIX wrapper: ${dartPosix.path} '
        '(${dartPosixValid ? 'verified' : 'missing or invalid'})',
      );
      stdout.writeln(
        '  Dart POSIX backup: ${dartPosixOriginal.path} '
        '(${dartPosixOriginal.existsSync() ? 'present' : 'missing'})',
      );
    }
    if (dartWindowsExpected) {
      stdout.writeln(
        '  Dart Windows wrapper: ${dartWindows.path} '
        '(${dartWindowsValid ? 'verified' : 'missing or invalid'})',
      );
      stdout.writeln(
        '  Dart Windows backup: ${dartWindowsOriginal.path} '
        '(${dartWindowsOriginal.existsSync() ? 'present' : 'missing'})',
      );
      if (Platform.isWindows) {
        stdout.writeln(
          '  Dart Windows direct executable: '
          'cache/dart-sdk/bin/dart.exe (not managed; IDEs must invoke '
          'bin/dart.bat for the hook)',
        );
      }
    }
    stdout.writeln(
      '  run/build preflight: ${preflightEnabled ? 'enabled' : 'missing'}, '
      'run watch: ${runWatchEnabled ? 'enabled' : 'missing'}, '
      'clean guard: ${cleanGuardEnabled ? 'enabled' : 'missing'}, '
      'watch startup handshake: ${watchStartupHandshakeEnabled ? 'enabled' : 'missing'}, '
      'run supervisor: ${runSupervisorEnabled ? 'enabled' : 'missing'}, '
      'machine reload gate: ${reloadGateEnabled ? 'enabled' : 'missing'}, '
      'flutter pub post-hook: ${posixValid ? 'enabled' : 'missing'}, '
      'dart pub post-hook: ${dartPosixValid && dartWindowsValid ? 'enabled' : 'missing'}',
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
          value['schema'] == _markerSchema &&
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

  bool _isDartPosixWrapper(File file) {
    if (!file.existsSync()) return false;
    try {
      return file.readAsStringSync().contains('CCRouter Dart pub hook wrapper');
    } on Object {
      return false;
    }
  }

  bool _isDartWindowsWrapper(File file) {
    if (!file.existsSync()) return false;
    try {
      return file.readAsStringSync().contains('CCRouter Dart pub hook wrapper');
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
      final contents = file.readAsStringSync();
      return contents.contains('--launch-watch') ||
          contents.contains('--watch=auto');
    } on Object {
      return false;
    }
  }

  bool _supportsCleanGuard(File file) {
    if (!file.existsSync()) return false;
    try {
      return file.readAsStringSync().contains(
        'CCROUTER_DISABLE_FLUTTER_CLEAN_GUARD',
      );
    } on Object {
      return false;
    }
  }

  bool _supportsReloadGate(File file) {
    if (!file.existsSync()) return false;
    try {
      final contents = file.readAsStringSync();
      return contents.contains('--reload-gate') ||
          contents.contains('ccrouter_generator:ccrouter_flutter_run_gate');
    } on Object {
      return false;
    }
  }

  bool _supportsWatchStartupHandshake(File file) {
    if (!file.existsSync()) return false;
    try {
      final contents = file.readAsStringSync();
      return contents.contains('--launch-watch') ||
          contents.contains('ccrouter_generator:ccrouter_watch_startup');
    } on Object {
      return false;
    }
  }

  bool _supportsRunSupervisor(File file) {
    if (!file.existsSync()) return false;
    try {
      return file.readAsStringSync().contains(
        'ccrouter_generator:ccrouter_flutter_run_supervisor',
      );
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
    final dartPosix = _dartPosixEntrypoint(bin);
    final dartWindows = File(path.join(bin.path, 'dart.bat'));
    final dartEntrypointExists = Platform.isWindows
        ? dartWindows.existsSync()
        : dartPosix.existsSync();
    if (!dartEntrypointExists) {
      throw FileSystemException(
        'Dart SDK entrypoint was not found below: ${sdkRoot.path}',
      );
    }
  }

  void _ensureBackupAbsent(Iterable<File> backups) {
    if (backups.any((file) => file.existsSync())) {
      throw const FileSystemException(
        'A CCRouter pub hook backup already exists; run status or uninstall before reinstalling.',
      );
    }
  }

  File _dartPosixEntrypoint(Directory bin) =>
      File(path.join(bin.path, 'cache', 'dart-sdk', 'bin', 'dart'));

  int? _readMarkerSchema(File file) {
    try {
      final value = jsonDecode(file.readAsStringSync());
      return value is Map && value['generator'] == 'ccrouter_generator'
          ? value['schema'] as int?
          : null;
    } on Object {
      return null;
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
  final context = CCProjectContext.resolve(root);
  final projectRole = CCProjectRoleResolver.resolve(context);
  if (projectRole.role == CCProjectRole.skip) {
    stdout.writeln(
      'CCRouter pub hook skipped: project does not use CCRouter directly; '
      'the current Package does not depend on ccrouter or '
      'ccrouter_contracts (Workspace aggregators are not Hosts and do not '
      'participate in generation).',
    );
    return true;
  }
  final runtimePackage = switch (projectRole.participation) {
    CCProjectParticipation.runtime => 'ccrouter',
    CCProjectParticipation.contracts => 'ccrouter_contracts',
    CCProjectParticipation.none => null,
  };
  if (runtimePackage == null ||
      !packageNames.contains(runtimePackage) ||
      !packageNames.contains('ccrouter_generator')) {
    stdout.writeln('CCRouter pub hook skipped: project does not use CCRouter.');
    return true;
  }
  final stopwatch = Stopwatch()..start();
  final operation = _CCPubHookOperation.fromCommand(pubCommand);
  stdout.writeln(
    'CCRouter ${operation.label} started for ${operation.target}.',
  );
  if (operation.isPostPub && projectRole.role == CCProjectRole.host) {
    final watch = await _waitForPostPubWatch(root, context.resolutionRoot);
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
        _writePubHookProjectContext(context, projectRole.role);
        if (watch.diagnostics case final diagnostics?) {
          stderr.writeln('Generator diagnostics:');
          stderr.writeln(diagnostics);
        }
        stderr.writeln('Watch log: ${watch.logFile.path}');
      }
      return watch.succeeded;
    }
  }
  if (operation.isPostPub && projectRole.role == CCProjectRole.package) {
    final watch = await _waitForPackagePostPubWatch(context, operation);
    if (watch != null) {
      stopwatch.stop();
      if (watch.succeeded) {
        stdout.writeln(
          'CCRouter ${operation.label} reused active watch cycle '
          '${watch.cycle} for exact Package evidence.',
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
          stderr.writeln('Generator diagnostics:');
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
    _writePubHookProjectContext(context, projectRole.role);
    output.writeFailureTail();
  }
  return exitCode == 0;
}

/// Adds exact requested/resolution roots only when post-Pub generation fails.
void _writePubHookProjectContext(CCProjectContext context, CCProjectRole role) {
  stderr.writeln(
    '${role == CCProjectRole.host ? 'Host' : 'Package'}: '
    '${context.requestedRoot.path}',
  );
  stderr.writeln('Resolution root: ${context.resolutionRoot.path}');
}

/// Waits for exact Package inputs and outputs from a shared Host watch.
Future<CCWatchReuseResult?> _waitForPackagePostPubWatch(
  CCProjectContext context,
  _CCPubHookOperation operation,
) async {
  final buildRoot = context.resolutionRoot;
  var status = await _readPubHookBuildRootWatchStatus(buildRoot);
  if (status == null || status['active'] != true) return null;
  if (!hasSameDirectoryIdentity(
    status['buildRoot'] as String,
    buildRoot.path,
  )) {
    return null;
  }
  if (!await _pubHookWatchOwnerIsHeld(buildRoot)) return null;
  final packageName = _readPubHookPackageName(context.requestedRoot);
  if (packageName == null) return null;

  final hostRoot = status['hostRoot'] as String;
  final logFile = _pubHookWatchLogFile(Directory(hostRoot));
  final retry =
      'stop the watch, then retry ${operation.target} from '
      '"${context.requestedRoot.path}"';
  if (Platform.environment[_packageWatchReuseKillSwitch] == '1') {
    return CCWatchReuseResult(
      succeeded: false,
      cycle: status['cycleRevision'] as int,
      message:
          'Package watch reuse is disabled by '
          '$_packageWatchReuseKillSwitch=1; $retry',
      logFile: logFile,
    );
  }
  if (status['packageCompletionEvidenceVersion'] != 1) {
    final targets = (status['targets'] as List).whereType<String>().toSet();
    final coverage = targets.contains(packageName)
        ? 'covers requested Package "$packageName"'
        : 'does not cover requested Package "$packageName"';
    return CCWatchReuseResult(
      succeeded: false,
      cycle: status['cycleRevision'] as int,
      message:
          'active Host watch at "$hostRoot" owns build root '
          '"${buildRoot.path}" and $coverage, but does not publish versioned Package '
          'completion evidence; $retry',
      logFile: logFile,
    );
  }

  var required = await _captureCurrentPackageWatchEvidence(
    packageName: packageName,
    packageRoot: context.requestedRoot,
    buildRoot: buildRoot,
    includeOutput: false,
  );
  final timeout = Stopwatch()..start();
  const maximumWait = Duration(minutes: 5);
  while (timeout.elapsed < maximumWait) {
    status = await _readPubHookBuildRootWatchStatus(buildRoot);
    if (status == null ||
        status['active'] != true ||
        !hasSameDirectoryIdentity(
          status['buildRoot'] as String,
          buildRoot.path,
        ) ||
        !await _pubHookWatchOwnerIsHeld(buildRoot)) {
      return CCWatchReuseResult(
        succeeded: false,
        cycle: 0,
        message: 'active Host watch became unavailable; $retry',
        logFile: logFile,
      );
    }
    final cycle = status['cycleRevision'] as int;
    final targets = (status['targets'] as List).whereType<String>().toSet();
    final rawEvidence = status['packageCompletionEvidence'];
    final packageEvidence = rawEvidence is Map
        ? rawEvidence[packageName]
        : null;
    if (targets.contains(packageName) && packageEvidence is Map) {
      final candidate = packageEvidence.cast<String, Object?>();
      final current = await _captureCurrentPackageWatchEvidence(
        packageName: packageName,
        packageRoot: context.requestedRoot,
        buildRoot: buildRoot,
        includeOutput: true,
      );
      if (!_packageWatchInputsEqual(current, required)) required = current;
      if (_packageWatchEvidenceMatches(
            candidate,
            required,
            packageName: packageName,
            packageRoot: context.requestedRoot,
          ) &&
          candidate['managedOutputFingerprint'] ==
              current.managedOutputFingerprint) {
        return CCWatchReuseResult(
          succeeded: true,
          cycle: cycle,
          message: 'active watch Package generation succeeded',
          logFile: logFile,
        );
      }
    }
    if (status['lastEvent'] == 'failed') {
      return CCWatchReuseResult(
        succeeded: false,
        cycle: cycle,
        message:
            'active Host watch cycle $cycle failed at '
            '${status['failureStage'] ?? 'generation'}',
        diagnostics: status['failureDiagnostics'] as String?,
        logFile: logFile,
      );
    }
    if (targets.contains(packageName) &&
        status['packageCompletionEvidenceState'] == 'unavailable') {
      return CCWatchReuseResult(
        succeeded: false,
        cycle: cycle,
        message:
            'active Host watch cycle $cycle completed without exact Package '
            'evidence for "$packageName"; $retry',
        logFile: logFile,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final lastStatus = status!;
  final targets = (lastStatus['targets'] as List).whereType<String>().toSet();
  final coverage = targets.contains(packageName)
      ? 'covers requested Package "$packageName" but did not publish '
            'matching completion evidence'
      : 'does not cover requested Package "$packageName"';
  return CCWatchReuseResult(
    succeeded: false,
    cycle: lastStatus['cycleRevision'] as int,
    message:
        'active Host watch at "$hostRoot" owns build root '
        '"${buildRoot.path}" and $coverage within 5 minutes; $retry',
    logFile: logFile,
  );
}

/// Current exact Package inputs, plus outputs when validating a candidate.
final class _CCPackageWatchEvidence {
  const _CCPackageWatchEvidence({
    required this.pubResolutionFingerprint,
    required this.authoredInputFingerprint,
    required this.managedOutputFingerprint,
  });

  final String pubResolutionFingerprint;
  final String authoredInputFingerprint;
  final String? managedOutputFingerprint;
}

Future<_CCPackageWatchEvidence> _captureCurrentPackageWatchEvidence({
  required String packageName,
  required Directory packageRoot,
  required Directory buildRoot,
  required bool includeOutput,
}) async => _CCPackageWatchEvidence(
  pubResolutionFingerprint: await CCPubResolutionFingerprint.capture(
    hostRoot: packageRoot,
    buildRoot: buildRoot,
  ),
  authoredInputFingerprint:
      await CCPackageWatchFingerprint.captureAuthoredInput(
        packageName: packageName,
        packageRoot: packageRoot,
      ),
  managedOutputFingerprint: includeOutput
      ? await CCPackageWatchFingerprint.captureManagedOutput(packageRoot)
      : null,
);

bool _packageWatchEvidenceMatches(
  Map<String, Object?> candidate,
  _CCPackageWatchEvidence required, {
  required String packageName,
  required Directory packageRoot,
}) =>
    candidate['schemaVersion'] == 1 &&
    candidate['package'] == packageName &&
    candidate['packageRoot'] is String &&
    hasSameDirectoryIdentity(
      candidate['packageRoot']! as String,
      packageRoot.path,
    ) &&
    candidate['pubResolutionFingerprint'] ==
        required.pubResolutionFingerprint &&
    candidate['authoredInputFingerprint'] ==
        required.authoredInputFingerprint &&
    candidate['managedOutputFingerprint'] is String;

bool _packageWatchInputsEqual(
  _CCPackageWatchEvidence left,
  _CCPackageWatchEvidence right,
) =>
    left.pubResolutionFingerprint == right.pubResolutionFingerprint &&
    left.authoredInputFingerprint == right.authoredInputFingerprint;

Future<Map<String, Object?>?> _readPubHookBuildRootWatchStatus(
  Directory buildRoot,
) async {
  try {
    final decoded = usesLegacyCCRouterCoordination()
        ? await _readPubHookJsonFile(
            File(
              path.join(
                buildRoot.path,
                '.dart_tool',
                'ccrouter',
                'v1',
                'watch',
                'builder-status.json',
              ),
            ),
          )
        : await readCCRouterBuilderSession(buildRoot: buildRoot);
    if (decoded == null ||
        decoded['schemaVersion'] != 1 ||
        decoded['active'] is! bool ||
        decoded['pid'] is! int ||
        decoded['cycleRevision'] is! int ||
        decoded['failureRevision'] is! int ||
        decoded['targets'] is! List ||
        !(decoded['targets'] as List).every((target) => target is String) ||
        decoded['hostRoot'] is! String ||
        decoded['buildRoot'] is! String ||
        decoded['updatedAt'] is! String) {
      return null;
    }
    return decoded;
  } on Object {
    return null;
  }
}

String? _readPubHookPackageName(Directory packageRoot) {
  try {
    final document = loadYaml(
      File(path.join(packageRoot.path, 'pubspec.yaml')).readAsStringSync(),
    );
    final name = document is YamlMap ? document['name'] : null;
    if (name is String && name.trim().isNotEmpty) return name.trim();
  } on Object {
    // The generator owns the authoritative malformed-manifest diagnostic.
  }
  return null;
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
    final encoded = command?.trim();
    final dartPub = encoded?.startsWith('dart:') ?? false;
    final normalized = dartPub ? encoded!.substring('dart:'.length) : encoded;
    final isPreflight = normalized == 'run' || normalized == 'build';
    final target = normalized == null || normalized.isEmpty
        ? '`ccrouter generate`'
        : isPreflight
        ? '`flutter $normalized`'
        : '`${dartPub ? 'dart' : 'flutter'} pub $normalized`';
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

/// Result of validating or waiting for an active generation watch.
final class CCWatchReuseResult {
  const CCWatchReuseResult({
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

/// Reuses exact active-watch evidence for an ordinary one-shot generation.
///
/// Commands whose semantics require their own execution path, such as
/// `--no-cache`, profile collection, custom output, and cleanup, do not call
/// this function. A null result means no active watch was observed or the
/// compatibility kill switch requested the former lock-conflict behavior.
Future<CCWatchReuseResult?> waitForCCOneShotWatch({
  required CCProjectContext context,
  required CCProjectRole role,
}) {
  if (Platform.environment[_oneShotWatchReuseKillSwitch] == '1') {
    return Future<CCWatchReuseResult?>.value();
  }
  return switch (role) {
    CCProjectRole.host => _waitForOneShotHostWatch(context),
    CCProjectRole.package => _waitForPackagePostPubWatch(
      context,
      _CCPubHookOperation(
        label: 'generation',
        target: '`ccrouter generate ${context.requestedRoot.path}`',
        isPostPub: false,
      ),
    ),
    CCProjectRole.skip => Future<CCWatchReuseResult?>.value(),
  };
}

/// Requires exact current inputs and outputs from one Host watch cycle.
Future<CCWatchReuseResult?> _waitForOneShotHostWatch(
  CCProjectContext context,
) async {
  final hostRoot = context.requestedRoot;
  final buildRoot = context.resolutionRoot;
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
  var status = await _readPostPubWatchStatus(
    hostRoot: hostRoot,
    buildRoot: buildRoot,
    localStatusFile: statusFile,
  );
  if (status == null || !_pubHookStatusMatchesHost(status, hostRoot)) {
    if (!await _pubHookWatchOwnerIsHeld(buildRoot)) return null;
    return CCWatchReuseResult(
      succeeded: false,
      cycle: 0,
      message:
          'active watch owns ${buildRoot.path}, but exact Host status for '
          '${hostRoot.path} is unavailable; stop and restart that watch',
      logFile: _pubHookWatchLogFile(hostRoot),
    );
  }
  if (!await _pubHookWatchIsActive(status)) return null;

  var requiredResolutionFingerprint = await CCPubResolutionFingerprint.capture(
    hostRoot: hostRoot,
    buildRoot: buildRoot,
  );
  final timeout = Stopwatch()..start();
  const maximumWait = Duration(minutes: 5);
  while (timeout.elapsed < maximumWait) {
    status = await _readPostPubWatchStatus(
      hostRoot: hostRoot,
      buildRoot: buildRoot,
      localStatusFile: statusFile,
    );
    if (status == null ||
        !_pubHookStatusMatchesHost(status, hostRoot) ||
        !await _pubHookWatchIsActive(status)) {
      return CCWatchReuseResult(
        succeeded: false,
        cycle: status?['cycle'] as int? ?? 0,
        message: 'active Host watch became unavailable',
        diagnostics: status?['failureDiagnostics'] as String?,
        logFile: _pubHookWatchLogFile(hostRoot),
      );
    }
    final cycle = status['cycle'] as int;
    if (status['lastEvent'] == 'failed') {
      return CCWatchReuseResult(
        succeeded: false,
        cycle: cycle,
        message:
            'active watch cycle $cycle failed at '
            '${status['failureStage'] ?? 'generation'}',
        diagnostics: status['failureDiagnostics'] as String?,
        logFile: _pubHookWatchLogFile(hostRoot),
      );
    }
    final lastEvent = status['lastEvent'];
    final terminalSuccess =
        lastEvent == 'ready' || lastEvent == 'aggregationSucceeded';
    if (terminalSuccess) {
      if (status['resolutionFingerprint'] != requiredResolutionFingerprint) {
        requiredResolutionFingerprint =
            await CCPubResolutionFingerprint.capture(
              hostRoot: hostRoot,
              buildRoot: buildRoot,
            );
      }
    }
    if (terminalSuccess &&
        status['resolutionFingerprint'] == requiredResolutionFingerprint) {
      if (status['packageCompletionEvidenceVersion'] != 1 ||
          status['packageCompletionEvidenceState'] != 'available' ||
          status['packageCompletionEvidence'] is! Map) {
        return CCWatchReuseResult(
          succeeded: false,
          cycle: cycle,
          message:
              'active watch cycle $cycle does not publish exact Host Package '
              'completion evidence; stop and restart the watch with the '
              'current CCRouter CLI',
          logFile: _pubHookWatchLogFile(hostRoot),
        );
      }
      final sessionId = status['sessionId'];
      final eventRevision = status['eventRevision'];
      final evidence = (status['packageCompletionEvidence'] as Map)
          .cast<Object?, Object?>();
      if (await _hostPackageEvidenceMatches(evidence, context: context)) {
        final confirmed = await _readPostPubWatchStatus(
          hostRoot: hostRoot,
          buildRoot: buildRoot,
          localStatusFile: statusFile,
        );
        if (confirmed != null &&
            confirmed['active'] == true &&
            confirmed['sessionId'] == sessionId &&
            confirmed['eventRevision'] == eventRevision &&
            await _pubHookWatchIsActive(confirmed)) {
          return CCWatchReuseResult(
            succeeded: true,
            cycle: cycle,
            message: 'exact active Host watch evidence matched',
            logFile: _pubHookWatchLogFile(hostRoot),
          );
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final latestStatus = status!;
  return CCWatchReuseResult(
    succeeded: false,
    cycle: latestStatus['cycle'] as int,
    message:
        'active watch did not publish exact current Host completion evidence '
        'within ${maximumWait.inMinutes} minutes',
    diagnostics: latestStatus['failureDiagnostics'] as String?,
    logFile: _pubHookWatchLogFile(hostRoot),
  );
}

Future<bool> _hostPackageEvidenceMatches(
  Map<Object?, Object?> evidence, {
  required CCProjectContext context,
}) async {
  try {
    final workspace = await CCPackageWorkspace.load(
      buildRoot: context.resolutionRoot,
      hostRoot: context.requestedRoot,
      workspace: context.isWorkspace,
    );
    final expected = <String, Directory>{
      for (final package in workspace.packages.values)
        if (package.writable && package.declaresGenerationIntent)
          package.name: package.root,
    };
    if (expected.isEmpty ||
        evidence.length != expected.length ||
        !evidence.keys.every(expected.containsKey)) {
      return false;
    }
    for (final entry in expected.entries) {
      final rawCandidate = evidence[entry.key];
      if (rawCandidate is! Map) return false;
      final candidate = rawCandidate.cast<String, Object?>();
      final current = await _captureCurrentPackageWatchEvidence(
        packageName: entry.key,
        packageRoot: entry.value,
        buildRoot: context.resolutionRoot,
        includeOutput: true,
      );
      if (!_packageWatchEvidenceMatches(
            candidate,
            current,
            packageName: entry.key,
            packageRoot: entry.value,
          ) ||
          candidate['managedOutputFingerprint'] !=
              current.managedOutputFingerprint) {
        return false;
      }
    }
    return true;
  } on Object {
    // Pub may atomically replace resolution files while watch starts a cycle.
    return false;
  }
}

/// Reuses one active Host watch instead of racing it with a one-shot generate.
///
/// Pub may rewrite Workspace resolution files before this process starts. Only
/// a terminal watch event for their exact current contents can satisfy the Hook.
Future<CCWatchReuseResult?> _waitForPostPubWatch(
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
  var status = await _readPostPubWatchStatus(
    hostRoot: hostRoot,
    buildRoot: buildRoot,
    localStatusFile: statusFile,
  );
  if (status == null) {
    if (!await _pubHookWatchOwnerIsHeld(buildRoot)) return null;
    return CCWatchReuseResult(
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
  final baselineSessionId = status['sessionId'] as String?;
  final baselineEventRevision = status['eventRevision'] as int?;
  final baselineCycle = status['cycle'] as int;
  final baselineUpdatedAt = status['updatedAt'] as String;
  final failureFenceEnabled =
      Platform.environment[_pubHookWatchFailureFenceKillSwitch] != '1';
  final timeout = Stopwatch()..start();
  const maximumWait = Duration(minutes: 5);
  while (timeout.elapsed < maximumWait) {
    status = await _readPostPubWatchStatus(
      hostRoot: hostRoot,
      buildRoot: buildRoot,
      localStatusFile: statusFile,
    );
    if (status == null || !_pubHookStatusMatchesHost(status, hostRoot)) {
      return CCWatchReuseResult(
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
    final sessionId = status['sessionId'] as String?;
    final sessionChanged =
        baselineSessionId != null &&
        sessionId != null &&
        sessionId != baselineSessionId;
    final sessionReady = status['sessionReady'] == true;
    if (matchesResolution &&
        (lastEvent == 'ready' ||
            (lastEvent == 'aggregationSucceeded' &&
                (!sessionChanged || sessionReady)))) {
      return CCWatchReuseResult(
        succeeded: true,
        cycle: cycle,
        message: 'active watch aggregation succeeded',
        logFile: _pubHookWatchLogFile(hostRoot),
      );
    }
    final eventRevision = status['eventRevision'] as int?;
    final isNewTerminalEvent = switch ((
      baselineSessionId,
      baselineEventRevision,
      sessionId,
      eventRevision,
    )) {
      (
        final String baselineSession,
        final int baselineRevision,
        final String currentSession,
        final int currentRevision,
      ) =>
        currentSession != baselineSession || currentRevision > baselineRevision,
      _ => cycle > baselineCycle || status['updatedAt'] != baselineUpdatedAt,
    };
    final acceptsFailure = failureFenceEnabled
        ? isNewTerminalEvent
        : matchesResolution;
    if (lastEvent == 'failed' && acceptsFailure) {
      final resolutionState = status['cycleResolutionState'] as String?;
      final message = matchesResolution
          ? 'active watch cycle $cycle failed at '
                '${status['failureStage'] ?? 'generation'}'
          : resolutionState == 'changed'
          ? 'active watch cycle $cycle failed after Pub resolution changed '
                'during the cycle; a new cycle or watch session is required'
          : 'active watch cycle $cycle failed without a matching Pub '
                'resolution proof; a new cycle or watch session is required';
      return CCWatchReuseResult(
        succeeded: false,
        cycle: cycle,
        message: message,
        diagnostics: status['failureDiagnostics'] as String?,
        logFile: _pubHookWatchLogFile(hostRoot),
      );
    }
    if (!await _pubHookWatchIsActive(status)) {
      return CCWatchReuseResult(
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
  return CCWatchReuseResult(
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

Future<Map<String, Object?>?> _readPostPubWatchStatus({
  required Directory hostRoot,
  required Directory buildRoot,
  required File localStatusFile,
}) {
  if (usesLegacyCCRouterCoordination()) {
    return _readPubHookWatchStatus(localStatusFile);
  }
  return readCCRouterHostSession(hostRoot: hostRoot, buildRoot: buildRoot);
}

Future<Map<String, Object?>?> _readPubHookJsonFile(File file) async {
  if (!file.existsSync()) return null;
  final decoded = jsonDecode(await file.readAsString());
  return decoded is Map ? decoded.cast<String, Object?>() : null;
}

bool _pubHookStatusMatchesHost(
  Map<String, Object?> status,
  Directory hostRoot,
) => hasSameDirectoryIdentity('${status['hostRoot']}', hostRoot.path);

Future<bool> _pubHookWatchIsActive(Map<String, Object?> status) async {
  if (status['active'] != true) return false;
  return _pubHookWatchOwnerIsHeld(Directory(status['buildRoot'] as String));
}

Future<bool> _pubHookWatchOwnerIsHeld(Directory buildRoot) async {
  return _pubHookOwnerFileIsHeld(ccrouterWatchOwnerLockFile(buildRoot));
}

Future<bool> _pubHookOwnerFileIsHeld(File owner) async {
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
    final item = _CCPubHookOutputLine(line, isError: isError);
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
    final visible = ccPubHookConciseFailureLines(
      _tail.map((item) => (line: item.line, isError: item.isError)),
    );
    stderr.writeln(
      _truncated
          ? 'Recent generator diagnostics (older lines omitted):'
          : 'Generator diagnostics:',
    );
    for (final line in visible) {
      stderr.writeln(line);
    }
  }

  /// Recognizes concise, version-stable generator completion messages.
  bool _isSummary(String line) =>
      line.startsWith('Validated ') ||
      line.startsWith('Generated Package artifacts for ') ||
      line == 'CCRouter generated artifacts are up to date.' ||
      line.startsWith('CCRouter generation fast path hit;') ||
      line.startsWith('CCRouter generation reused active watch cycle ') ||
      line.startsWith('CCRouter generation aggregate-only path;') ||
      line.startsWith('Bootstrapped generated component APIs ');
}

/// Removes routine Builder progress after a successful Builder phase.
///
/// Unknown output and every stderr line remain visible. If Builder never
/// reached its success summary, the complete bounded tail is returned so a
/// build failure cannot be hidden by presentation filtering.
List<String> ccPubHookConciseFailureLines(
  Iterable<({String line, bool isError})> lines,
) {
  final retained = lines.toList(growable: false);
  final builderSucceeded = retained.any(
    (item) =>
        !item.isError &&
        item.line.trimLeft().startsWith('Built with build_runner'),
  );
  if (!builderSucceeded) {
    return retained.map((item) => item.line).toList(growable: false);
  }
  return retained
      .where(
        (item) => item.isError || !_isRoutineBuildRunnerProgress(item.line),
      )
      .map((item) => item.line)
      .toList(growable: false);
}

/// Whether one stdout line is routine build_runner progress rather than a
/// terminal summary or Generator diagnostic.
bool _isRoutineBuildRunnerProgress(String line) {
  if (line.startsWith('Generating Package artifacts for ')) return true;
  return RegExp(
    r'^\s*\d+(?:\.\d+)?s\s+ccrouter_generator:[^\s]+\s+on\s+',
  ).hasMatch(line);
}

/// One retained line plus its encoded-size approximation.
final class _CCPubHookOutputLine {
  /// Creates one retained child-process line.
  const _CCPubHookOutputLine(this.line, {required this.isError});

  /// Exact decoded line without its newline terminator.
  final String line;

  /// Whether the child emitted this line on stderr.
  final bool isError;

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

parse_pub_invocation() {
  PUB_COMMAND=""
  PROJECT_DIRECTORY=""
  while [ "$#" -gt 0 ]; do
    ARG="$1"
    shift
    case "$ARG" in
      -h|--help)
        SKIP_PUB_HOOK=1
        return 0
        ;;
      -v|--verbose|--color|--no-color)
        ;;
      -C|--directory)
        if [ "$#" -eq 0 ]; then
          SKIP_PUB_HOOK=1
          return 0
        fi
        PROJECT_DIRECTORY="$1"
        shift
        ;;
      --directory=*)
        PROJECT_DIRECTORY="${ARG#--directory=}"
        ;;
      --)
        if [ "$#" -gt 0 ]; then
          PUB_COMMAND="$1"
          shift
        fi
        break
        ;;
      -*)
        SKIP_PUB_HOOK=1
        return 0
        ;;
      *)
        PUB_COMMAND="$ARG"
        break
        ;;
    esac
  done
  while [ "$#" -gt 0 ]; do
    ARG="$1"
    shift
    case "$ARG" in
      --help|-h|--dry-run|-n)
        SKIP_PUB_HOOK=1
        ;;
      -C|--directory)
        if [ "$#" -gt 0 ]; then
          PROJECT_DIRECTORY="$1"
          shift
        fi
        ;;
      --directory=*)
        PROJECT_DIRECTORY="${ARG#--directory=}"
        ;;
    esac
  done
}

parse_flutter_invocation() {
  FLUTTER_COMMAND=""
  PUB_COMMAND=""
  PROJECT_DIRECTORY=""
  SKIP_PUB_HOOK=0
  while [ "$#" -gt 0 ]; do
    ARG="$1"
    shift
    case "$ARG" in
      -h|--help|--version)
        SKIP_PUB_HOOK=1
        return 0
        ;;
      -v|-vv|--verbose|--prefixed-errors|--quiet|--wrap|--no-wrap|--machine|--color|--no-color|--version-check|--no-version-check|--enable-analytics|--disable-analytics|--suppress-analytics|--print-dtd|--show-test-device|--show-web-server-device|--ci)
        ;;
      -d|--device-id|--wrap-column|--packages|--local-engine-src-path|--local-engine|--local-engine-host|--local-web-sdk|--debug-logs-dir)
        if [ "$#" -eq 0 ]; then
          return 0
        fi
        shift
        ;;
      --device-id=*|--wrap-column=*|--packages=*|--local-engine-src-path=*|--local-engine=*|--local-engine-host=*|--local-web-sdk=*|--debug-logs-dir=*)
        ;;
      --)
        if [ "$#" -eq 0 ]; then
          return 0
        fi
        FLUTTER_COMMAND="$1"
        shift
        if [ "$FLUTTER_COMMAND" = "pub" ]; then
          parse_pub_invocation "$@"
        fi
        return 0
        ;;
      -*)
        return 0
        ;;
      *)
        FLUTTER_COMMAND="$ARG"
        if [ "$FLUTTER_COMMAND" = "pub" ]; then
          parse_pub_invocation "$@"
        fi
        return 0
        ;;
    esac
  done
}

resolve_project_root() {
  HOOK_DIR="${PROJECT_DIRECTORY:-$PWD}"
  if [[ "$HOOK_DIR" != /* ]]; then
    HOOK_DIR="$PWD/$HOOK_DIR"
  fi
  while [ ! -f "$HOOK_DIR/pubspec.yaml" ] && [ "$HOOK_DIR" != "/" ]; do
    HOOK_DIR="$(dirname -- "$HOOK_DIR")"
  done
  if [ ! -f "$HOOK_DIR/pubspec.yaml" ]; then
    return 1
  fi
  HOOK_DIR="$(cd -- "$HOOK_DIR" && pwd -P)" || return 1
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
  if ! resolve_project_root; then
    return 0
  fi
  (
    cd "$PROJECT_ROOT" || exit 1
    "$DART" run --verbosity=error ccrouter_generator:ccrouter pub-hook run \
      --project-root "$PROJECT_ROOT" --pub-command "$HOOK_COMMAND"
  )
}

run_clean_guard() {
  if ! resolve_project_root; then
    return 0
  fi
  (
    cd "$PROJECT_ROOT" || exit 1
    "$DART" run --verbosity=error ccrouter_generator:ccrouter pub-hook \
      guard-clean --project-root "$PROJECT_ROOT"
  )
}

parse_flutter_invocation "$@"
if [ "$FLUTTER_COMMAND" = "clean" ] && \
   [ "${CCROUTER_DISABLE_FLUTTER_CLEAN_GUARD:-0}" != "1" ]; then
  run_clean_guard
  GUARD_EXIT=$?
  if [ "$GUARD_EXIT" -ne 0 ]; then
    echo "CCRouter clean guard blocked flutter clean (exit $GUARD_EXIT)." >&2
    exit "$GUARD_EXIT"
  fi
  exec "$ORIGINAL" "$@"
fi
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
  FLUTTER_MACHINE=0
  for ARG in "$@"; do
    if [ "$ARG" = "--machine" ]; then
      FLUTTER_MACHINE=1
      break
    fi
  done
  if [ "$FLUTTER_MACHINE" -eq 1 ] && \
     [ "${CCROUTER_DISABLE_HOT_RELOAD_GATE:-0}" != "1" ]; then
    "$DART" run --verbosity=error \
      ccrouter_generator:ccrouter_flutter_run_supervisor \
      --host-root "$PROJECT_ROOT" --original "$ORIGINAL" \
      --launch-watch --reload-gate -- "$@"
  else
    "$DART" run --verbosity=error \
      ccrouter_generator:ccrouter_flutter_run_supervisor \
      --host-root "$PROJECT_ROOT" --original "$ORIGINAL" \
      --launch-watch -- "$@"
  fi
  exit $?
fi

if [ "$FLUTTER_COMMAND" != "pub" ]; then
  exec "$ORIGINAL" "$@"
fi

CCROUTER_PUB_HOOK_NESTED_FLUTTER=1 "$ORIGINAL" "$@"
PUB_EXIT=$?
if [ "$PUB_EXIT" -ne 0 ]; then
  exit "$PUB_EXIT"
fi

case "$PUB_COMMAND" in
  get|upgrade|downgrade|add|remove)
    ;;
  *)
    SKIP_PUB_HOOK=1
    ;;
esac
if [ "$SKIP_PUB_HOOK" -eq 1 ]; then
  exit 0
fi
run_generator_hook "$PUB_COMMAND" "$@"
HOOK_EXIT=$?
if [ "$HOOK_EXIT" -ne 0 ]; then
  echo "CCRouter pub hook failed after successful flutter pub (exit $HOOK_EXIT)." >&2
fi
exit "$HOOK_EXIT"
''';

/// POSIX wrapper installed over Flutter's inner Dart executable.
const _dartPosixWrapper = r'''#!/usr/bin/env bash
# CCRouter Dart pub hook wrapper. The original Dart executable is kept beside this file.
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ORIGINAL="$SCRIPT_DIR/dart.ccrouter-original"

if [ "${CCROUTER_PUB_HOOK_DISABLE:-0}" = "1" ]; then
  exec "$ORIGINAL" "$@"
fi
if [ "${CCROUTER_PUB_HOOK_NESTED_FLUTTER:-0}" = "1" ]; then
  exec "$ORIGINAL" "$@"
fi

parse_pub_invocation() {
  PUB_COMMAND=""
  PROJECT_DIRECTORY=""
  SKIP_PUB_HOOK=0
  while [ "$#" -gt 0 ]; do
    ARG="$1"
    shift
    case "$ARG" in
      -h|--help)
        SKIP_PUB_HOOK=1
        return 0
        ;;
      -v|--verbose|--color|--no-color)
        ;;
      -C|--directory)
        if [ "$#" -eq 0 ]; then
          SKIP_PUB_HOOK=1
          return 0
        fi
        PROJECT_DIRECTORY="$1"
        shift
        ;;
      --directory=*)
        PROJECT_DIRECTORY="${ARG#--directory=}"
        ;;
      --)
        if [ "$#" -gt 0 ]; then
          PUB_COMMAND="$1"
          shift
        fi
        break
        ;;
      -*)
        SKIP_PUB_HOOK=1
        return 0
        ;;
      *)
        PUB_COMMAND="$ARG"
        break
        ;;
    esac
  done
  while [ "$#" -gt 0 ]; do
    ARG="$1"
    shift
    case "$ARG" in
      --help|-h|--dry-run|-n)
        SKIP_PUB_HOOK=1
        ;;
      -C|--directory)
        if [ "$#" -gt 0 ]; then
          PROJECT_DIRECTORY="$1"
          shift
        fi
        ;;
      --directory=*)
        PROJECT_DIRECTORY="${ARG#--directory=}"
        ;;
    esac
  done
}

parse_dart_invocation() {
  DART_COMMAND=""
  while [ "$#" -gt 0 ]; do
    ARG="$1"
    shift
    case "$ARG" in
      -h|--help|--version)
        return 0
        ;;
      -v|--verbose|--enable-analytics|--disable-analytics|--diagnostics|--suppress-analytics)
        ;;
      --)
        if [ "$#" -eq 0 ]; then
          return 0
        fi
        DART_COMMAND="$1"
        shift
        if [ "$DART_COMMAND" = "pub" ]; then
          parse_pub_invocation "$@"
        fi
        return 0
        ;;
      -*)
        return 0
        ;;
      *)
        DART_COMMAND="$ARG"
        if [ "$DART_COMMAND" = "pub" ]; then
          parse_pub_invocation "$@"
        fi
        return 0
        ;;
    esac
  done
}

parse_dart_invocation "$@"
if [ "$DART_COMMAND" != "pub" ]; then
  exec "$ORIGINAL" "$@"
fi

"$ORIGINAL" "$@"
PUB_EXIT=$?
if [ "$PUB_EXIT" -ne 0 ]; then
  exit "$PUB_EXIT"
fi

case "$PUB_COMMAND" in
  get|upgrade|downgrade|add|remove)
    ;;
  *)
    SKIP_PUB_HOOK=1
    ;;
esac
if [ "$SKIP_PUB_HOOK" -eq 1 ]; then
  exit 0
fi

HOOK_DIR="${PROJECT_DIRECTORY:-$PWD}"
if [[ "$HOOK_DIR" != /* ]]; then
  HOOK_DIR="$PWD/$HOOK_DIR"
fi
while [ ! -f "$HOOK_DIR/pubspec.yaml" ] && [ "$HOOK_DIR" != "/" ]; do
  HOOK_DIR="$(dirname -- "$HOOK_DIR")"
done
if [ ! -f "$HOOK_DIR/pubspec.yaml" ]; then
  exit 0
fi
HOOK_DIR="$(cd -- "$HOOK_DIR" && pwd -P)" || exit 0
PROJECT_ROOT="$HOOK_DIR"
PACKAGE_CONFIG="$HOOK_DIR/.dart_tool/package_config.json"
while [ ! -f "$PACKAGE_CONFIG" ] && [ "$HOOK_DIR" != "/" ]; do
  HOOK_DIR="$(dirname -- "$HOOK_DIR")"
  PACKAGE_CONFIG="$HOOK_DIR/.dart_tool/package_config.json"
done
if [ ! -f "$PACKAGE_CONFIG" ] || \
   ! grep -Eq '"name"[[:space:]]*:[[:space:]]*"ccrouter_generator"' "$PACKAGE_CONFIG"; then
  exit 0
fi

(
  cd "$PROJECT_ROOT" || exit 1
  "$ORIGINAL" run --verbosity=error ccrouter_generator:ccrouter pub-hook run \
    --project-root "$PROJECT_ROOT" --pub-command "dart:$PUB_COMMAND"
)
HOOK_EXIT=$?
if [ "$HOOK_EXIT" -ne 0 ]; then
  echo "CCRouter pub hook failed after successful dart pub (exit $HOOK_EXIT)." >&2
fi
exit "$HOOK_EXIT"
''';

/// Windows PATH wrapper installed as `bin/dart.bat`.
///
/// IDEs that execute `cache/dart-sdk/bin/dart.exe` directly do not traverse a
/// batch entrypoint; status and documentation report that platform boundary.
const _dartWindowsWrapper = r'''@echo off
rem CCRouter Dart pub hook wrapper. The original Dart entrypoint is kept beside this file.
set "SCRIPT_DIR=%~dp0"
set "ORIGINAL=%SCRIPT_DIR%dart.ccrouter-original.bat"
if "%CCROUTER_PUB_HOOK_DISABLE%"=="1" goto invoke_original
if "%CCROUTER_PUB_HOOK_NESTED_FLUTTER%"=="1" goto invoke_original

call :parse_dart_invocation %*
if /I not "%DART_COMMAND%"=="pub" goto invoke_original

call "%ORIGINAL%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
if "%SKIP_PUB_HOOK%"=="1" exit /b 0
set "RUN_PUB_HOOK=0"
for %%C in (get upgrade downgrade add remove) do if /I "%PUB_COMMAND%"=="%%C" set "RUN_PUB_HOOK=1"
if not "%RUN_PUB_HOOK%"=="1" exit /b 0
call :resolve_project_root
if not "%ERRORLEVEL%"=="0" exit /b 0
set "HOOK_DIR=%PROJECT_ROOT%"
:find_package_config
if exist "%HOOK_DIR%\.dart_tool\package_config.json" goto package_config_found
for %%i in ("%HOOK_DIR%\..") do set "PARENT_DIR=%%~fi"
if /I "%PARENT_DIR%"=="%HOOK_DIR%" exit /b 0
set "HOOK_DIR=%PARENT_DIR%"
goto find_package_config
:package_config_found
findstr /R /C:"\"name\"[ ]*:[ ]*\"ccrouter_generator\"" "%HOOK_DIR%\.dart_tool\package_config.json" >nul
if not "%ERRORLEVEL%"=="0" exit /b 0
pushd "%PROJECT_ROOT%" || exit /b 1
call "%ORIGINAL%" run --verbosity=error ccrouter_generator:ccrouter pub-hook run --project-root "%PROJECT_ROOT%" --pub-command "dart:%PUB_COMMAND%"
set "HOOK_EXIT=%ERRORLEVEL%"
popd
if not "%HOOK_EXIT%"=="0" echo CCRouter pub hook failed after successful dart pub ^(exit %HOOK_EXIT%^). 1>&2
exit /b %HOOK_EXIT%

:invoke_original
call "%ORIGINAL%" %*
exit /b %ERRORLEVEL%

:parse_dart_invocation
set "DART_COMMAND="
set "PUB_COMMAND="
set "PROJECT_DIRECTORY="
set "SKIP_PUB_HOOK=0"
:parse_dart_global
if "%~1"=="" exit /b 0
if /I "%~1"=="-h" exit /b 0
if /I "%~1"=="--help" exit /b 0
if /I "%~1"=="--version" exit /b 0
for %%O in (-v --verbose --enable-analytics --disable-analytics --diagnostics --suppress-analytics) do if /I "%~1"=="%%O" goto parse_dart_shift
if "%~1"=="--" goto parse_dart_separator
set "HOOK_ARGUMENT=%~1"
if "%HOOK_ARGUMENT:~0,1%"=="-" exit /b 0
goto parse_dart_command
:parse_dart_shift
shift
goto parse_dart_global
:parse_dart_separator
shift
if "%~1"=="" exit /b 0
:parse_dart_command
set "DART_COMMAND=%~1"
shift
if /I "%DART_COMMAND%"=="pub" call :parse_pub_invocation %*
exit /b 0

:parse_pub_invocation
:parse_pub_global
if "%~1"=="" exit /b 0
if /I "%~1"=="-h" goto parse_pub_skip
if /I "%~1"=="--help" goto parse_pub_skip
for %%O in (-v --verbose --color --no-color) do if /I "%~1"=="%%O" goto parse_pub_shift
if /I "%~1"=="-C" goto parse_pub_directory
if /I "%~1"=="--directory" goto parse_pub_directory
set "HOOK_ARGUMENT=%~1"
if /I "%HOOK_ARGUMENT:~0,12%"=="--directory=" goto parse_pub_inline_directory
if "%~1"=="--" goto parse_pub_separator
if "%HOOK_ARGUMENT:~0,1%"=="-" goto parse_pub_skip
goto parse_pub_command
:parse_pub_directory
shift
if "%~1"=="" goto parse_pub_skip
set "PROJECT_DIRECTORY=%~1"
:parse_pub_shift
shift
goto parse_pub_global
:parse_pub_inline_directory
set "PROJECT_DIRECTORY=%HOOK_ARGUMENT:~12%"
goto parse_pub_shift
:parse_pub_separator
shift
if "%~1"=="" exit /b 0
:parse_pub_command
set "PUB_COMMAND=%~1"
shift
:parse_pub_tail
if "%~1"=="" exit /b 0
if /I "%~1"=="-h" set "SKIP_PUB_HOOK=1"
if /I "%~1"=="--help" set "SKIP_PUB_HOOK=1"
if /I "%~1"=="-n" set "SKIP_PUB_HOOK=1"
if /I "%~1"=="--dry-run" set "SKIP_PUB_HOOK=1"
if /I "%~1"=="-C" goto parse_pub_tail_directory
if /I "%~1"=="--directory" goto parse_pub_tail_directory
set "HOOK_ARGUMENT=%~1"
if /I "%HOOK_ARGUMENT:~0,12%"=="--directory=" set "PROJECT_DIRECTORY=%HOOK_ARGUMENT:~12%"
shift
goto parse_pub_tail
:parse_pub_tail_directory
shift
if "%~1"=="" exit /b 0
set "PROJECT_DIRECTORY=%~1"
shift
goto parse_pub_tail
:parse_pub_skip
set "SKIP_PUB_HOOK=1"
exit /b 0

:resolve_project_root
set "HOOK_DIR=%CD%"
if defined PROJECT_DIRECTORY set "HOOK_DIR=%PROJECT_DIRECTORY%"
:resolve_project_root_path
for %%i in ("%HOOK_DIR%") do set "HOOK_DIR=%%~fi"
:resolve_project_root_parent
if exist "%HOOK_DIR%\pubspec.yaml" (
  set "PROJECT_ROOT=%HOOK_DIR%"
  exit /b 0
)
for %%i in ("%HOOK_DIR%\..") do set "PARENT_DIR=%%~fi"
if /I "%PARENT_DIR%"=="%HOOK_DIR%" exit /b 1
set "HOOK_DIR=%PARENT_DIR%"
goto resolve_project_root_parent
''';

/// Windows wrapper installed as `bin/flutter.bat`.
const _windowsWrapper = r'''@echo off
rem CCRouter pub hook wrapper. The original Flutter entrypoint is kept beside this file.
rem CCRouter preflight hook: run/build generation is deliberately fail-closed.
set "SCRIPT_DIR=%~dp0"
set "ORIGINAL=%SCRIPT_DIR%flutter.ccrouter-original.bat"
if "%CCROUTER_PUB_HOOK_DISABLE%"=="1" goto invoke_original

call :parse_flutter_invocation %*
if /I "%FLUTTER_COMMAND%"=="clean" goto clean_guard
if /I "%FLUTTER_COMMAND%"=="run" goto preflight
if /I "%FLUTTER_COMMAND%"=="build" goto preflight
if /I not "%FLUTTER_COMMAND%"=="pub" goto invoke_original

setlocal
set "CCROUTER_PUB_HOOK_NESTED_FLUTTER=1"
call "%ORIGINAL%" %*
set "PUB_EXIT=%ERRORLEVEL%"
endlocal & set "PUB_EXIT=%PUB_EXIT%"
if not "%PUB_EXIT%"=="0" exit /b %PUB_EXIT%
if "%SKIP_PUB_HOOK%"=="1" exit /b 0
set "RUN_PUB_HOOK=0"
for %%C in (get upgrade downgrade add remove) do if /I "%PUB_COMMAND%"=="%%C" set "RUN_PUB_HOOK=1"
if not "%RUN_PUB_HOOK%"=="1" exit /b 0
set "HOOK_COMMAND=%PUB_COMMAND%"
goto run_hook

:preflight
set "HOOK_COMMAND=%FLUTTER_COMMAND%"
goto run_hook

:clean_guard
if "%CCROUTER_DISABLE_FLUTTER_CLEAN_GUARD%"=="1" goto invoke_original
set "HOOK_COMMAND=clean"
goto run_hook

:run_hook
call :resolve_project_root
if not "%ERRORLEVEL%"=="0" goto invoke_original
set "HOOK_DIR=%PROJECT_ROOT%"
:find_package_config
if exist "%HOOK_DIR%\.dart_tool\package_config.json" goto package_config_found
for %%i in ("%HOOK_DIR%\..") do set "PARENT_DIR=%%~fi"
if /I "%PARENT_DIR%"=="%HOOK_DIR%" goto invoke_original
set "HOOK_DIR=%PARENT_DIR%"
goto find_package_config
:package_config_found
findstr /R /C:"\"name\"[ ]*:[ ]*\"ccrouter_generator\"" "%HOOK_DIR%\.dart_tool\package_config.json" >nul
if not "%ERRORLEVEL%"=="0" goto invoke_original
pushd "%PROJECT_ROOT%" || goto hook_failed
if /I "%HOOK_COMMAND%"=="clean" (
  call "%SCRIPT_DIR%dart.bat" run --verbosity=error ccrouter_generator:ccrouter pub-hook guard-clean --project-root "%PROJECT_ROOT%"
) else (
  call "%SCRIPT_DIR%dart.bat" run --verbosity=error ccrouter_generator:ccrouter pub-hook run --project-root "%PROJECT_ROOT%" --pub-command "%HOOK_COMMAND%"
)
set "HOOK_EXIT=%ERRORLEVEL%"
popd
if not "%HOOK_EXIT%"=="0" goto hook_failed_with_exit
if /I "%HOOK_COMMAND%"=="clean" goto invoke_original
if /I "%HOOK_COMMAND%"=="build" goto invoke_original
if /I not "%HOOK_COMMAND%"=="run" exit /b 0
if "%CCROUTER_DISABLE_BUILD_WATCH%"=="1" goto invoke_original
set "FLUTTER_MACHINE=0"
for %%A in (%*) do if "%%~A"=="--machine" set "FLUTTER_MACHINE=1"
if "%CCROUTER_DISABLE_WINDOWS_RUN_SUPERVISOR%"=="1" goto run_with_legacy_watch
if "%FLUTTER_MACHINE%"=="1" if not "%CCROUTER_DISABLE_HOT_RELOAD_GATE%"=="1" goto run_with_supervisor_reload_gate
call "%SCRIPT_DIR%dart.bat" run --verbosity=error ccrouter_generator:ccrouter_flutter_run_supervisor --host-root "%PROJECT_ROOT%" --original "%ORIGINAL%" --launch-watch -- %*
exit /b %ERRORLEVEL%

:run_with_supervisor_reload_gate
call "%SCRIPT_DIR%dart.bat" run --verbosity=error ccrouter_generator:ccrouter_flutter_run_supervisor --host-root "%PROJECT_ROOT%" --original "%ORIGINAL%" --launch-watch --reload-gate -- %*
exit /b %ERRORLEVEL%

:run_with_legacy_watch
set "WATCH_DIR=%PROJECT_ROOT%\.dart_tool\ccrouter\v1\watch"
if not exist "%WATCH_DIR%" mkdir "%WATCH_DIR%"
set "WATCH_LEASE=%WATCH_DIR%\flutter-run-%RANDOM%-%RANDOM%.lease"
type nul > "%WATCH_LEASE%"
start "" /b "%SCRIPT_DIR%dart.bat" run --verbosity=error ccrouter_generator:ccrouter generate "%PROJECT_ROOT%" --watch=auto --machine --watch-lease "%WATCH_LEASE%" 1>>"%WATCH_DIR%\flutter-run.log" 2>>&1
echo CCRouter watch starting. Status: %WATCH_DIR%\status.json; log: %WATCH_DIR%\flutter-run.log
if "%CCROUTER_DISABLE_WATCH_STARTUP_HANDSHAKE%"=="1" goto watch_handshake_complete
call "%SCRIPT_DIR%dart.bat" run --verbosity=error ccrouter_generator:ccrouter_watch_startup --host-root "%PROJECT_ROOT%" --watch-lease "%WATCH_LEASE%"
set "WATCH_HANDSHAKE_EXIT=%ERRORLEVEL%"
if not "%WATCH_HANDSHAKE_EXIT%"=="0" goto watch_handshake_failed
:watch_handshake_complete
if "%FLUTTER_MACHINE%"=="1" if not "%CCROUTER_DISABLE_HOT_RELOAD_GATE%"=="1" goto run_with_reload_gate
call "%ORIGINAL%" %*
goto run_finished
:run_with_reload_gate
call "%SCRIPT_DIR%dart.bat" run --verbosity=error ccrouter_generator:ccrouter_flutter_run_gate --host-root "%PROJECT_ROOT%" --original "%ORIGINAL%" -- %*
:run_finished
set "ORIGINAL_EXIT=%ERRORLEVEL%"
del /q "%WATCH_LEASE%" >nul 2>&1
exit /b %ORIGINAL_EXIT%

:watch_handshake_failed
del /q "%WATCH_LEASE%" >nul 2>&1
echo CCRouter watch startup blocked flutter run ^(exit %WATCH_HANDSHAKE_EXIT%^). 1>&2
exit /b %WATCH_HANDSHAKE_EXIT%

:hook_failed
echo CCRouter hook failed for flutter %HOOK_COMMAND%. 1>&2
exit /b %ERRORLEVEL%

:hook_failed_with_exit
echo CCRouter hook failed for flutter %HOOK_COMMAND%. 1>&2
exit /b %HOOK_EXIT%

:invoke_original
call "%ORIGINAL%" %*
exit /b %ERRORLEVEL%

:parse_flutter_invocation
set "FLUTTER_COMMAND="
set "PUB_COMMAND="
set "PROJECT_DIRECTORY="
set "SKIP_PUB_HOOK=0"
:parse_flutter_global
if "%~1"=="" exit /b 0
if /I "%~1"=="-h" exit /b 0
if /I "%~1"=="--help" exit /b 0
if /I "%~1"=="--version" exit /b 0
for %%O in (-v -vv --verbose --prefixed-errors --quiet --wrap --no-wrap --machine --color --no-color --version-check --no-version-check --enable-analytics --disable-analytics --suppress-analytics --print-dtd --show-test-device --show-web-server-device --ci) do if /I "%~1"=="%%O" goto parse_flutter_shift
for %%O in (-d --device-id --wrap-column --packages --local-engine-src-path --local-engine --local-engine-host --local-web-sdk --debug-logs-dir) do if /I "%~1"=="%%O" goto parse_flutter_value
set "HOOK_ARGUMENT=%~1"
if /I "%HOOK_ARGUMENT:~0,12%"=="--device-id=" goto parse_flutter_shift
if /I "%HOOK_ARGUMENT:~0,14%"=="--wrap-column=" goto parse_flutter_shift
if /I "%HOOK_ARGUMENT:~0,11%"=="--packages=" goto parse_flutter_shift
if /I "%HOOK_ARGUMENT:~0,24%"=="--local-engine-src-path=" goto parse_flutter_shift
if /I "%HOOK_ARGUMENT:~0,15%"=="--local-engine=" goto parse_flutter_shift
if /I "%HOOK_ARGUMENT:~0,20%"=="--local-engine-host=" goto parse_flutter_shift
if /I "%HOOK_ARGUMENT:~0,16%"=="--local-web-sdk=" goto parse_flutter_shift
if /I "%HOOK_ARGUMENT:~0,17%"=="--debug-logs-dir=" goto parse_flutter_shift
if "%~1"=="--" goto parse_flutter_separator
if "%HOOK_ARGUMENT:~0,1%"=="-" exit /b 0
goto parse_flutter_command
:parse_flutter_value
shift
if "%~1"=="" exit /b 0
:parse_flutter_shift
shift
goto parse_flutter_global
:parse_flutter_separator
shift
if "%~1"=="" exit /b 0
:parse_flutter_command
set "FLUTTER_COMMAND=%~1"
shift
if /I "%FLUTTER_COMMAND%"=="pub" call :parse_pub_invocation %*
exit /b 0

:parse_pub_invocation
:parse_pub_global
if "%~1"=="" exit /b 0
if /I "%~1"=="-h" goto parse_pub_skip
if /I "%~1"=="--help" goto parse_pub_skip
for %%O in (-v --verbose --color --no-color) do if /I "%~1"=="%%O" goto parse_pub_shift
if /I "%~1"=="-C" goto parse_pub_directory
if /I "%~1"=="--directory" goto parse_pub_directory
set "HOOK_ARGUMENT=%~1"
if /I "%HOOK_ARGUMENT:~0,12%"=="--directory=" goto parse_pub_inline_directory
if "%~1"=="--" goto parse_pub_separator
if "%HOOK_ARGUMENT:~0,1%"=="-" goto parse_pub_skip
goto parse_pub_command
:parse_pub_directory
shift
if "%~1"=="" goto parse_pub_skip
set "PROJECT_DIRECTORY=%~1"
:parse_pub_shift
shift
goto parse_pub_global
:parse_pub_inline_directory
set "PROJECT_DIRECTORY=%HOOK_ARGUMENT:~12%"
goto parse_pub_shift
:parse_pub_separator
shift
if "%~1"=="" exit /b 0
:parse_pub_command
set "PUB_COMMAND=%~1"
shift
:parse_pub_tail
if "%~1"=="" exit /b 0
if /I "%~1"=="-h" set "SKIP_PUB_HOOK=1"
if /I "%~1"=="--help" set "SKIP_PUB_HOOK=1"
if /I "%~1"=="-n" set "SKIP_PUB_HOOK=1"
if /I "%~1"=="--dry-run" set "SKIP_PUB_HOOK=1"
if /I "%~1"=="-C" goto parse_pub_tail_directory
if /I "%~1"=="--directory" goto parse_pub_tail_directory
set "HOOK_ARGUMENT=%~1"
if /I "%HOOK_ARGUMENT:~0,12%"=="--directory=" set "PROJECT_DIRECTORY=%HOOK_ARGUMENT:~12%"
shift
goto parse_pub_tail
:parse_pub_tail_directory
shift
if "%~1"=="" exit /b 0
set "PROJECT_DIRECTORY=%~1"
shift
goto parse_pub_tail
:parse_pub_skip
set "SKIP_PUB_HOOK=1"
exit /b 0

:resolve_project_root
set "HOOK_DIR=%CD%"
if defined PROJECT_DIRECTORY set "HOOK_DIR=%PROJECT_DIRECTORY%"
:resolve_project_root_path
for %%i in ("%HOOK_DIR%") do set "HOOK_DIR=%%~fi"
:resolve_project_root_parent
if exist "%HOOK_DIR%\pubspec.yaml" (
  set "PROJECT_ROOT=%HOOK_DIR%"
  exit /b 0
)
for %%i in ("%HOOK_DIR%\..") do set "PARENT_DIR=%%~fi"
if /I "%PARENT_DIR%"=="%HOOK_DIR%" exit /b 1
set "HOOK_DIR=%PARENT_DIR%"
goto resolve_project_root_parent
''';
