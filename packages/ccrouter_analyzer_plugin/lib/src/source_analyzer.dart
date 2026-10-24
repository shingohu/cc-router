import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:ccrouter_analyzer_plugin/src/component_dependency_analyzer.dart';
import 'package:ccrouter_analyzer_plugin/src/contract_owner_index.dart';
import 'package:ccrouter_analyzer_plugin/src/service_lifecycle_analysis.dart';
import 'resolved_symbols.dart';
import 'host_lifecycle_analysis.dart';
import 'ui_fragment_analysis.dart';
import 'project_context.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

part 'route_configuration_analysis.dart';

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

/// One parsed source result shared by diagnostics and protocol conversion.
final class CCRouterSourceAnalysis {
  /// Creates an immutable analysis result from one parser pass.
  const CCRouterSourceAnalysis({
    required this.diagnostics,
    required this.lineInfo,
    required this.generatedOutputPaths,
  });

  /// Deterministic CCRouter diagnostics for the source buffer.
  final List<CCRouterAnalyzerDiagnostic> diagnostics;

  /// Line mapping produced by the same parser pass as [diagnostics].
  final LineInfo lineInfo;

  /// Exact generated files whose filesystem identity can change diagnostics.
  final Set<String> generatedOutputPaths;
}

/// One source-preserving generated file required by an annotation.
final class _GeneratedOutputSpec {
  /// Creates an output mapping under one generated [directory].
  const _GeneratedOutputSpec({
    required this.capability,
    required this.directory,
    required this.suffix,
  });

  /// Human-readable capability name used in the diagnostic.
  final String capability;

  /// Directory below `lib/src/ccrouter_generated`.
  final String directory;

  /// Generated suffix replacing the authored `.dart` suffix.
  final String suffix;
}

/// Missing-output check anchored to one authored annotation.
final class _GeneratedOutputExpectation {
  /// Creates an expectation for all [outputPaths] emitted from one source.
  const _GeneratedOutputExpectation({
    required this.annotation,
    required this.capability,
    required this.outputPaths,
  });

  /// Annotation highlighted when one or more generated files are missing.
  final Annotation annotation;

  /// Human-readable capability category.
  final String capability;

  /// Package-relative files that must exist after successful generation.
  final List<String> outputPaths;
}

/// Direct outputs whose path is provable from one authored source file.
///
/// Command/Event/InitTask Contract declarations and component-wide API barrels
/// are deliberately absent: their outputs depend on cross-file Package
/// metadata and remain the responsibility of `ccrouter generate --check`.
const _generatedOutputSpecs = <String, List<_GeneratedOutputSpec>>{
  'CCRoute': [
    _GeneratedOutputSpec(
      capability: 'Route',
      directory: 'route',
      suffix: '.route.g.dart',
    ),
    _GeneratedOutputSpec(
      capability: 'Route',
      directory: 'binding',
      suffix: '.route_binding.g.dart',
    ),
  ],
  'CCRouteImplementation': [
    _GeneratedOutputSpec(
      capability: 'Route implementation',
      directory: 'binding',
      suffix: '.route_binding.g.dart',
    ),
  ],
  'CCRouteContract': [
    _GeneratedOutputSpec(
      capability: 'Route Contract',
      directory: 'contract',
      suffix: '.route.contract.g.dart',
    ),
  ],
  'CCService': [
    _GeneratedOutputSpec(
      capability: 'Service',
      directory: 'service',
      suffix: '.service.g.dart',
    ),
  ],
  'CCServiceContract': [
    _GeneratedOutputSpec(
      capability: 'Service Contract',
      directory: 'contract',
      suffix: '.service.contract.g.dart',
    ),
  ],
  'CCCommandHandler': [
    _GeneratedOutputSpec(
      capability: 'Command Handler',
      directory: 'command',
      suffix: '.command.g.dart',
    ),
  ],
  'CCEventSubscription': [
    _GeneratedOutputSpec(
      capability: 'Event Subscription',
      directory: 'event',
      suffix: '.event.g.dart',
    ),
  ],
  'CCInitTask': [
    _GeneratedOutputSpec(
      capability: 'InitTask',
      directory: 'init_task',
      suffix: '.init_task.g.dart',
    ),
  ],
};

/// Stable identity syntax shared by annotation-level diagnostics.
final _stableIdPattern = RegExp(r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$');

/// Public lower-camel identifier syntax used by generated Client aliases.
final _aliasPattern = RegExp(r'^[a-z][A-Za-z0-9]*$');

/// Dart keywords that cannot become generated Client members.
const _dartKeywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

/// Function annotations that require static top-level Handler declarations.
const _handlerAnnotations = <String>{
  'CCCommandHandler',
  'CCEventSubscription',
  'CCInitTask',
};

/// Annotations whose literal `id` follows the stable identity syntax.
const _idAnnotations = <String>{
  'CCRoute',
  'CCRouteContract',
  'CCService',
  'CCServiceContract',
  'CCCommandContract',
  'CCEventContract',
  'CCEventSubscription',
  'CCInitTask',
};

/// Contract annotations whose alias becomes a generated Dart member.
const _aliasAnnotations = <String>{'CCServiceContract', 'CCCommandContract'};

/// Named `Duration` units converted to microseconds for positivity checks.
const _durationFactors = <String, int>{
  'days': Duration.microsecondsPerDay,
  'hours': Duration.microsecondsPerHour,
  'minutes': Duration.microsecondsPerMinute,
  'seconds': Duration.microsecondsPerSecond,
  'milliseconds': Duration.microsecondsPerMillisecond,
  'microseconds': 1,
};

/// Computes the small set of diagnostics that is safe to run on every edit.
///
/// The analyzer deliberately does not run `build_runner`, read arbitrary
/// workspace Packages, or infer dependency ownership from a partial editor
/// buffer. The CLI generator remains authoritative for complete metadata and
/// dependency validation.
abstract final class CCRouterSourceAnalyzer {
  /// Analyzes one Dart [source] file and returns deterministic diagnostics.
  ///
  /// [filePath] must be an absolute or normalized path. [packageRoot] is the
  /// owning Package root when known; when omitted it is discovered by looking
  /// for the nearest `pubspec.yaml`. [packageName] can be supplied by the
  /// plugin after discovery to avoid reparsing the manifest. [contractOwners]
  /// enables Metadata-proven cross-component dependency checks; omitting it
  /// keeps standalone single-file analysis available without Pub state.
  /// [resolvedUnit] must represent exactly [source]; the plugin checks current
  /// overlay identity after resolution; each rule declines missing symbol proof.
  /// [projectRole] reuses cached Host/Package evidence when provided.
  static List<CCRouterAnalyzerDiagnostic> analyze({
    required String source,
    required String filePath,
    String? packageRoot,
    String? packageName,
    CCRouterContractOwnerIndex? contractOwners,
    CompilationUnit? resolvedUnit,
    CCRouterAnalyzerProjectRole? projectRole,
  }) => analyzeWithLineInfo(
    source: source,
    filePath: filePath,
    packageRoot: packageRoot,
    packageName: packageName,
    contractOwners: contractOwners,
    resolvedUnit: resolvedUnit,
    projectRole: projectRole,
  ).diagnostics;

  /// Analyzes one source and reuses its parser line mapping for IDE locations.
  /// [resolvedUnit] optionally supplies current type/constant identities. Missing
  /// semantic information suppresses lifecycle rules and uncertain type errors.
  /// [projectRole] may reuse the plugin's cached Package role.
  static CCRouterSourceAnalysis analyzeWithLineInfo({
    required String source,
    required String filePath,
    String? packageRoot,
    String? packageName,
    CCRouterContractOwnerIndex? contractOwners,
    CompilationUnit? resolvedUnit,
    CCRouterAnalyzerProjectRole? projectRole,
  }) {
    // Generated libraries are implementation artifacts. Their imports are
    // intentionally allowed to cross component boundaries and are validated
    // by the generator, not by the author-facing import rule.
    if (_isGeneratedFile(filePath)) {
      return CCRouterSourceAnalysis(
        diagnostics: const <CCRouterAnalyzerDiagnostic>[],
        lineInfo: LineInfo.fromContent(source),
        generatedOutputPaths: const <String>{},
      );
    }
    final root = packageRoot ?? _findPackageRoot(filePath);
    if (root == null) {
      return CCRouterSourceAnalysis(
        diagnostics: const <CCRouterAnalyzerDiagnostic>[],
        lineInfo: LineInfo.fromContent(source),
        generatedOutputPaths: const <String>{},
      );
    }
    final owner = packageName ?? _readPackageName(root);
    if (owner == null) {
      return CCRouterSourceAnalysis(
        diagnostics: const <CCRouterAnalyzerDiagnostic>[],
        lineInfo: LineInfo.fromContent(source),
        generatedOutputPaths: const <String>{},
      );
    }

    // Editors frequently send incomplete buffers. A parse error must not
    // terminate the Analysis Server plugin or replace Dart's own diagnostics.
    final parsed = parseString(
      content: source,
      path: filePath,
      throwIfDiagnostics: false,
    );
    final unit = resolvedUnit ?? parsed.unit;
    final diagnostics = <CCRouterAnalyzerDiagnostic>[];
    for (final directive
        in parsed.unit.directives.whereType<NamespaceDirective>()) {
      for (final reference in [
        directive.uri,
        ...directive.configurations.map((configuration) => configuration.uri),
      ]) {
        final uri = reference.stringValue;
        if (uri == null || !_isGeneratedImport(uri, filePath, root, owner)) {
          continue;
        }
        diagnostics.add(
          CCRouterAnalyzerDiagnostic(
            offset: reference.offset,
            length: reference.length,
            code: 'ccrouter_cross_package_generated_import',
            message:
                'Cross-Package imports of src/ccrouter_generated are not a stable CCRouter API.',
            correction:
                'Import the owning Package public Contract or Host barrel instead.',
            severity: AnalysisErrorSeverity.ERROR,
          ),
        );
      }
    }

    for (final location in CCRouterHostLifecycleAnalysis.violations(
      unit: unit,
      filePath: filePath,
      packageRoot: root,
      projectRole: projectRole,
    )) {
      diagnostics.add(
        CCRouterAnalyzerDiagnostic(
          offset: location.offset,
          length: location.length,
          code: 'ccrouter_host_lifecycle_access',
          message:
              'Only the application Host Composition Root may control the CCRouter Runtime lifecycle.',
          correction:
              'Keep CCRouterHost in Host composition code; request product actions through a Host-provided callback or Contract.',
          severity: AnalysisErrorSeverity.ERROR,
        ),
      );
    }

    final sourceRelative = _relativeSourcePath(filePath, root);
    final generatedOutputPaths = <String>{};
    if (sourceRelative != null && sourceRelative.startsWith('lib/src/')) {
      for (final expectation in _generatedOutputExpectations(
        unit,
        sourceRelative,
      )) {
        generatedOutputPaths.addAll(
          expectation.outputPaths.map((output) => path.join(root, output)),
        );
        final missing = expectation.outputPaths
            .where((output) => !File(path.join(root, output)).existsSync())
            .toList(growable: false);
        if (missing.isEmpty) continue;
        diagnostics.add(
          CCRouterAnalyzerDiagnostic(
            offset: expectation.annotation.offset,
            length: expectation.annotation.length,
            code: 'ccrouter_generated_output_missing',
            message:
                'This CCRouter ${expectation.capability} has missing generated output.',
            correction:
                'Run `ccrouter generate` (or the configured pub hook) to create ${missing.join(', ')}.',
            severity: AnalysisErrorSeverity.WARNING,
          ),
        );
      }
    }
    diagnostics.addAll(_singleFileRuleDiagnostics(unit));
    for (final issue in CCRouterUIFragmentAnalysis.issues(
      unit: unit,
      filePath: filePath,
      packageRoot: root,
      packageName: owner,
      projectRole: projectRole,
    )) {
      diagnostics.add(
        CCRouterAnalyzerDiagnostic(
          offset: issue.node.offset,
          length: issue.node.length,
          code: issue.code,
          message: issue.message,
          correction: issue.correction,
          severity: AnalysisErrorSeverity.ERROR,
        ),
      );
    }
    for (final (declaration, fixable)
        in CCRouterServiceLifecycleAnalysis.issues(unit)) {
      diagnostics.add(
        CCRouterAnalyzerDiagnostic(
          offset: declaration.name.offset,
          length: declaration.name.length,
          code: fixable
              ? 'ccrouter_service_disposable_missing'
              : 'ccrouter_service_owned_resource',
          message: fixable
              ? 'This Service has dispose() but does not implement CCDisposable; Scope will not call it.'
              : 'This Service creates a disposable resource but does not connect disposal to Scope.',
          correction: fixable
              ? 'Implement CCDisposable to connect the existing method to Scope cleanup.'
              : 'Review ownership and implement CCDisposable with complete cleanup; do not dispose borrowed resources.',
          severity: AnalysisErrorSeverity.WARNING,
        ),
      );
    }
    if (contractOwners != null) {
      for (final missing in CCRouterComponentDependencyAnalyzer.findMissing(
        unit: unit,
        sourcePath: filePath,
        sourcePackage: owner,
        owners: contractOwners,
      )) {
        final kind = switch (missing.contractKind) {
          CCRouterContractKind.service => 'Service',
          CCRouterContractKind.command => 'Command',
          CCRouterContractKind.uiFragment => 'UI Fragment',
        };
        final symbol = missing.owner.componentIdSymbol;
        diagnostics.add(
          CCRouterAnalyzerDiagnostic(
            offset: missing.offset,
            length: missing.length,
            code: 'ccrouter_component_owner_dependency_missing',
            message:
                '$kind Contract ${missing.contractSymbol} is owned by '
                'component "${missing.owner.componentId}", which is missing '
                'from CCComponent.dependencies.',
            correction: symbol == null
                ? 'Add the owner as a required component dependency; '
                      'optionalDependencies cannot satisfy this capability.'
                : 'Add $symbol to CCComponent.dependencies; '
                      'optionalDependencies cannot satisfy this capability.',
            severity: AnalysisErrorSeverity.ERROR,
          ),
        );
      }
    }
    for (final declaration
        in unit.declarations.whereType<FunctionDeclaration>()) {
      final annotation = declaration.metadata
          .where((item) => _annotationName(item) == 'CCInitTask')
          .firstOrNull;
      if (annotation == null) continue;
      final policy = _namedArgument(annotation, 'failurePolicy');
      if (policy == null || !policy.toSource().endsWith('.required')) continue;
      if (_namedArgument(annotation, 'contract') == null) {
        diagnostics.add(
          CCRouterAnalyzerDiagnostic(
            offset: annotation.offset,
            length: annotation.length,
            code: 'ccrouter_required_init_task_contract_missing',
            message: 'A required InitTask must use a stable Contract.',
            correction:
                'Declare a top-level CCInitTaskContract and pass it with contract:.',
            severity: AnalysisErrorSeverity.ERROR,
          ),
        );
      }
      final returnType = declaration.returnType?.toSource() ?? '';
      final resolvedType = declaration.returnType?.type;
      final isAsync = resolvedType != null
          ? resolvedType.isDartAsyncFuture || resolvedType.isDartAsyncFutureOr
          : returnType.startsWith('Future<') ||
                returnType.startsWith('FutureOr<');
      if (isAsync && _namedArgument(annotation, 'timeout') == null) {
        diagnostics.add(
          CCRouterAnalyzerDiagnostic(
            offset: annotation.offset,
            length: annotation.length,
            code: 'ccrouter_required_init_task_timeout_missing',
            message: 'An async required InitTask must have a timeout.',
            correction: 'Add a positive timeout: Duration(...).',
            severity: AnalysisErrorSeverity.ERROR,
          ),
        );
      }
    }
    return CCRouterSourceAnalysis(
      diagnostics: List.unmodifiable(diagnostics),
      lineInfo: parsed.lineInfo,
      generatedOutputPaths: Set.unmodifiable(generatedOutputPaths),
    );
  }

  /// Whether a path belongs to CCRouter's generated implementation tree.
  static bool isGeneratedPath(String filePath) => _isGeneratedFile(filePath);

  /// Returns the authored source corresponding to a source-preserving
  /// generated library path, or `null` for unrelated aggregate files.
  ///
  /// The Analysis Server can report a generated file change without marking
  /// the annotated source as affected because the source does not import its
  /// registration library directly. The plugin uses this deterministic
  /// mapping to refresh the source diagnostic after generation or cleanup.
  static String? authoredPathForGenerated(String filePath) {
    final normalized = path.normalize(filePath);
    for (final spec in _generatedOutputSpecs.values.expand((items) => items)) {
      final marker =
          '${path.separator}lib${path.separator}src${path.separator}'
          'ccrouter_generated${path.separator}${spec.directory}${path.separator}';
      final markerIndex = normalized.lastIndexOf(marker);
      if (markerIndex < 0 || !normalized.endsWith(spec.suffix)) continue;
      final relativeStart = markerIndex + marker.length;
      final relativeEnd = normalized.length - spec.suffix.length;
      if (relativeStart >= relativeEnd) return null;
      final packageRoot = normalized.substring(0, markerIndex);
      final relative = normalized.substring(relativeStart, relativeEnd);
      return path.join(packageRoot, 'lib', 'src', '$relative.dart');
    }
    return null;
  }

  /// Collects output requirements that a single parsed source can prove.
  static List<_GeneratedOutputExpectation> _generatedOutputExpectations(
    CompilationUnit unit,
    String sourcePath,
  ) {
    final annotations = <Annotation>[
      for (final declaration in unit.declarations.whereType<ClassDeclaration>())
        ...declaration.metadata,
      for (final declaration
          in unit.declarations.whereType<FunctionDeclaration>())
        ...declaration.metadata,
    ];
    final expectations = <String, _GeneratedOutputExpectation>{};
    for (final annotation in annotations) {
      final name = _annotationName(annotation);
      final specs = name == null ? null : _generatedOutputSpecs[name];
      if (specs == null) continue;
      final paths = [for (final spec in specs) _outputPath(sourcePath, spec)];
      expectations.putIfAbsent(
        name!,
        () => _GeneratedOutputExpectation(
          annotation: annotation,
          capability: specs.first.capability,
          outputPaths: paths,
        ),
      );
    }
    return expectations.values.toList(growable: false);
  }

  /// Derives one source-preserving generated output path.
  static String _outputPath(String sourcePath, _GeneratedOutputSpec spec) {
    final relative = sourcePath.substring('lib/src/'.length);
    final stem = relative.substring(0, relative.length - '.dart'.length);
    return 'lib/src/ccrouter_generated/${spec.directory}/$stem${spec.suffix}';
  }

  /// Applies only rules that do not require resolved types or another file.
  static List<CCRouterAnalyzerDiagnostic> _singleFileRuleDiagnostics(
    CompilationUnit unit,
  ) {
    final diagnostics = <CCRouterAnalyzerDiagnostic>[];
    for (final declaration
        in unit.declarations.whereType<FunctionDeclaration>()) {
      for (final annotation in declaration.metadata) {
        final name = _annotationName(annotation);
        if (!_handlerAnnotations.contains(name)) continue;
        if (declaration.name.lexeme.startsWith('_') ||
            declaration.functionExpression.typeParameters != null) {
          diagnostics.add(
            _ruleDiagnostic(
              annotation,
              code: 'ccrouter_handler_declaration_invalid',
              message:
                  '$name requires a public, top-level, non-generic function.',
              correction:
                  'Move the Handler to a public top-level function and remove its type parameters.',
            ),
          );
        }
        diagnostics.addAll(
          _handlerSignatureDiagnostics(declaration, annotation, name!),
        );
      }
    }
    for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
      for (final member in declaration.members.whereType<MethodDeclaration>()) {
        for (final annotation in member.metadata) {
          final name = _annotationName(annotation);
          if (!_handlerAnnotations.contains(name)) continue;
          diagnostics.add(
            _ruleDiagnostic(
              annotation,
              code: 'ccrouter_handler_declaration_invalid',
              message: '$name cannot annotate an instance or static method.',
              correction:
                  'Move the Handler to a public, top-level, non-generic function.',
            ),
          );
        }
      }
    }
    for (final annotation in _allAnnotations(unit)) {
      final name = _annotationName(annotation);
      if (name == null) continue;
      diagnostics.addAll(_argumentRuleDiagnostics(annotation, name));
    }
    return diagnostics;
  }

  /// Validates obvious Handler arity and return-shape violations.
  static List<CCRouterAnalyzerDiagnostic> _handlerSignatureDiagnostics(
    FunctionDeclaration declaration,
    Annotation annotation,
    String annotationName,
  ) {
    final parameters = declaration.functionExpression.parameters?.parameters;
    if (parameters == null) return const [];
    final count = parameters.length;
    final arityValid = switch (annotationName) {
      'CCCommandHandler' || 'CCEventSubscription' => count == 1 || count == 2,
      'CCInitTask' =>
        count <= 1 && parameters.every((item) => !item.isOptional),
      _ => true,
    };
    final diagnostics = <CCRouterAnalyzerDiagnostic>[];
    if (!arityValid) {
      diagnostics.add(
        _ruleDiagnostic(
          annotation,
          code: 'ccrouter_handler_signature_invalid',
          message: '$annotationName has an unsupported parameter count.',
          correction: switch (annotationName) {
            'CCInitTask' =>
              'Use no parameter or one required CCInvocationContext parameter.',
            _ =>
              'Use one capability parameter and an optional second CCInvocationContext parameter.',
          },
        ),
      );
    }
    if (annotationName == 'CCInitTask' ||
        annotationName == 'CCEventSubscription') {
      final returnType = declaration.returnType;
      if (returnType != null && _isVoidLikeReturnType(returnType) == false) {
        diagnostics.add(
          _ruleDiagnostic(
            annotation,
            code: 'ccrouter_handler_signature_invalid',
            message:
                '$annotationName must return void, Future<void>, or FutureOr<void>.',
            correction:
                'Change the Handler return type to a supported void form.',
          ),
        );
      }
    }
    return diagnostics;
  }

  /// Validates mutually exclusive fields and safe literal values.
  static List<CCRouterAnalyzerDiagnostic> _argumentRuleDiagnostics(
    Annotation annotation,
    String annotationName,
  ) {
    final diagnostics = <CCRouterAnalyzerDiagnostic>[];
    if (annotationName == 'CCRoute' || annotationName == 'CCRouteContract') {
      diagnostics.addAll(_RouteConfigurationAnalysis.diagnostics(annotation));
    }
    if ((annotationName == 'CCRoute' || annotationName == 'CCRouteContract') &&
        _namedArgument(annotation, 'pattern') != null &&
        _namedArgument(annotation, 'patterns') != null) {
      diagnostics.add(
        _ruleDiagnostic(
          annotation,
          code: 'ccrouter_annotation_arguments_conflict',
          message: '$annotationName cannot set both pattern and patterns.',
          correction:
              'Keep pattern for one address, or keep patterns for multiple addresses.',
        ),
      );
    }
    if (annotationName == 'CCInitTask' && _hasCompleteArguments(annotation)) {
      final contract = _nonNullNamedArgument(annotation, 'contract');
      final id = _nonNullNamedArgument(annotation, 'id');
      if (contract == id) {
        diagnostics.add(
          _ruleDiagnostic(
            annotation,
            code: 'ccrouter_annotation_arguments_conflict',
            message: 'CCInitTask must set exactly one of contract and id.',
            correction:
                'Keep contract for a shared task, or id for a component-internal task.',
          ),
        );
      }
    }
    if (_idAnnotations.contains(annotationName)) {
      final id = _literalString(_namedArgument(annotation, 'id'));
      if (id != null && (id.length > 128 || !_stableIdPattern.hasMatch(id))) {
        diagnostics.add(
          _ruleDiagnostic(
            annotation,
            code: 'ccrouter_identifier_invalid',
            message: '$annotationName id "$id" is not a stable identifier.',
            correction:
                'Use a lowercase-leading ID with alphanumeric segments separated by ., _, or -.',
          ),
        );
      }
    }
    if (_aliasAnnotations.contains(annotationName)) {
      final alias = _literalString(_namedArgument(annotation, 'alias'));
      if (alias != null &&
          (!_aliasPattern.hasMatch(alias) || _dartKeywords.contains(alias))) {
        diagnostics.add(
          _ruleDiagnostic(
            annotation,
            code: 'ccrouter_alias_invalid',
            message:
                '$annotationName alias "$alias" is not a public lower-camel Dart identifier.',
            correction: 'Choose a non-keyword lower-camel Client member name.',
          ),
        );
      }
    }
    if (annotationName == 'CCInitTask') {
      final gate = _namedArgument(annotation, 'gate');
      final gateId = _constructorString(gate, 'CCInitTaskGate');
      if (gateId != null &&
          (gateId.length > 128 || !_stableIdPattern.hasMatch(gateId))) {
        diagnostics.add(
          _ruleDiagnostic(
            annotation,
            code: 'ccrouter_identifier_invalid',
            message: 'CCInitTask gate "$gateId" is not a stable identifier.',
            correction:
                'Use a lowercase-leading Gate ID with stable alphanumeric segments.',
          ),
        );
      }
      final timeout = _namedArgument(annotation, 'timeout');
      final timeoutMicros = _durationMicroseconds(timeout);
      if (timeoutMicros != null && timeoutMicros <= 0) {
        diagnostics.add(
          _ruleDiagnostic(
            annotation,
            code: 'ccrouter_timeout_invalid',
            message: 'CCInitTask timeout must be positive.',
            correction: 'Use a Duration greater than zero or omit timeout.',
          ),
        );
      }
    }
    return diagnostics;
  }

  /// Returns every annotation from supported top-level and member declarations.
  static Iterable<Annotation> _allAnnotations(CompilationUnit unit) sync* {
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration) {
        yield* declaration.metadata;
        for (final member in declaration.members) {
          yield* member.metadata;
        }
      } else if (declaration is FunctionDeclaration) {
        yield* declaration.metadata;
      } else if (declaration is TopLevelVariableDeclaration) {
        yield* declaration.metadata;
      }
    }
  }

  /// Whether an annotation's argument list is complete enough for absence checks.
  static bool _hasCompleteArguments(Annotation annotation) {
    final arguments = annotation.arguments;
    return arguments != null && !arguments.rightParenthesis.isSynthetic;
  }

  /// Whether one named argument is present and not the literal `null`.
  static bool _nonNullNamedArgument(Annotation annotation, String name) {
    final expression = _namedArgument(annotation, name);
    return expression != null && expression is! NullLiteral;
  }

  /// Reads a string only when the editor buffer contains a literal value.
  static String? _literalString(Expression? expression) =>
      expression is SimpleStringLiteral ? expression.value : null;

  /// Reads the first string argument of a named constructor type.
  static String? _constructorString(Expression? expression, String typeName) {
    final arguments = _constructorArguments(expression, typeName);
    if (arguments == null) return null;
    return arguments.isEmpty ? null : _literalString(arguments.first);
  }

  /// Evaluates literal `Duration` expressions without executing user code.
  static int? _durationMicroseconds(Expression? expression) {
    if (expression == null) return null;
    if (expression is PrefixedIdentifier &&
        expression.prefix.name == 'Duration' &&
        expression.identifier.name == 'zero') {
      return 0;
    }
    final arguments = _constructorArguments(expression, 'Duration');
    if (arguments == null) return null;
    var total = 0;
    for (final argument in arguments) {
      if (argument is! NamedExpression) return null;
      final value = _integerLiteral(argument.expression);
      final factor = _durationFactors[argument.name.label.name];
      if (value == null || factor == null) return null;
      total += value * factor;
    }
    return total;
  }

  /// Reads arguments from an unresolved constructor-shaped invocation.
  ///
  /// A partial editor parse may represent `Type(...)` as a method invocation
  /// until element resolution completes, so both AST shapes are accepted.
  static List<Expression>? _constructorArguments(
    Expression? expression,
    String typeName,
  ) {
    if (expression is InstanceCreationExpression &&
        expression.constructorName.type.name.lexeme == typeName) {
      return expression.argumentList.arguments.toList(growable: false);
    }
    if (expression is MethodInvocation &&
        expression.target == null &&
        expression.methodName.name == typeName) {
      return expression.argumentList.arguments.toList(growable: false);
    }
    return null;
  }

  /// Reads a signed integer literal without evaluating arbitrary expressions.
  static int? _integerLiteral(Expression expression) {
    if (expression is IntegerLiteral) return expression.value;
    if (expression is PrefixExpression &&
        expression.operator.lexeme == '-' &&
        expression.operand is IntegerLiteral) {
      final value = (expression.operand as IntegerLiteral).value;
      return value == null ? null : -value;
    }
    return null;
  }

  /// Resolves aliases and prefixes when available; unknown syntax is not an error.
  static bool? _isVoidLikeReturnType(TypeAnnotation annotation) {
    final type = annotation.type;
    if (type is VoidType) return true;
    if (type is InterfaceType) {
      return (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
          type.typeArguments.single is VoidType;
    }
    if (type != null && type is! InvalidType && type is! DynamicType)
      return false;
    // Without element resolution only reject unambiguous built-in primitives.
    // Imported aliases and shadowed names are left to resolved analysis/generation.
    if (annotation is! NamedType || annotation.importPrefix != null)
      return null;
    final name = annotation.name.lexeme;
    if (name == 'void') return true;
    final unit = annotation.root as CompilationUnit;
    if (type is DynamicType && unit.declaredFragment != null) return false;
    final shadowed = unit.declarations.any(
      (declaration) => switch (declaration) {
        ClassDeclaration d => d.name.lexeme == name,
        GenericTypeAlias d => d.name.lexeme == name,
        _ => false,
      },
    );
    if (shadowed) return null;
    if (unit.directives.whereType<ImportDirective>().any(
      (directive) => !(directive.uri.stringValue?.startsWith('dart:') ?? false),
    ))
      return null;
    return const {
          'int',
          'double',
          'num',
          'String',
          'bool',
          'Never',
        }.contains(name)
        ? false
        : null;
  }

  /// Creates a source-anchored error for one deterministic annotation rule.
  static CCRouterAnalyzerDiagnostic _ruleDiagnostic(
    Annotation annotation, {
    required String code,
    required String message,
    required String correction,
  }) => CCRouterAnalyzerDiagnostic(
    offset: annotation.offset,
    length: annotation.length,
    code: code,
    message: message,
    correction: correction,
    severity: AnalysisErrorSeverity.ERROR,
  );

  /// Shares exact framework identity with generated-output and fix rules.
  static String? _annotationName(Annotation annotation) =>
      CCRouterResolvedSymbols.annotationName(annotation);

  /// Returns one named annotation argument without resolving workspace state.
  static Expression? _namedArgument(Annotation annotation, String name) {
    for (final argument
        in annotation.arguments?.arguments.whereType<NamedExpression>() ??
            const <NamedExpression>[]) {
      if (argument.name.label.name == name) return argument.expression;
    }
    return null;
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
