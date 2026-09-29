import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer_plugin/plugin/plugin.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:ccrouter_analyzer_plugin/src/source_analyzer.dart';
import 'package:pub_semver/pub_semver.dart';

/// Analysis Server plugin that publishes CCRouter-specific diagnostics.
final class CCRouterAnalyzerPlugin extends ServerPlugin {
  /// Creates a plugin backed by the Analysis Server [resourceProvider].
  CCRouterAnalyzerPlugin(ResourceProvider resourceProvider)
    : super(resourceProvider: resourceProvider);

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

  /// Publishes diagnostics for one changed source file.
  @override
  Future<void> analyzeFile({
    required AnalysisContext analysisContext,
    required String path,
  }) async {
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
    final diagnostics = CCRouterSourceAnalyzer.analyze(
      source: source,
      filePath: path,
    );
    final lineInfo = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    ).lineInfo;
    final errors = diagnostics
        .map(
          (diagnostic) => AnalysisError(
            diagnostic.severity,
            AnalysisErrorType.LINT,
            _location(path, lineInfo, diagnostic),
            diagnostic.message,
            diagnostic.code,
            correction: diagnostic.correction,
          ),
        )
        .toList(growable: false);
    channel.sendNotification(
      AnalysisErrorsParams(path, errors).toNotification(),
    );
  }

  /// Re-analyzes authored Route sources affected by generated file changes.
  ///
  /// A generated Route library is intentionally not imported by its authored
  /// page, so the analyzer's normal dependency graph does not always include
  /// the page in [paths]. The deterministic source mapping keeps a stale
  /// `ccrouter_generated_output_missing` warning from surviving a successful
  /// generation.
  @override
  Future<void> handleAffectedFiles({
    required AnalysisContext analysisContext,
    required List<String> paths,
  }) async {
    final analyzedPaths = <String>{};
    for (final changedPath in paths) {
      if (analysisContext.contextRoot.isAnalyzed(changedPath)) {
        analyzedPaths.add(changedPath);
      }
      final authored = CCRouterSourceAnalyzer.authoredRoutePathForGenerated(
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

  /// Refreshes diagnostics for generated Route files added, changed, or
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
}
