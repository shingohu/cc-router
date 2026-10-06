part of 'analyzer_bootstrap.dart';

/// Validated, portable dependency identity for an isolated Analyzer loader.
final class _AnalyzerSource {
  const _AnalyzerSource(
    this.kind, {
    this.version,
    this.url,
    this.ref,
    this.gitPath,
  });
  final String kind;
  final String? version;
  final String? url;
  final String? ref;
  final String? gitPath;

  factory _AnalyzerSource.select(
    CCAnalyzerBootstrapRequest request,
    Map<String, Object?>? installed,
  ) {
    final upgrading = request.action == CCAnalyzerBootstrapAction.upgrade;
    final previous = _stringKeyedMap(installed?['source']);
    final kind =
        request.source ??
        (upgrading ? previous['kind'] as String? : null) ??
        'hosted';
    if (!['hosted', 'git'].contains(kind))
      throw ArgumentError('source must be hosted or git.');
    if (upgrading && kind != previous['kind']) {
      throw ArgumentError(
        'upgrade cannot switch dependency source; uninstall and install explicitly.',
      );
    }
    if (kind == 'hosted') {
      if (request.url != null ||
          request.ref != null ||
          request.gitPath != null) {
        throw ArgumentError(
          'Hosted source cannot use --url, --ref or --git-path.',
        );
      }
      final version = request.version;
      final constraint = _constraint(version);
      if (version == null ||
          constraint == null ||
          constraint.isAny ||
          constraint.isEmpty) {
        throw ArgumentError(
          'Hosted install/upgrade requires an explicit --version constraint. '
          'The source manifest version does not prove a Hosted release exists.',
        );
      }
      return _AnalyzerSource(kind, version: version);
    }
    if (request.version != null)
      throw ArgumentError('Git source cannot use --version.');
    final url = request.url ?? (upgrading ? previous['url'] as String? : null);
    final ref = request.ref;
    final gitPath =
        request.gitPath ??
        (upgrading ? previous['gitPath'] as String? : null) ??
        'packages/ccrouter_analyzer_plugin';
    final uri = url == null ? null : Uri.tryParse(url);
    final remoteUri =
        uri != null &&
        ['https', 'ssh'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.scheme == 'ssh'
            ? !uri.userInfo.contains(':')
            : uri.userInfo.isEmpty);
    final scp =
        url != null && RegExp(r'^[\w.-]+@[\w.-]+:[\w./-]+$').hasMatch(url);
    if (!remoteUri && !scp)
      throw ArgumentError(
        'Git requires a remote HTTPS/SSH --url without credentials; local repositories are refused.',
      );
    if (ref == null || !RegExp(r'^[0-9a-f]{40}$').hasMatch(ref)) {
      throw ArgumentError(
        'Git requires --ref with a full 40-character commit SHA.',
      );
    }
    if (gitPath.isEmpty ||
        path.posix.isAbsolute(gitPath) ||
        gitPath.contains('\\') ||
        gitPath.split('/').any((part) => part == '..' || part.isEmpty)) {
      throw ArgumentError('Invalid --git-path.');
    }
    return _AnalyzerSource(kind, url: url, ref: ref, gitPath: gitPath);
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (version != null) 'version': version,
    if (url != null) 'url': url,
    if (ref != null) 'ref': ref,
    if (gitPath != null) 'gitPath': gitPath,
  };

  /// JSON scalar syntax is valid YAML and avoids injecting URL/constraint text.
  String manifest(String pluginName) =>
      '''# Managed by ccrouter analyzer. Do not edit.
name: ${pluginName}_loader
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  analyzer: 8.4.0
  analyzer_plugin: 0.13.10
  ccrouter_analyzer_plugin: ${kind == 'hosted' ? jsonEncode(version) : '\n    git:\n      url: ${jsonEncode(url)}\n      ref: $ref\n      path: ${jsonEncode(gitPath)}'}
''';
}

/// Verifies Analyzer-specific Flutter and SDK constraints after the shared role
/// resolver has proven that [host] is a CCRouter Host.
Map<String, Object?> _inspectAnalyzerHost(Directory host) {
  final manifest = _readYamlMap(File(path.join(host.path, 'pubspec.yaml')));
  if (manifest == null)
    throw StateError('Host pubspec.yaml is missing or invalid.');
  final dependencies = _stringKeyedMap(manifest['dependencies']);
  if (!dependencies.containsKey('ccrouter') ||
      _stringKeyedMap(dependencies['flutter'])['sdk'] != 'flutter') {
    throw StateError(
      'Select a Flutter CCRouter Host with direct ccrouter/flutter dependencies; '
      'aggregators and non-Host Packages are not installation targets.',
    );
  }
  final name = manifest['name'];
  if (name is! String || !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name))
    throw StateError('Invalid Host package name.');
  final sdk = Version.parse(Platform.version.split(' ').first);
  if (sdk < Version(3, 10, 0) ||
      sdk.major != 3 ||
      !(_constraint(
            _stringKeyedMap(manifest['environment'])['sdk']?.toString(),
          )?.allows(sdk) ??
          false)) {
    throw StateError(
      'Analyzer bootstrap requires a compatible Dart 3.10+ SDK and Host SDK constraint.',
    );
  }
  return _stringKeyedMap(manifest);
}

/// Refuses inherited plugin conflicts as well as locally enabled plugins.
void _checkAnalyzerIncludes(
  Directory host,
  File options,
  Set<String> visited, {
  String? ownedPlugin,
}) {
  if (!options.existsSync()) return;
  _checkAnalyzerPath(options.path);
  if (!visited.add(options.path) || visited.length > 20)
    throw StateError('Cyclic or excessive analysis_options includes.');
  final map = _analyzerYaml(options.readAsStringSync(), options.path);
  final plugins = _stringKeyedMap(map['analyzer'])['plugins'];
  final owned =
      ownedPlugin != null &&
      plugins is List &&
      plugins.length == 1 &&
      plugins.single == ownedPlugin;
  if (!owned && plugins != null && (plugins is! List || plugins.isNotEmpty)) {
    throw StateError(
      'Existing Analyzer plugin configuration must be managed manually: ${options.path}',
    );
  }
  // Dart 3.10+ top-level plugin syntax must not be silently combined either.
  if (map.containsKey('plugins'))
    throw StateError(
      'Existing top-level plugin configuration conflicts with legacy bootstrap.',
    );
  final include = map['include'];
  if (include == null) return;
  if (include is! String)
    throw StateError('Unsupported analysis_options include.');
  final uri = Uri.tryParse(include);
  File target;
  if (uri?.scheme == 'package') {
    final segments = uri!.pathSegments;
    if (segments.length < 2)
      throw StateError('Invalid Package include: $include');
    final root = _resolvePackageRoot(host, segments.first);
    if (root == null)
      throw StateError('Resolve Host dependencies before inspecting $include.');
    target = File(path.join(root.path, 'lib', path.joinAll(segments.skip(1))));
  } else if (uri != null && !uri.hasScheme) {
    target = File(path.normalize(path.join(options.parent.path, include)));
  } else {
    throw StateError('Unsupported analysis_options include: $include');
  }
  if (!target.existsSync())
    throw StateError('Missing analysis_options include: ${target.path}');
  _checkAnalyzerIncludes(host, target, visited);
}

/// Executes a subprocess stage, preserving a bounded failure tail.
Future<void> _analyzerStage(
  AnalyzerBootstrapProcessRunner runner,
  String executable,
  List<String> arguments,
  Directory directory,
  String label,
) async {
  stdout.writeln('CCRouter Analyzer: $label...');
  final result = await runner(
    executable,
    arguments,
    workingDirectory: directory.path,
    environment: const {
      'CCROUTER_PUB_HOOK_DISABLE': '1',
      'GIT_TERMINAL_PROMPT': '0',
    },
  );
  if (result.exitCode != 0)
    throw StateError(
      '$label failed (${result.exitCode}).\n${result.stdout}\n${result.stderr}',
    );
}

/// Verifies a candidate in isolation, including remote provenance for Git.
Future<void> _verifyAnalyzerCandidate(
  Directory staging,
  Directory candidate,
  String pluginName,
  _AnalyzerSource source,
  AnalyzerBootstrapProcessRunner runner,
) async {
  if (source.kind == 'git') {
    final git = Directory(path.join(staging.path, 'remote-proof'))
      ..createSync();
    await _analyzerStage(
      runner,
      'git',
      ['init', '--bare', '--quiet'],
      git,
      'prepare remote commit proof',
    );
    await _analyzerStage(
      runner,
      'git',
      ['fetch', '--quiet', '--no-tags', '--depth=1', source.url!, source.ref!],
      git,
      'verify remote commit',
    );
  }
  final bootstrap = Directory(
    path.join(candidate.path, 'tools', 'analyzer_plugin'),
  );
  await _analyzerStage(
    runner,
    Platform.resolvedExecutable,
    ['pub', 'get'],
    bootstrap,
    'resolve isolated bootstrap',
  );
  // Reuse status and doctor without publishing unverified Host configuration.
  final probe = Directory(path.join(staging.path, 'probe'))..createSync();
  File(
    path.join(probe.path, 'pubspec.yaml'),
  ).writeAsStringSync('name: analyzer_probe\ndependencies:\n  ccrouter: any\n');
  File(
    path.join(probe.path, 'analysis_options.yaml'),
  ).writeAsStringSync('analyzer:\n  plugins:\n    - $pluginName\n');
  Directory(path.join(probe.path, '.dart_tool')).createSync();
  File(
    path.join(probe.path, '.dart_tool', 'package_config.json'),
  ).writeAsStringSync(
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': pluginName,
          'rootUri': candidate.uri.toString(),
          'packageUri': 'lib/',
        },
      ],
    }),
  );
  final report = _AnalyzerBootstrapReport.inspect(probe);
  if (report.state != _AnalyzerBootstrapState.healthy)
    throw StateError(report.message);
  if (!await _runDoctor(report, runner: runner))
    throw StateError('Candidate loader verification failed.');
}

/// Prints a concrete plan and applies it under the Pub owner's exclusive lock.
Future<bool> _runAnalyzerInstallation(
  CCAnalyzerBootstrapRequest request,
  AnalyzerBootstrapProcessRunner runner,
) async {
  final input = Directory(request.hostRoot).absolute;
  if (!input.existsSync())
    throw StateError('Host does not exist: ${input.path}');
  final context = CCProjectContext.resolve(input);
  final role = CCProjectRoleResolver.resolve(context);
  if (role.role != CCProjectRole.host) {
    throw StateError(
      'Selected Package is `${role.role.name}`, not a CCRouter Host. Use '
      '`.metadata` project_type app or set `ccrouter.yaml` host.enabled true.',
    );
  }
  final host = Directory(context.requestedRoot.resolveSymbolicLinksSync());
  final manifest = _inspectAnalyzerHost(host);
  final owner = Directory(context.resolutionRoot.resolveSymbolicLinksSync());
  final wrapper = Directory(path.join(host.path, _analyzerWrapperPath));
  final marker = File(path.join(wrapper.path, _analyzerOwnershipFile));
  final pluginName = '${manifest['name']}_ccrouter_analyzer';
  final manifestFile = File(path.join(host.path, 'pubspec.yaml'));
  final optionsFile = File(path.join(host.path, 'analysis_options.yaml'));
  final originalManifest = utf8.decode(_analyzerBytes(manifestFile.path)!);
  final originalOptionsBytes = _analyzerBytes(optionsFile.path);
  var originalOptions = originalOptionsBytes == null
      ? '{}\n'
      : utf8.decode(originalOptionsBytes);
  String? inheritedInclude;
  if (originalOptionsBytes == null) {
    var parent = host.parent;
    while (parent.path != parent.parent.path) {
      final inherited = File(path.join(parent.path, 'analysis_options.yaml'));
      if (inherited.existsSync()) {
        _checkAnalyzerIncludes(host, inherited, {});
        inheritedInclude = path
            .relative(inherited.path, from: host.path)
            .replaceAll(path.separator, '/');
        originalOptions = 'include: ${jsonEncode(inheritedInclude)}\n';
        break;
      }
      parent = parent.parent;
    }
  }
  final options = _analyzerYaml(originalOptions, optionsFile.path);
  _checkAnalyzerPath(marker.path);
  Map<String, Object?>? installed;
  if (marker.existsSync()) {
    installed = (jsonDecode(marker.readAsStringSync()) as Map)
        .cast<String, Object?>();
    if (installed['schema'] != 1 || installed['plugin'] != pluginName)
      throw StateError('Unknown Analyzer ownership record.');
    final files = _stringKeyedMap(installed['files']);
    if (files.length != _analyzerOwnedFiles.length ||
        !files.keys.toSet().containsAll(_analyzerOwnedFiles)) {
      throw StateError('Invalid Analyzer ownership file list.');
    }
    for (final relative in _analyzerOwnedFiles) {
      final bytes = _analyzerBytes(path.join(wrapper.path, relative));
      if (bytes == null ||
          sha256.convert(bytes).toString() != files[relative]) {
        throw StateError(
          'CLI-owned Analyzer file was modified: $relative. Preserve it and use manual recovery.',
        );
      }
    }
    final dependency = _stringKeyedMap(
      _stringKeyedMap(manifest['dev_dependencies'])[pluginName],
    );
    final plugins = _stringKeyedMap(options['analyzer'])['plugins'];
    if (dependency.length != 1 ||
        dependency['path'] != _analyzerWrapperPath ||
        jsonEncode(plugins) != jsonEncode([pluginName])) {
      throw StateError(
        'CLI-owned YAML entries changed; refusing to overwrite user configuration.',
      );
    }
    _checkAnalyzerIncludes(host, optionsFile, {}, ownedPlugin: pluginName);
  } else {
    if (request.action == CCAnalyzerBootstrapAction.uninstall &&
        !wrapper.existsSync() &&
        !_stringKeyedMap(
          manifest['dev_dependencies'],
        ).containsKey(pluginName)) {
      _checkAnalyzerIncludes(host, optionsFile, {});
      stdout.writeln('Analyzer is not installed for ${host.path}; no changes.');
      return true;
    }
    if (request.action != CCAnalyzerBootstrapAction.install)
      throw StateError(
        'No CLI-owned Analyzer installation. Manual bootstraps are never adopted implicitly.',
      );
    if (wrapper.existsSync())
      throw StateError('Unmanaged bootstrap already exists: ${wrapper.path}');
    _checkAnalyzerIncludes(host, optionsFile, {});
    for (final field in [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ]) {
      if (_stringKeyedMap(manifest[field]).containsKey(pluginName))
        throw StateError('Existing $pluginName dependency is not CLI-owned.');
    }
    for (final field in ['dev_dependencies']) {
      if (manifest.containsKey(field) && manifest[field] is! Map)
        throw StateError('$field must be a YAML mapping.');
    }
    if (options.containsKey('analyzer') && options['analyzer'] is! Map)
      throw StateError('analyzer must be a YAML mapping.');
  }
  final source = request.action == CCAnalyzerBootstrapAction.uninstall
      ? null
      : _AnalyzerSource.select(request, installed);
  final originals = <String, List<int>?>{
    manifestFile.path: utf8.encode(originalManifest),
    optionsFile.path: originalOptionsBytes,
    marker.path: _analyzerBytes(marker.path),
    for (final relative in _analyzerOwnedFiles)
      path.join(wrapper.path, relative): _analyzerBytes(
        path.join(wrapper.path, relative),
      ),
  };
  stdout.writeln(
    'CCRouter Analyzer ${request.action.name}${request.dryRun ? ' (dry-run)' : ''}',
  );
  stdout.writeln(
    '  host: ${host.path}\n  pub owner: ${owner.path}\n  bootstrap: ${wrapper.path}',
  );
  if (source != null)
    stdout.writeln(
      '  source: ${source.kind}\n  identity: ${source.version ?? source.ref}',
    );
  stdout.writeln(
    '  managed: Host dev_dependency, analyzer.plugins, ${_analyzerOwnedFiles.length} bootstrap files and ownership record',
  );
  stdout.writeln(
    '  preserved: unrelated YAML, unknown files, IDE/Pub caches and generated artifacts',
  );
  final sameSource =
      installed != null &&
      source != null &&
      jsonEncode(installed['source']) == jsonEncode(source.toJson());
  if (request.action == CCAnalyzerBootstrapAction.install &&
      installed != null &&
      !sameSource) {
    throw StateError('Installed source differs; use explicit upgrade.');
  }
  if (request.dryRun) return true;
  if (sameSource) {
    if (_AnalyzerBootstrapReport.inspect(host).state !=
        _AnalyzerBootstrapState.healthy) {
      throw StateError(
        'Installed files are unchanged but Host resolution is incomplete; run flutter pub get from this Host.',
      );
    }
    stdout.writeln('Already installed; no files or lockfiles changed.');
    return true;
  }

  final stateRoot = Directory(
    path.join(owner.path, '.dart_tool', 'ccrouter', 'analyzer'),
  );
  _checkAnalyzerPath(stateRoot.path);
  stateRoot.createSync(recursive: true);
  final lock = File(
    path.join(stateRoot.path, 'operation.lock'),
  ).openSync(mode: FileMode.append);
  var locked = false;
  Directory? staging;
  _AnalyzerFileTransaction? transaction;
  try {
    lock.lockSync(FileLock.exclusive);
    locked = true;
    final journals = Directory(path.join(stateRoot.path, 'transactions'));
    if (journals.existsSync() && journals.listSync().isNotEmpty) {
      throw StateError(
        'An interrupted Analyzer transaction needs recovery: ${journals.path}',
      );
    }
    // Compare the source configuration again after acquiring the shared lock.
    if (!_sameAnalyzerBytes(
          _analyzerBytes(manifestFile.path),
          utf8.encode(originalManifest),
        ) ||
        !_sameAnalyzerBytes(
          _analyzerBytes(optionsFile.path),
          originalOptionsBytes,
        )) {
      throw StateError('Host configuration changed during preflight; retry.');
    }
    if (request.action == CCAnalyzerBootstrapAction.upgrade) {
      final previous = _AnalyzerBootstrapReport.inspect(host);
      if (previous.state != _AnalyzerBootstrapState.healthy ||
          !await _runDoctor(previous, runner: runner)) {
        throw StateError(
          'Existing installation must pass doctor before upgrade.',
        );
      }
    }
    staging = Directory.systemTemp.createTempSync('ccrouter-analyzer-install-');
    final changes = <String, List<int>?>{};
    if (source != null) {
      final candidate = Directory(path.join(staging.path, 'candidate'))
        ..createSync();
      final inner = Directory(
        path.join(candidate.path, 'tools', 'analyzer_plugin', 'bin'),
      )..createSync(recursive: true);
      File(path.join(candidate.path, 'pubspec.yaml')).writeAsStringSync(
        '''# Managed by ccrouter analyzer. Do not edit.
name: $pluginName
publish_to: none
environment:
  sdk: ^3.10.0
''',
      );
      File(
        path.join(inner.parent.path, 'pubspec.yaml'),
      ).writeAsStringSync(source.manifest(pluginName));
      File(
        path.join(inner.path, 'plugin.dart'),
      ).writeAsStringSync(_analyzerLoader);
      await _verifyAnalyzerCandidate(
        staging,
        candidate,
        pluginName,
        source,
        runner,
      );
      final hashes = <String, String>{};
      for (final relative in _analyzerOwnedFiles) {
        final bytes = File(
          path.join(candidate.path, relative),
        ).readAsBytesSync();
        changes[path.join(wrapper.path, relative)] = bytes;
        hashes[relative] = sha256.convert(bytes).toString();
      }
      final ownership = <String, Object?>{
        'schema': 1,
        'inheritedInclude': installed?['inheritedInclude'] ?? inheritedInclude,
        'plugin': pluginName,
        'source': source.toJson(),
        'files': hashes,
        'hadDevDependencies':
            installed?['hadDevDependencies'] ??
            manifest.containsKey('dev_dependencies'),
        'hadAnalyzer':
            installed?['hadAnalyzer'] ?? options.containsKey('analyzer'),
        'hadPlugins':
            installed?['hadPlugins'] ??
            _stringKeyedMap(options['analyzer']).containsKey('plugins'),
        'hadOptions':
            installed?['hadOptions'] ?? (originalOptionsBytes != null),
      };
      changes[marker.path] = utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(ownership)}\n',
      );
      if (installed == null) {
        changes[manifestFile.path] = utf8.encode(
          _setAnalyzerLeaf(
            originalManifest,
            ['dev_dependencies', pluginName],
            {'path': _analyzerWrapperPath},
          ),
        );
        changes[optionsFile.path] = utf8.encode(
          _setAnalyzerLeaf(
            originalOptions,
            ['analyzer', 'plugins'],
            [pluginName],
          ),
        );
      }
    } else {
      for (final relative in _analyzerOwnedFiles) {
        changes[path.join(wrapper.path, relative)] = null;
      }
      changes[marker.path] = null;
      changes[manifestFile.path] = utf8.encode(
        _removeAnalyzerLeaf(originalManifest, [
          'dev_dependencies',
          pluginName,
        ], removeParent: installed!['hadDevDependencies'] == false),
      );
      var restoredOptions = installed['hadPlugins'] == true
          ? _setAnalyzerLeaf(originalOptions, [
              'analyzer',
              'plugins',
            ], <String>[])
          : _removeAnalyzerLeaf(originalOptions, [
              'analyzer',
              'plugins',
            ], removeParent: installed['hadAnalyzer'] == false);
      final restoredMap = _analyzerYaml(restoredOptions, optionsFile.path);
      changes[optionsFile.path] =
          installed['hadOptions'] == false &&
              (restoredMap.isEmpty ||
                  (restoredMap.length == 1 &&
                      restoredMap['include'] == installed['inheritedInclude']))
          ? null
          : utf8.encode(restoredOptions);
    }
    transaction = _AnalyzerFileTransaction(
      Directory(
        path.join(
          journals.path,
          '$pid-${DateTime.now().microsecondsSinceEpoch}',
        ),
      ),
    );
    final pubFiles = <String>{
      for (final root in {host.path, owner.path}) ...[
        path.join(root, 'pubspec.lock'),
        path.join(root, '.dart_tool', 'package_config.json'),
        path.join(root, '.dart_tool', 'package_graph.json'),
        path.join(root, '.flutter-plugins-dependencies'),
      ],
    };
    for (final file in {...changes.keys, ...pubFiles}) {
      transaction.capture(file);
    }
    for (final entry in originals.entries) {
      transaction.capture(entry.key);
      if (!_sameAnalyzerBytes(transaction._before[entry.key], entry.value)) {
        throw StateError(
          'File changed during verification; preserving ${entry.key}.',
        );
      }
    }
    for (final entry in changes.entries) {
      transaction.write(entry.key, entry.value);
    }
    final flutter = path.join(
      path.dirname(
        path.dirname(path.dirname(path.dirname(Platform.resolvedExecutable))),
      ),
      Platform.isWindows ? 'flutter.bat' : 'flutter',
    );
    if (!File(flutter).existsSync())
      throw StateError(
        'Use this command through the Host Flutter/FVM SDK; matching flutter executable was not found.',
      );
    try {
      await _analyzerStage(
        runner,
        flutter,
        ['--no-color', 'pub', 'get'],
        host,
        'resolve Host dependencies (Pub Hook disabled)',
      );
    } finally {
      transaction.recordPubResult(pubFiles);
    }
    if (source != null) {
      final report = _AnalyzerBootstrapReport.inspect(host);
      if (report.state != _AnalyzerBootstrapState.healthy ||
          report.bootstrapRoot?.resolveSymbolicLinksSync() !=
              path.join(wrapper.path, 'tools', 'analyzer_plugin')) {
        throw StateError(
          'Host did not resolve the installed bootstrap: ${report.message}',
        );
      }
    }
    transaction.finish();
    transaction = null;
    if (source == null) {
      for (final relative in [
        'tools/analyzer_plugin/bin',
        'tools/analyzer_plugin',
        'tools',
        '',
      ]) {
        final folder = Directory(path.join(wrapper.path, relative));
        if (folder.existsSync() && folder.listSync(followLinks: false).isEmpty)
          folder.deleteSync();
      }
    }
    stdout.writeln(
      'Analyzer ${request.action.name} completed. Restart the Dart Analysis Server. '
      'Run analyzer status/doctor before relying on IDE diagnostics.',
    );
    try {
      if (source != null &&
          _analyzerPluginManagerCaches(
            Directory(path.join(wrapper.path, 'tools', 'analyzer_plugin')),
          ).any((entry) => !entry.current)) {
        stdout.writeln(
          'The previous IDE cache may be stale; doctor will identify the exact entry. No IDE cache was modified.',
        );
      }
    } on Object catch (error) {
      stderr.writeln(
        'warning: Installation completed; IDE cache inspection failed: $error',
      );
    }
    return true;
  } catch (_) {
    if (transaction != null) {
      transaction.rollback();
      stderr.writeln(
        'Restored CLI configuration and recorded Pub resolution files.',
      );
    }
    rethrow;
  } finally {
    if (staging?.existsSync() ?? false) staging!.deleteSync(recursive: true);
    if (locked) lock.unlockSync();
    lock.closeSync();
  }
}
