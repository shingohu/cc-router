import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

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
          'schema': 2,
          'entrypoint': 'flutter',
          'generator': 'ccrouter_generator',
          'features': const <String>['pub', 'run', 'build'],
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
    final installed =
        markerValid &&
        posixBackupPresent &&
        posixValid &&
        windowsValid &&
        preflightEnabled;
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
          (value['schema'] == 1 || value['schema'] == 2) &&
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

/// Runs generation after a successful pub command. Non-CCRouter projects are
/// intentionally a zero-cost no-op once their resolved Package config is read.
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
  final stopwatch = Stopwatch()..start();
  stdout.writeln(
    'CCRouter pub hook started for `flutter ${pubCommand ?? 'pub command'}`.',
  );
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    'ccrouter_generator:ccrouter',
    'generate',
    root.path,
    '--profile',
  ], workingDirectory: root.path);
  final stdoutDone = process.stdout.listen(stdout.add).asFuture<void>();
  final stderrDone = process.stderr.listen(stderr.add).asFuture<void>();
  final exitCode = await process.exitCode;
  await Future.wait([stdoutDone, stderrDone]);
  stopwatch.stop();
  stdout.writeln(
    'CCRouter pub hook finished: exitCode=$exitCode, '
    'elapsed=${stopwatch.elapsedMilliseconds}ms.',
  );
  return exitCode == 0;
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
  exec "$ORIGINAL" "$@"
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
if "%ERRORLEVEL%"=="0" goto invoke_original
echo CCRouter hook failed for flutter %HOOK_COMMAND%. 1>&2
exit /b %ERRORLEVEL%

:invoke_original
call "%ORIGINAL%" %*
exit /b %ERRORLEVEL%
''';
