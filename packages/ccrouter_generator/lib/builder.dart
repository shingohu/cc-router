/// Build-runner integration for typed component route generation.
///
/// This is tooling API, not a business navigation API. Applications add the
/// package as a dev dependency and use the automatically applied builder.
library;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/route_generator.dart';

/// Creates one standalone generated route library without backend coupling.
///
/// Annotated pages do not import or declare generated files. The builder emits
/// package-internal registration glue and a typed callable factory consumed by
/// the component's unique generated Route API.
Builder ccRouteBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _routeBuildExtensions);
  return LibraryBuilder(
    ccRouteGenerator(),
    generatedExtension: '.route.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Creates page-binding libraries kept separate from typed route contracts.
///
/// Bindings import Flutter pages and are consumed only by generated component
/// catalogs. Keeping them out of the typed Route API prevents import cycles
/// when an annotated page navigates through its component API.
Builder ccRouteBindingBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _routeBindingBuildExtensions);
  return LibraryBuilder(
    ccRouteBindingGenerator(),
    generatedExtension: '.route_binding.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Creates standalone Pure Dart libraries for public contract schemas.
///
/// Component packages add `ccrouter_contracts` as a direct dependency and
/// export these generated libraries through their explicit contract barrel.
/// Only `CCRouteContract` schemas emit content; page-level `CCRoute`
/// declarations use the separate package-internal route-library builder.
Builder ccRouteContractBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _routeContractBuildExtensions);
  return LibraryBuilder(
    ccRouteContractGenerator(),
    generatedExtension: '.route.contract.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Creates a same-library Part containing generated component Manifests.
///
/// Annotated Registrar libraries declare a `.component.g.dart` Part so the
/// generated Manifest can instantiate a private const Registrar while keeping
/// that implementation outside package and business APIs.
Builder ccComponentBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _componentBuildExtensions);
  return PartBuilder(
    [ccComponentGenerator()],
    '.component.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Emits disposable machine-readable component metadata into the build cache.
Builder ccComponentMetadataBuilder(BuilderOptions options) =>
    ccComponentMetadataBuilderInternal();

/// Emits disposable machine-readable route metadata into the build cache.
///
/// Workspace generation consumes the JSON for ownership and contract-exposure
/// validation, then publishes one Package Index and optional readable catalog.
Builder ccRouteMetadataBuilder(BuilderOptions options) =>
    ccRouteMetadataBuilderInternal();

/// Maps route source libraries under `lib/` to package-level metadata files.
const _routeBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': ['lib/src/ccrouter_generated/{{}}.route.g.dart'],
};

/// Maps route sources to isolated Flutter page-binding libraries.
const _routeBindingBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': [
    'lib/src/ccrouter_generated/{{}}.route_binding.g.dart',
  ],
};

/// Maps route sources to standalone Pure Dart contract libraries.
const _routeContractBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': [
    'lib/src/ccrouter_generated/{{}}.route.contract.g.dart',
  ],
};

/// Maps component Registrar libraries to same-library Manifest Parts.
const _componentBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': ['lib/src/ccrouter_generated/{{}}.component.g.dart'],
};
