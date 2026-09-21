import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:ccrouter_generator/src/package_workspace.dart';
import 'package:path/path.dart' as path;

/// Rejects handwritten cross-Package references to CCRouter generated internals.
///
/// Generated Host and binding libraries are excluded because they deliberately
/// connect Package bundles. This check applies to the resolved Host dependency
/// closure, not unrelated workspace Packages or read-only Pub dependencies.
final class CCGeneratedInternalApiBoundaryValidator {
  /// Reports forbidden imports and exports in writable Package production code.
  static List<String> validate(Iterable<CCResolvedPackage> packages) {
    final resolved = packages.toList(growable: false);
    final errors = <String>[];
    for (final package in resolved.where((entry) => entry.writable)) {
      final sourceRoot = Directory(path.join(package.root.path, 'lib'));
      if (!sourceRoot.existsSync()) continue;
      final generatedRoot = path.normalize(
        path.join(sourceRoot.path, 'src', 'ccrouter_generated'),
      );
      for (final entity in sourceRoot.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = path.normalize(entity.absolute.path);
        if (path.isWithin(generatedRoot, source)) continue;
        final content = entity.readAsStringSync();
        if (!content.contains('ccrouter_generated')) continue;
        final parsed = parseString(
          content: content,
          path: source,
          featureSet: FeatureSet.latestLanguageVersion(),
        );
        for (final directive
            in parsed.unit.directives.whereType<NamespaceDirective>()) {
          final references = [
            directive.uri,
            for (final configuration in directive.configurations)
              configuration.uri,
          ];
          for (final reference in references) {
            final literal = reference.stringValue;
            if (literal == null ||
                !_isForeignGeneratedLibrary(
                  literal,
                  source,
                  package.name,
                  resolved,
                )) {
              continue;
            }
            final line = parsed.lineInfo
                .getLocation(reference.offset)
                .lineNumber;
            errors.add(
              '${package.name}:${path.relative(source, from: package.root.path)}:$line '
              'must not import or export another Package\'s '
              'src/ccrouter_generated library ($literal). Use its public '
              'Contract or Host barrel instead.',
            );
          }
        }
      }
    }
    return errors..sort();
  }
}

/// Resolves a directive URI without treating comments or string literals as imports.
bool _isForeignGeneratedLibrary(
  String literal,
  String source,
  String owner,
  List<CCResolvedPackage> packages,
) {
  final uri = Uri.tryParse(literal);
  if (uri == null) return false;
  if (uri.scheme == 'package') {
    final segments = uri.pathSegments;
    return segments.length > 3 &&
        segments.first != owner &&
        segments[1] == 'src' &&
        segments[2] == 'ccrouter_generated';
  }
  if (uri.hasScheme) return false;
  final target = path.normalize(Uri.file(source).resolveUri(uri).toFilePath());
  for (final package in packages) {
    if (package.name == owner) continue;
    final generatedRoot = path.normalize(
      path.join(package.root.absolute.path, 'lib', 'src', 'ccrouter_generated'),
    );
    if (path.isWithin(generatedRoot, target)) return true;
  }
  return false;
}
