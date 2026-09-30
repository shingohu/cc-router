import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer_plugin/plugin/plugin.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/package_context_cache.dart';
import 'package:ccrouter_analyzer_plugin/src/quick_fixes.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:pub_semver/pub_semver.dart';

/// Analysis Server plugin that publishes CCRouter-specific diagnostics.
final class CCRouterAnalyzerPlugin extends ServerPlugin {
  /// Creates a plugin backed by the Analysis Server [resourceProvider].
  CCRouterAnalyzerPlugin(ResourceProvider resourceProvider)
    : super(resourceProvider: resourceProvider);

  /// Bounded source-directory identities owned by this plugin isolate.
  final CCRouterPackageContextCache _packageContexts =
      CCRouterPackageContextCache();

  /// Bounded Metadata snapshots shared across edits in one Pub graph.
  final CCRouterContractOwnerIndexCache _contractOwners =
      CCRouterContractOwnerIndexCache();

  /// Limits analysis to Dart source files.
  @override
  List<String> get fileGlobsToAnalyze => const <String>['**/*.dart'];

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
    for (final analysisContext in contextCollection.contexts) {
      final paths = analysisContext.contextRoot
          .analyzedFiles()
          .where(_isAuthoredDartPath)
          .toList(growable: false);
      await analyzeFiles(analysisContext: analysisContext, paths: paths);
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
    for (final path in parameters.files.keys.where(_isAuthoredDartPath)) {
      await _analyzeCurrentSource(path);
    }
    return result;
  }

  /// Reads and analyzes the latest physical or Analysis Server overlay source.
  Future<void> _analyzeCurrentSource(String path) async {
    if (!_isAuthoredDartPath(path)) return;
    final file = resourceProvider.getFile(path);
    if (!file.exists) return;
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
    final analysis = CCRouterSourceAnalyzer.analyzeWithLineInfo(
      source: source,
      filePath: path,
      packageRoot: packageContext.root,
      packageName: packageContext.name,
      contractOwners: _contractOwners.resolve(path),
    );
    final errors = analysis.diagnostics
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
    final analysis = CCRouterSourceAnalyzer.analyzeWithLineInfo(
      source: source,
      filePath: parameters.file,
      packageRoot: packageContext.root,
      packageName: packageContext.name,
      contractOwners: _contractOwners.resolve(parameters.file),
    );
    final requestLine = analysis.lineInfo
        .getLocation(parameters.offset)
        .lineNumber;
    final errorFixes = <AnalysisErrorFixes>[];
    for (final diagnostic in analysis.diagnostics) {
      if ((diagnostic.code != 'ccrouter_annotation_arguments_conflict' &&
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
