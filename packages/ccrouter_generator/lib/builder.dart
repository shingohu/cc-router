/// Build-runner integration for typed component route generation.
///
/// This is tooling API, not a business navigation API. Applications add the
/// package as a dev dependency and use the automatically applied builder.
library;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/route_generator.dart';

/// Creates one library-local generated part without coupling to a backend.
///
/// Annotated libraries must declare `part '<path>.route.g.dart'`. Keeping
/// generated code in the same library preserves private page constructors
/// and component-only route contracts.
Builder ccRouteBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _routeBuildExtensions);
  return PartBuilder(
    [ccRouteGenerator()],
    '.route.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Emits machine-readable component metadata and component documentation.
Builder ccComponentMetadataBuilder(BuilderOptions options) =>
    ccComponentMetadataBuilderInternal();

/// Emits machine-readable route metadata and route documentation.
///
/// Workspace CI consumes JSON for cross-component visibility validation;
/// Markdown is intended for review rather than application runtime loading.
Builder ccRouteMetadataBuilder(BuilderOptions options) =>
    ccRouteMetadataBuilderInternal();

/// Maps route source libraries under `lib/` to package-level metadata files.
const _routeBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': ['lib/src/ccrouter_generated/{{}}.route.g.dart'],
};
