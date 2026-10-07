import 'dart:async';
import 'dart:io' as io;

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer_plugin/plugin/plugin.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/generator_diagnostics_bridge.dart';
import 'package:ccrouter_analyzer_plugin/src/package_context_cache.dart';
import 'package:ccrouter_analyzer_plugin/src/project_context.dart';
import 'package:ccrouter_analyzer_plugin/src/quick_fixes.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

/// Analysis Server plugin that publishes CCRouter-specific diagnostics.
final class CCRouterAnalyzerPlugin extends ServerPlugin {
  /// Creates a plugin backed by the Analysis Server [resourceProvider].
  CCRouterAnalyzerPlugin(ResourceProvider resourceProvider)
    : super(resourceProvider: resourceProvider);

  /// Bounded source-directory identities owned by this plugin isolate.
  final CCRouterPackageContextCache _packageContexts =
      CCRouterPackageContextCache();

  /// Cached role and Pub-owner contexts for explicitly indexed Packages.
  final CCRouterAnalyzerProjectContextCache _projectContexts =
      CCRouterAnalyzerProjectContextCache();

  /// Bounded Metadata snapshots shared across edits in one Pub graph.
  final CCRouterContractOwnerIndexCache _contractOwners =
      CCRouterContractOwnerIndexCache();

  /// Read-only structured Generator evidence and Pub-resolution hints.
  final CCRouterGeneratorDiagnosticsBridge _generatorDiagnostics =
      CCRouterGeneratorDiagnosticsBridge();

  /// Borrowed active contexts, released before the Server disposes them.
  /// Used only to route explicit non-import dependency refreshes.
  AnalysisContextCollection? _activeContexts;

  /// Polling fallback for `.dart_tool`, which Analysis Server does not
  /// consistently expose through plugin watch events.
  Timer? _watchBridgeTimer;

  /// Prevents overlapping polling cycles when analysis exceeds one interval.
  bool _watchBridgePollActive = false;

  /// Invalidates asynchronous polling work when contexts are replaced.
  int _watchBridgeLifecycleRevision = 0;

  /// Explicit Package manifests participating in each active Analysis context.
  final Map<String, List<String>> _pubspecPathsByContext = {};

  /// Last observed Workspace manifest identity for each Analysis context.
  final Map<String, String> _workspaceManifestIdentityByContext = {};

  /// Generated outputs tracked only for analyzed authored capability sources.
  final Map<String, Map<String, String>> _generatedOutputIdentityBySource = {};

  /// Watches Dart sources and the exact generated Contract ownership index.
  /// JSON is an invalidation input only; no JSON diagnostics are published.
  @override
  List<String> get fileGlobsToAnalyze => const <String>[
    '**/*.dart',
    '**/ccrouter_generated/metadata/ccrouter_package.json',
    '**/pubspec.yaml',
    '**/.metadata',
    '**/ccrouter.yaml',
    '**/.dart_tool/pub/workspace_ref.json',
  ];

  /// Human-readable plugin name shown by Analysis Server diagnostics.
  @override
  String get name => 'CCRouter Analysis Server Plugin';

  /// Analysis Server protocol version used by this plugin.
  @override
  String get version => '1.0.0';

  /// Accepts protocol versions supported by the plugin framework.
  @override
  bool isCompatibleWith(Version serverVersion) =>
      serverVersion <= Version(1, 0, 0);

  /// Performs initial analysis only for authored Dart sources.
  ///
  /// Analyzer's default plugin bootstrap enumerates every file below the
  /// context root, including platform build products and assets. CCRouter has
  /// no diagnostics for those files, while visiting them delays processing of
  /// live editor overlays. Generated Dart files are also skipped because their
  /// authored declarations and workspace generation remain authoritative.
  @override
  Future<void> afterNewContextCollection({
    required AnalysisContextCollection contextCollection,
  }) async {
    _activeContexts = contextCollection;
    for (final analysisContext in contextCollection.contexts) {
      final paths = analysisContext.contextRoot
          .analyzedFiles()
          .where(_isAuthoredDartPath)
          .toList(growable: false);
      await analyzeFiles(analysisContext: analysisContext, paths: paths);
      for (final pubspec in _refreshPubspecIndex(
        analysisContext,
        force: true,
      )) {
        await _publishPubResolutionHint(pubspec);
      }
    }
    _startWatchBridgePolling();
  }

  /// Releases borrowed contexts and package indexes when roots are replaced.
  @override
  Future<void> beforeContextCollectionDispose({
    required AnalysisContextCollection contextCollection,
  }) async {
    _stopWatchBridgePolling();
    _activeContexts = null;
    _packageContexts.clear();
    _projectContexts.clear();
    _contractOwners.clear();
    _generatorDiagnostics.clear();
    _pubspecPathsByContext.clear();
    _workspaceManifestIdentityByContext.clear();
    _generatedOutputIdentityBySource.clear();
    await super.beforeContextCollectionDispose(
      contextCollection: contextCollection,
    );
  }

  /// Starts one low-frequency poller for the current Analysis contexts.
  void _startWatchBridgePolling() {
    _stopWatchBridgePolling();
    if (!_generatorDiagnostics.enabled || _activeContexts == null) return;
    final revision = _watchBridgeLifecycleRevision;
    _watchBridgeTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_pollWatchBridge(revision));
    });
    unawaited(_pollWatchBridge(revision));
  }

  /// Re-analyzes only paths whose structured watch evidence changed.
  Future<void> _pollWatchBridge(int lifecycleRevision) async {
    if (_watchBridgePollActive ||
        lifecycleRevision != _watchBridgeLifecycleRevision) {
      return;
    }
    final contexts = _activeContexts;
    if (contexts == null) return;
    _watchBridgePollActive = true;
    try {
      final refresh = <String>{};
      refresh.addAll(_pollGeneratedOutputs());
      refresh.addAll(_contractOwners.pollChangedPaths());
      final resolutionChanged = <String>{};
      final pubspecsByResolutionRoot = <String, Set<String>>{};
      final resolutionRoots = <String, io.Directory>{};
      for (final context in contexts.contexts) {
        final reindexed = _refreshPubspecIndex(context);
        resolutionChanged.addAll(reindexed);
        for (final pubspec in reindexed) {
          _projectContexts.invalidate(pubspec);
        }
        final hostRoots = <String, io.Directory>{};
        final contextRoot = io.Directory(context.contextRoot.root.path);
        hostRoots[_canonicalDirectoryPath(contextRoot)] = contextRoot;
        for (final pubspec in _indexedPubspecs(context)) {
          final observation = _projectContexts.observe(pubspec);
          if (observation.inputChanged) resolutionChanged.add(pubspec);
          final project = observation.context;
          if (project == null) continue;
          if (project.role == CCRouterAnalyzerProjectRole.host) {
            final root = project.requestedRoot;
            hostRoots[_canonicalDirectoryPath(root)] = root;
          }
          final resolutionKey = _canonicalDirectoryPath(project.resolutionRoot);
          resolutionRoots[resolutionKey] = project.resolutionRoot;
          pubspecsByResolutionRoot
              .putIfAbsent(resolutionKey, () => <String>{})
              .add(pubspec);
        }
        for (final root in hostRoots.values) {
          refresh.addAll(_generatorDiagnostics.pollAffectedDartPaths(root));
        }
      }
      for (final entry in resolutionRoots.entries) {
        if (_generatorDiagnostics.pollResolutionGraphChanged(entry.value)) {
          resolutionChanged.addAll(
            pubspecsByResolutionRoot[entry.key] ?? const <String>{},
          );
        }
      }
      if (lifecycleRevision != _watchBridgeLifecycleRevision) {
        return;
      }
      for (final pubspec in resolutionChanged) {
        await _publishPubResolutionHint(pubspec);
      }
      if (refresh.isEmpty) return;
      for (final context in contexts.contexts) {
        if (lifecycleRevision != _watchBridgeLifecycleRevision) return;
        await analyzeFiles(
          analysisContext: context,
          paths: refresh
              .where(context.contextRoot.isAnalyzed)
              .toList(growable: false),
        );
      }
    } on Object {
      // The bridge is diagnostic-only and must not destabilize Analysis Server.
    } finally {
      _watchBridgePollActive = false;
    }
  }

  /// Cancels owned polling and invalidates any asynchronous continuation.
  void _stopWatchBridgePolling() {
    _watchBridgeLifecycleRevision++;
    _watchBridgeTimer?.cancel();
    _watchBridgeTimer = null;
  }

  /// Releases lifecycle-bound polling before the plugin process shuts down.
  @override
  Future<PluginShutdownResult> handlePluginShutdown(
    PluginShutdownParams parameters,
  ) async {
    _stopWatchBridgePolling();
    _generatorDiagnostics.clear();
    _projectContexts.clear();
    _pubspecPathsByContext.clear();
    _workspaceManifestIdentityByContext.clear();
    _generatedOutputIdentityBySource.clear();
    return super.handlePluginShutdown(parameters);
  }

  /// Releases polling if the Analysis Server channel closes unexpectedly.
  @override
  void onDone() {
    _stopWatchBridgePolling();
    _generatorDiagnostics.clear();
    _projectContexts.clear();
    _pubspecPathsByContext.clear();
    _workspaceManifestIdentityByContext.clear();
    _generatedOutputIdentityBySource.clear();
    super.onDone();
  }

  /// Preserves original changed paths before Analyzer narrows them to Dart
  /// import dependencies. Metadata and generated registration outputs are not
  /// imported by their authored declarations, but still change diagnostics.
  @override
  Future<void> contentChanged(List<String> paths) async {
    final refresh = <String>{};
    var resolutionInputChanged = false;
    for (final changedPath in paths) {
      _packageContexts.invalidate(changedPath);
      _projectContexts.invalidate(changedPath);
      refresh.addAll(_contractOwners.invalidate(changedPath));
      refresh.addAll(_generatorDiagnostics.affectedDartPaths(changedPath));
      final projectPubspec = _projectPubspecForInput(changedPath);
      if (projectPubspec != null) {
        await _publishPubResolutionHint(projectPubspec);
      }
      if (changedPath.endsWith(path.join('.dart_tool', 'package_graph.json')) ||
          changedPath.endsWith(
            path.join('.dart_tool', 'package_config.json'),
          ) ||
          changedPath.endsWith(
            path.join('.dart_tool', 'pub', 'workspace_ref.json'),
          )) {
        resolutionInputChanged = true;
      }
      final authored = CCRouterSourceAnalyzer.authoredPathForGenerated(
        changedPath,
      );
      if (authored != null) refresh.add(authored);
    }
    await super.contentChanged(paths);
    final contexts = _activeContexts;
    if (contexts == null) return;
    for (final context in contexts.contexts) {
      final contextPubspec = path.join(
        context.contextRoot.root.path,
        'pubspec.yaml',
      );
      if (paths.any((changed) => path.equals(changed, contextPubspec))) {
        for (final pubspec in _refreshPubspecIndex(context, force: true)) {
          await _publishPubResolutionHint(pubspec);
        }
      }
      if (resolutionInputChanged) {
        for (final pubspec in _indexedPubspecs(context)) {
          await _publishPubResolutionHint(pubspec);
        }
      }
      await analyzeFiles(
        analysisContext: context,
        paths: refresh
            .where(context.contextRoot.isAnalyzed)
            .toList(growable: false),
      );
    }
  }

  /// Publishes diagnostics for one changed source file.
  @override
  Future<void> analyzeFile({
    required AnalysisContext analysisContext,
    required String path,
  }) => _analyzeCurrentSource(path);

  /// Re-analyzes editor overlays after the base plugin applies their content.
  ///
  /// `contentChanged` reports dependency-graph affected files, but it does not
  /// guarantee that the directly edited path is returned. An explicit pass is
  /// therefore required so removing a component dependency is diagnosed
  /// before the buffer is saved or a Generator preflight runs.
  @override
  Future<AnalysisUpdateContentResult> handleAnalysisUpdateContent(
    AnalysisUpdateContentParams parameters,
  ) async {
    final result = await super.handleAnalysisUpdateContent(parameters);
    for (final manifestPath in parameters.files.keys.where(
      (candidate) => path.basename(candidate) == 'pubspec.yaml',
    )) {
      await _publishPubResolutionHint(manifestPath);
    }
    for (final path in parameters.files.keys.where(_isAuthoredDartPath)) {
      await _analyzeCurrentSource(path);
    }
    return result;
  }

  /// Reads and analyzes the latest physical or Analysis Server overlay source.
  Future<void> _analyzeCurrentSource(String path) async {
    if (!_isAuthoredDartPath(path)) return;
    final file = resourceProvider.getFile(path);
    if (!file.exists) {
      _generatedOutputIdentityBySource.remove(path);
      return;
    }
    // Analysis Server can forward files matching a broad context glob,
    // including binary assets in a Flutter Host. Such files are outside the
    // plugin's Dart-only contract and must not terminate the plugin isolate.
    late final String source;
    try {
      source = file.readAsStringSync();
    } on Object {
      return;
    }
    if (CCRouterSourceAnalyzer.isGeneratedPath(path)) {
      channel.sendNotification(
        AnalysisErrorsParams(path, const []).toNotification(),
      );
      return;
    }
    final packageContext = _packageContexts.resolve(path);
    if (packageContext == null) {
      channel.sendNotification(
        AnalysisErrorsParams(path, const []).toNotification(),
      );
      return;
    }
    final resolvedUnit = await _resolvedCurrentUnit(path, source);
    if (!_sourceStillCurrent(path, source)) return;
    final analysis = CCRouterSourceAnalyzer.analyzeWithLineInfo(
      source: source,
      filePath: path,
      packageRoot: packageContext.root,
      packageName: packageContext.name,
      contractOwners: _contractOwners.resolve(path),
      resolvedUnit: resolvedUnit,
    );
    _trackGeneratedOutputs(path, analysis.generatedOutputPaths);
    final diagnostics = <CCRouterAnalyzerDiagnostic>[
      ...analysis.diagnostics,
      for (final diagnostic in _generatorDiagnostics.diagnosticsFor(path))
        diagnostic.toAnalyzerDiagnostic(source, analysis.lineInfo),
    ];
    final errors = diagnostics
        .map(
          (diagnostic) => _protocolError(path, analysis.lineInfo, diagnostic),
        )
        .toList(growable: false);
    channel.sendNotification(
      AnalysisErrorsParams(path, errors).toNotification(),
    );
  }

  /// Whether [path] can contain developer-authored CCRouter declarations.
  static bool _isAuthoredDartPath(String path) =>
      path.endsWith('.dart') && !CCRouterSourceAnalyzer.isGeneratedPath(path);

  /// Uses the existing Analysis Server session only for rules needing types.
  /// Partial/unresolved input falls back to conservative syntax checks. No
  /// separate workspace scan/session or long-lived resolved AST cache is added.
  Future<CompilationUnit?> _resolvedCurrentUnit(
    String path,
    String source,
  ) async {
    if (!const [
      'CCService',
      'CCComponent',
      'CCInitTask',
      'CCEventSubscription',
      'CCRoute',
      'CCCommand',
      'CCEventContract',
    ].any(source.contains))
      return null;
    try {
      final result = await getResolvedUnitResult(path);
      // Errors elsewhere must not discard proven annotation/namespace identity.
      // Each semantic rule still requires the exact elements it consumes.
      if (result.content != source) return null;
      return result.unit;
    } on Object {
      return null;
    }
  }

  /// Drops stale asynchronous analysis/fixes rather than editing a newer buffer.
  bool _sourceStillCurrent(String path, String source) {
    try {
      return resourceProvider.getFile(path).readAsStringSync() == source;
    } on Object {
      return false;
    }
  }

  /// Captures only outputs proven by the latest authored source analysis.
  void _trackGeneratedOutputs(String sourcePath, Set<String> outputPaths) {
    if (outputPaths.isEmpty) {
      _generatedOutputIdentityBySource.remove(sourcePath);
      return;
    }
    _generatedOutputIdentityBySource[sourcePath] = {
      for (final outputPath in outputPaths)
        outputPath: _filesystemIdentity(io.File(outputPath)),
    };
  }

  /// Detects generated output changes even when Analysis Server drops events.
  Set<String> _pollGeneratedOutputs() {
    final refresh = <String>{};
    final removedSources = <String>[];
    for (final entry in _generatedOutputIdentityBySource.entries) {
      if (!io.File(entry.key).existsSync()) {
        removedSources.add(entry.key);
        continue;
      }
      var changed = false;
      for (final outputPath in entry.value.keys.toList(growable: false)) {
        final current = _filesystemIdentity(io.File(outputPath));
        if (current == entry.value[outputPath]) continue;
        entry.value[outputPath] = current;
        changed = true;
      }
      if (changed) refresh.add(entry.key);
    }
    for (final source in removedSources) {
      _generatedOutputIdentityBySource.remove(source);
    }
    return refresh;
  }

  /// Re-analyzes authored capability sources affected by generated changes.
  ///
  /// Generated registration libraries are intentionally not imported by their
  /// authored declarations, so the analyzer's normal dependency graph does
  /// not always include the source in [paths]. Deterministic mapping keeps a stale
  /// `ccrouter_generated_output_missing` warning from surviving a successful
  /// generation.
  @override
  Future<void> handleAffectedFiles({
    required AnalysisContext analysisContext,
    required List<String> paths,
  }) async {
    final analyzedPaths = <String>{};
    for (final changedPath in paths) {
      _packageContexts.invalidate(changedPath);
      analyzedPaths.addAll(
        _generatorDiagnostics
            .affectedDartPaths(changedPath)
            .where(analysisContext.contextRoot.isAnalyzed),
      );
      for (final componentSource in _contractOwners.invalidate(changedPath)) {
        if (analysisContext.contextRoot.isAnalyzed(componentSource)) {
          analyzedPaths.add(componentSource);
        }
      }
      if (analysisContext.contextRoot.isAnalyzed(changedPath)) {
        analyzedPaths.add(changedPath);
      }
      final authored = CCRouterSourceAnalyzer.authoredPathForGenerated(
        changedPath,
      );
      if (authored != null &&
          analysisContext.contextRoot.isAnalyzed(authored)) {
        analyzedPaths.add(authored);
      }
    }
    await analyzeFiles(
      analysisContext: analysisContext,
      paths: analyzedPaths.toList(growable: false),
    );
  }

  /// Publishes only the fact that saved and resolved dependency sets differ.
  Future<void> _publishPubResolutionHint(String pubspecPath) async {
    _publishProjectConfigurationDiagnostic(pubspecPath);
    final resource = resourceProvider.getFile(pubspecPath);
    if (!resource.exists) return;
    late final String source;
    try {
      source = resource.readAsStringSync();
    } on Object {
      return;
    }
    final hint = _generatorDiagnostics.pubResolutionHint(
      io.File(pubspecPath),
      contents: source,
    );
    if (hint == null) {
      channel.sendNotification(
        AnalysisErrorsParams(pubspecPath, const []).toNotification(),
      );
      return;
    }
    final lineInfo = LineInfo.fromContent(source);
    final start = lineInfo.getLocation(hint.offset);
    final end = lineInfo.getLocation(hint.offset + hint.length);
    channel.sendNotification(
      AnalysisErrorsParams(pubspecPath, [
        AnalysisError(
          AnalysisErrorSeverity.WARNING,
          AnalysisErrorType.LINT,
          Location(
            pubspecPath,
            hint.offset,
            hint.length,
            start.lineNumber,
            start.columnNumber,
            endLine: end.lineNumber,
            endColumn: end.columnNumber,
          ),
          hint.message,
          'ccrouter_pub_resolution_stale',
          correction: hint.correction,
        ),
      ]).toNotification(),
    );
  }

  /// Publishes or clears the authored `ccrouter.yaml` role diagnostic.
  void _publishProjectConfigurationDiagnostic(String pubspecPath) {
    final root = io.File(pubspecPath).parent;
    final configurationPath = path.join(root.path, 'ccrouter.yaml');
    final issue = CCRouterAnalyzerProjectContext.configurationIssue(
      pubspecPath,
    );
    if (issue == null) {
      channel.sendNotification(
        AnalysisErrorsParams(configurationPath, const []).toNotification(),
      );
      return;
    }
    var source = '';
    try {
      source = io.File(issue.path).readAsStringSync();
    } on Object {
      // The file-level diagnostic remains useful during an atomic replacement.
    }
    final lineInfo = LineInfo.fromContent(source);
    final end = lineInfo.getLocation(source.length);
    channel.sendNotification(
      AnalysisErrorsParams(issue.path, [
        AnalysisError(
          AnalysisErrorSeverity.ERROR,
          AnalysisErrorType.LINT,
          Location(
            issue.path,
            0,
            source.isEmpty ? 0 : source.length,
            1,
            1,
            endLine: end.lineNumber,
            endColumn: end.columnNumber,
          ),
          issue.message,
          'ccrouter_project_configuration_invalid',
          correction: issue.correction,
        ),
      ]).toNotification(),
    );
  }

  /// Maps Package role inputs back to the manifest receiving a stale-resolution
  /// hint. Workspace-owned graph files are handled separately for every active
  /// Analysis context because they can affect multiple member manifests.
  static String? _projectPubspecForInput(String changedPath) {
    final normalized = path.normalize(changedPath);
    final basename = path.basename(normalized);
    if (basename == 'pubspec.yaml') return normalized;
    if (basename == '.metadata' || basename == 'ccrouter.yaml') {
      return path.join(path.dirname(normalized), 'pubspec.yaml');
    }
    if (normalized.endsWith(
      path.join('.dart_tool', 'pub', 'workspace_ref.json'),
    )) {
      return path.join(
        path.dirname(path.dirname(path.dirname(normalized))),
        'pubspec.yaml',
      );
    }
    return null;
  }

  /// Rebuilds one context's explicit Workspace member manifest index on demand.
  ///
  /// The returned union lets callers publish newly added members and clear
  /// diagnostics associated with members that left the Workspace.
  Set<String> _refreshPubspecIndex(
    AnalysisContext analysisContext, {
    bool force = false,
  }) {
    final contextRoot = analysisContext.contextRoot.root.path;
    final key = path.normalize(io.Directory(contextRoot).absolute.path);
    final workspaceManifest = io.File(path.join(contextRoot, 'pubspec.yaml'));
    final identity = _filesystemIdentity(workspaceManifest);
    if (!force && _workspaceManifestIdentityByContext[key] == identity) {
      return const <String>{};
    }
    _workspaceManifestIdentityByContext[key] = identity;
    final previous = _pubspecPathsByContext[key] ?? const <String>[];
    final current =
        <String>[
              for (final root
                  in CCRouterAnalyzerProjectContext.analysisPackageRoots(
                    contextRoot,
                  ))
                path.normalize(path.join(root.path, 'pubspec.yaml')),
            ]
            .where(analysisContext.contextRoot.isAnalyzed)
            .toList(growable: false)
          ..sort();
    _pubspecPathsByContext[key] = List<String>.unmodifiable(current);
    return <String>{...previous, ...current};
  }

  /// Returns the already indexed Package manifests for one Analysis context.
  List<String> _indexedPubspecs(AnalysisContext analysisContext) {
    final key = path.normalize(
      io.Directory(analysisContext.contextRoot.root.path).absolute.path,
    );
    return _pubspecPathsByContext[key] ?? const <String>[];
  }

  /// Uses bounded filesystem metadata to detect Workspace manifest changes.
  static String _filesystemIdentity(io.File file) {
    try {
      final stat = file.statSync();
      return '${stat.type}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:'
          '${stat.changed.microsecondsSinceEpoch}';
    } on Object {
      return 'missing';
    }
  }

  /// Returns one stable directory key for deduplicating nested Host polling.
  static String _canonicalDirectoryPath(io.Directory directory) {
    try {
      return path.normalize(directory.resolveSymbolicLinksSync());
    } on io.FileSystemException {
      return path.normalize(directory.absolute.path);
    }
  }

  /// Refreshes diagnostics for generated capability files added, changed, or
  /// removed by `ccrouter generate` and `ccrouter clean`.
  @override
  Future<AnalysisHandleWatchEventsResult> handleAnalysisHandleWatchEvents(
    AnalysisHandleWatchEventsParams parameters,
  ) async {
    final changed = parameters.events
        .where(
          (event) =>
              event.type == WatchEventType.ADD ||
              event.type == WatchEventType.MODIFY ||
              event.type == WatchEventType.REMOVE,
        )
        .map((event) => event.path)
        .toList(growable: false);
    if (changed.isNotEmpty) await contentChanged(changed);
    return AnalysisHandleWatchEventsResult();
  }

  /// Offers bounded edits for conflicts and Metadata-proven owner dependencies.
  @override
  Future<EditGetFixesResult> handleEditGetFixes(
    EditGetFixesParams parameters,
  ) async {
    final file = resourceProvider.getFile(parameters.file);
    if (!file.exists) return EditGetFixesResult(const []);
    late final String source;
    try {
      source = file.readAsStringSync();
    } on Object {
      return EditGetFixesResult(const []);
    }
    final packageContext = _packageContexts.resolve(parameters.file);
    if (packageContext == null) return EditGetFixesResult(const []);
    final resolvedUnit = await _resolvedCurrentUnit(parameters.file, source);
    if (!_sourceStillCurrent(parameters.file, source))
      return EditGetFixesResult(const []);
    final analysis = CCRouterSourceAnalyzer.analyzeWithLineInfo(
      source: source,
      filePath: parameters.file,
      packageRoot: packageContext.root,
      packageName: packageContext.name,
      contractOwners: _contractOwners.resolve(parameters.file),
      resolvedUnit: resolvedUnit,
    );
    final requestLine = analysis.lineInfo
        .getLocation(parameters.offset)
        .lineNumber;
    final errorFixes = <AnalysisErrorFixes>[];
    for (final diagnostic in analysis.diagnostics) {
      if ((diagnostic.code != 'ccrouter_annotation_arguments_conflict' &&
              diagnostic.code != 'ccrouter_service_disposable_missing' &&
              diagnostic.code !=
                  'ccrouter_component_owner_dependency_missing') ||
          analysis.lineInfo.getLocation(diagnostic.offset).lineNumber !=
              requestLine) {
        continue;
      }
      final fixes = CCRouterQuickFixes.compute(
        source: source,
        filePath: parameters.file,
        offset: diagnostic.offset,
        diagnosticCode: diagnostic.code,
        contractOwners: _contractOwners.resolve(parameters.file),
        sourcePackage: packageContext.name,
        resolvedUnit: resolvedUnit,
      );
      if (fixes.isEmpty) continue;
      errorFixes.add(
        AnalysisErrorFixes(
          _protocolError(parameters.file, analysis.lineInfo, diagnostic),
          fixes: [
            for (final fix in fixes)
              PrioritizedSourceChange(
                50,
                SourceChange(
                  fix.message,
                  id: fix.id,
                  edits: [
                    SourceFileEdit(
                      parameters.file,
                      file.modificationStamp,
                      edits: [
                        SourceEdit(fix.offset, fix.length, fix.replacement),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return EditGetFixesResult(errorFixes);
  }

  /// Converts a source-oriented diagnostic to an Analysis Server location.
  static Location _location(
    String filePath,
    LineInfo lineInfo,
    CCRouterAnalyzerDiagnostic diagnostic,
  ) {
    final start = lineInfo.getLocation(diagnostic.offset);
    final end = lineInfo.getLocation(diagnostic.offset + diagnostic.length);
    return Location(
      filePath,
      diagnostic.offset,
      diagnostic.length,
      start.lineNumber,
      start.columnNumber,
      endLine: end.lineNumber,
      endColumn: end.columnNumber,
    );
  }

  /// Converts one source diagnostic to the error object shared by fixes.
  static AnalysisError _protocolError(
    String filePath,
    LineInfo lineInfo,
    CCRouterAnalyzerDiagnostic diagnostic,
  ) => AnalysisError(
    diagnostic.severity,
    AnalysisErrorType.LINT,
    _location(filePath, lineInfo, diagnostic),
    diagnostic.message,
    diagnostic.code,
    correction: diagnostic.correction,
  );
}
