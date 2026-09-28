import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Describes one CCRouter-specific diagnostic before it is converted to the
/// Analysis Server protocol.
///
/// This value is intentionally source-oriented and has no dependency on a
/// Runtime, generated registry, or Flutter object. It is therefore suitable
/// for deterministic unit tests and for the isolated Analysis Server plugin.
final class CCRouterAnalyzerDiagnostic {
  /// Creates a diagnostic at [offset] with the supplied [length] and message.
  const CCRouterAnalyzerDiagnostic({
    required this.offset,
    required this.length,
    required this.code,
    required this.message,
    required this.correction,
    required this.severity,
  });

  /// UTF-16 source offset at which the diagnostic starts.
  final int offset;

  /// Number of UTF-16 code units covered by the diagnostic.
  final int length;

  /// Stable CCRouter diagnostic code.
  final String code;

  /// Message shown by the IDE.
  final String message;

  /// Suggested correction shown by the IDE.
  final String correction;

  /// Analysis Server severity.
  final AnalysisErrorSeverity severity;
}

/// Computes the small set of diagnostics that is safe to run on every edit.
///
/// The analyzer deliberately does not run `build_runner`, read arbitrary
/// workspace Packages, or infer dependency ownership from a partial editor
/// buffer. The CLI generator remains authoritative for complete metadata and
/// dependency validation.
abstract final class CCRouterAnalyzerDiagnostics {
  /// Analyzes one Dart [source] file and returns deterministic diagnostics.
  ///
  /// [filePath] must be an absolute or normalized path. [packageRoot] is the
  /// owning Package root when known; when omitted it is discovered by looking
  /// for the nearest `pubspec.yaml`. [packageName] can be supplied by the
  /// plugin after discovery to avoid reparsing the manifest.
  static List<CCRouterAnalyzerDiagnostic> analyze({
    required String source,
    required String filePath,
    String? packageRoot,
    String? packageName,
  }) {
    // Generated libraries are implementation artifacts. Their imports are
    // intentionally allowed to cross component boundaries and are validated
    // by the generator, not by the author-facing import rule.
    if (_isGeneratedFile(filePath)) {
      return const <CCRouterAnalyzerDiagnostic>[];
    }
    final root = packageRoot ?? _findPackageRoot(filePath);
    if (root == null) return const <CCRouterAnalyzerDiagnostic>[];
    final owner = packageName ?? _readPackageName(root);
    if (owner == null) return const <CCRouterAnalyzerDiagnostic>[];

    // Editors frequently send incomplete buffers. A parse error must not
    // terminate the Analysis Server plugin or replace Dart's own diagnostics.
    final parsed = parseString(
      content: source,
      path: filePath,
      throwIfDiagnostics: false,
    );
    final diagnostics = <CCRouterAnalyzerDiagnostic>[];
    for (final directive
        in parsed.unit.directives.whereType<NamespaceDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null || !_isGeneratedImport(uri, filePath, root, owner)) {
        continue;
      }
      diagnostics.add(
        CCRouterAnalyzerDiagnostic(
          offset: directive.uri.offset,
          length: directive.uri.length,
          code: 'ccrouter_cross_package_generated_import',
          message:
              'Cross-Package imports of src/ccrouter_generated are not a stable CCRouter API.',
          correction:
              'Import the owning Package public Contract or Host barrel instead.',
          severity: AnalysisErrorSeverity.ERROR,
        ),
      );
    }

    final sourceRelative = _relativeSourcePath(filePath, root);
    if (sourceRelative != null && sourceRelative.startsWith('lib/src/')) {
      final hasRouteAnnotation = parsed.unit.declarations
          .whereType<ClassDeclaration>()
          .any(_hasRouteAnnotation);
      if (hasRouteAnnotation) {
        final generated = File(
          path.join(root, _routeOutputPath(sourceRelative)),
        );
        if (!generated.existsSync()) {
          final annotation = _firstRouteAnnotation(parsed.unit);
          final offset = annotation?.offset ?? 0;
          final length = annotation?.length ?? 1;
          diagnostics.add(
            CCRouterAnalyzerDiagnostic(
              offset: offset,
              length: length,
              code: 'ccrouter_generated_output_missing',
              message:
                  'This CCRouter route has no generated route library yet.',
              correction:
                  'Run `ccrouter generate` (or the configured pub hook) before relying on the generated Route API.',
              severity: AnalysisErrorSeverity.WARNING,
            ),
          );
        }
      }
    }
    return diagnostics;
  }

  /// Whether [declaration] is a page carrying the CCRouter route annotation.
  static bool _hasRouteAnnotation(ClassDeclaration declaration) => declaration
      .metadata
      .any((annotation) => _annotationName(annotation) == 'CCRoute');

  /// Returns the first route annotation for a useful source highlight.
  static Annotation? _firstRouteAnnotation(CompilationUnit unit) {
    for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
      for (final annotation in declaration.metadata) {
        if (_annotationName(annotation) == 'CCRoute') return annotation;
      }
    }
    return null;
  }

  /// Reads an annotation's unqualified source name.
  static String? _annotationName(Annotation annotation) {
    final name = annotation.name;
    if (name is SimpleIdentifier) return name.name;
    final source = name.toSource();
    return source.substring(source.lastIndexOf('.') + 1);
  }

  /// Determines whether [uri] reaches another Package's generated internals.
  static bool _isGeneratedImport(
    String uri,
    String sourcePath,
    String packageRoot,
    String owner,
  ) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return false;
    if (parsed.scheme == 'package') {
      final segments = parsed.pathSegments;
      return segments.length >= 3 &&
          segments[1] == 'src' &&
          segments[2] == 'ccrouter_generated' &&
          segments.first != owner;
    }
    if (parsed.hasScheme) return false;
    final target = path.normalize(
      Uri.file(sourcePath).resolveUri(parsed).toFilePath(),
    );
    final ownGenerated = path.normalize(
      path.join(packageRoot, 'lib', 'src', 'ccrouter_generated'),
    );
    return path.isWithin(ownGenerated, target) == false &&
        target.contains(
          '${path.separator}lib${path.separator}src${path.separator}ccrouter_generated${path.separator}',
        );
  }

  /// Returns whether [filePath] itself is a generated CCRouter source file.
  static bool _isGeneratedFile(String filePath) => path
      .normalize(filePath)
      .contains(
        '${path.separator}lib${path.separator}src${path.separator}ccrouter_generated${path.separator}',
      );

  /// Converts a file path to the generator's slash-separated source path.
  static String? _relativeSourcePath(String filePath, String root) {
    final relative = path.relative(
      path.normalize(filePath),
      from: path.normalize(root),
    );
    return relative.replaceAll(path.separator, '/');
  }

  /// Derives the generated Route library path for one authored source file.
  static String _routeOutputPath(String sourcePath) {
    final relative = sourcePath.substring('lib/src/'.length);
    final stem = relative.substring(0, relative.length - '.dart'.length);
    return 'lib/src/ccrouter_generated/route/$stem.route.g.dart';
  }

  /// Finds the nearest Package root containing [filePath].
  static String? _findPackageRoot(String filePath) {
    var current = Directory(path.normalize(filePath)).parent;
    while (true) {
      if (File(path.join(current.path, 'pubspec.yaml')).existsSync()) {
        return current.path;
      }
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
  }

  /// Reads the Package name from its authored `pubspec.yaml`.
  static String? _readPackageName(String packageRoot) {
    final file = File(path.join(packageRoot, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    try {
      final yaml = loadYaml(file.readAsStringSync());
      final name = yaml is YamlMap ? yaml['name'] : null;
      return name is String && name.isNotEmpty ? name : null;
    } on Object {
      return null;
    }
  }
}
