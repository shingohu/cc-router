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

  /// Runs generation for a project after a successful `flutter pub` command.
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
          'schema': 1,
          'entrypoint': 'flutter',
          'generator': 'ccrouter_generator',
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
      'The hook runs after `flutter pub get/upgrade/downgrade/add/remove`.',
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
    final installed =
        markerValid && posixBackupPresent && posixValid && windowsValid;
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
      'CCRouter pub hook result: ${installed ? 'installed and verified' : 'not installed or inconsistent'}',
    );
    return installed;
  }

  bool _isMarker(File file) {
    if (!file.existsSync()) return false;
    try {
      final value = jsonDecode(file.readAsStringSync());
      return value is Map &&
          value['schema'] == 1 &&
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
    'CCRouter pub hook started after `flutter pub ${pubCommand ?? 'command'}`.',
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
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ORIGINAL="$SCRIPT_DIR/flutter.ccrouter-original"
DART="$SCRIPT_DIR/dart"

if [ "${CCROUTER_PUB_HOOK_DISABLE:-0}" = "1" ]; then
  exec "$ORIGINAL" "$@"
fi

if [ "${1:-}" != "pub" ]; then
  exec "$ORIGINAL" "$@"
fi

"$ORIGINAL" "$@"
PUB_EXIT=$?
if [ "$PUB_EXIT" -ne 0 ]; then
  exit "$PUB_EXIT"
fi

case "${2:-}" in
  get|upgrade|downgrade|add|remove) ;;
  *) exit 0 ;;
esac

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
  exit 0
fi

PACKAGE_CONFIG="$HOOK_DIR/.dart_tool/package_config.json"
PROJECT_ROOT="$HOOK_DIR"
while [ ! -f "$PACKAGE_CONFIG" ] && [ "$HOOK_DIR" != "/" ]; do
  HOOK_DIR="$(dirname -- "$HOOK_DIR")"
  PACKAGE_CONFIG="$HOOK_DIR/.dart_tool/package_config.json"
done
if [ ! -f "$PACKAGE_CONFIG" ] || \
   ! grep -Eq '"name"[[:space:]]*:[[:space:]]*"ccrouter_generator"' "$PACKAGE_CONFIG"; then
  exit 0
fi

"$DART" run ccrouter_generator:ccrouter pub-hook run \
  --project-root "$PROJECT_ROOT" --pub-command "${2:-command}"
HOOK_EXIT=$?
if [ "$HOOK_EXIT" -ne 0 ]; then
  echo "CCRouter pub hook failed after successful flutter pub (exit $HOOK_EXIT)." >&2
fi
exit "$HOOK_EXIT"
''';

/// Windows wrapper installed as `bin/flutter.bat`.
const _windowsWrapper = r'''@echo off
rem CCRouter pub hook wrapper. The original Flutter entrypoint is kept beside this file.
set "SCRIPT_DIR=%~dp0"
set "ORIGINAL=%SCRIPT_DIR%flutter.ccrouter-original.bat"
if "%CCROUTER_PUB_HOOK_DISABLE%"=="1" (
  call "%ORIGINAL%" %*
  exit /b %ERRORLEVEL%
)
if /I not "%~1"=="pub" (
  call "%ORIGINAL%" %*
  exit /b %ERRORLEVEL%
)
call "%ORIGINAL%" %*
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
if /I not "%~2"=="get" if /I not "%~2"=="upgrade" if /I not "%~2"=="downgrade" if /I not "%~2"=="add" if /I not "%~2"=="remove" exit /b 0
set "HOOK_DIR=%CD%"
if not exist "%HOOK_DIR%\pubspec.yaml" exit /b 0
set "PROJECT_ROOT=%HOOK_DIR%"
:find_package_config
if exist "%HOOK_DIR%\.dart_tool\package_config.json" goto package_config_found
for %%i in ("%HOOK_DIR%\..") do set "PARENT_DIR=%%~fi"
if /I "%PARENT_DIR%"=="%HOOK_DIR%" exit /b 0
set "HOOK_DIR=%PARENT_DIR%"
goto find_package_config
:package_config_found
findstr /R /C:"\"name\"[ ]*:[ ]*\"ccrouter_generator\"" "%HOOK_DIR%\.dart_tool\package_config.json" >nul
if not "%ERRORLEVEL%"=="0" exit /b 0
call "%SCRIPT_DIR%dart.bat" run ccrouter_generator:ccrouter pub-hook run --project-root "%PROJECT_ROOT%" --pub-command "%~2"
exit /b %ERRORLEVEL%
''';
