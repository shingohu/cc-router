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
    final libraryRoots = {
      for (final package in resolved)
        package.name: path.join(package.root.absolute.path, 'lib'),
    };
    final generatedRoots = {
      for (final entry in libraryRoots.entries)
        entry.key: _nativeSourcePath(
          path.join(entry.value, 'src', 'ccrouter_generated'),
        ),
    };
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
        if (!content.contains('import') && !content.contains('export'))
          continue;
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
                  libraryRoots,
                  generatedRoots,
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

/// Resolves Package, relative and file URI identity against the same boundary.
/// Malformed source URIs remain Builder errors.
bool _isForeignGeneratedLibrary(
  String literal,
  String source,
  String owner,
  Map<String, String> libraryRoots,
  Map<String, String> generatedRoots,
) {
  try {
    final uri = Uri.tryParse(literal);
    if (uri == null || uri.hasFragment) return false;
    final String targetPath;
    if (uri.scheme == 'package') {
      final segments = uri.pathSegments;
      if (segments.length < 2) return false;
      final root = libraryRoots[segments.first];
      if (root == null) return false;
      targetPath = path.join(root, path.joinAll(segments.skip(1)));
    } else {
      if (uri.hasScheme && uri.scheme != 'file') return false;
      targetPath = path.fromUri(Uri.file(source).resolveUri(uri));
    }
    if (targetPath.contains('\u0000')) return false;
    final target = _nativeSourcePath(targetPath);
    for (final entry in generatedRoots.entries) {
      if (entry.key != owner && path.isWithin(entry.value, target)) return true;
    }
    return false;
  } on FormatException {
    return false;
  } on UnsupportedError {
    return false;
  }
}

/// Resolves existing aliases; absent editor/build inputs keep lexical identity.
String _nativeSourcePath(String value) {
  final file = File(value).absolute;
  try {
    return path.normalize(file.resolveSymbolicLinksSync());
  } on FileSystemException {
    return path.normalize(file.path);
  }
}
