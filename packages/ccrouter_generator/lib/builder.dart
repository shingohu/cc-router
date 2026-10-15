/// Build-runner integration for typed component route generation.
///
/// This is tooling API, not a business navigation API. Applications add the
/// package as a dev dependency and use the automatically applied builder.
library;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/route_generator.dart';
import 'src/command_generator.dart';
import 'src/event_generator.dart';
import 'src/init_task_generator.dart';
import 'src/service_generator.dart';
import 'src/ui_fragment_generator.dart';

/// Generates opt-in typed UI Clients and Renderer contributions.
Builder ccUIFragmentBuilder(BuilderOptions options) =>
    createUIFragmentBuilder(metadata: false);

/// Generates cache-only UI schemas and static assembly requirements.
Builder ccUIFragmentMetadataBuilder(BuilderOptions options) =>
    createUIFragmentBuilder(metadata: true);

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

/// Creates standalone typed Tokens for generated and owner-only Service SPI.
Builder ccServiceContractBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _serviceContractBuildExtensions);
  return LibraryBuilder(
    ccServiceContractGenerator(),
    generatedExtension: '.service.contract.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Creates package-internal Provider registration for simple Services.
Builder ccServiceBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _serviceBuildExtensions);
  return LibraryBuilder(
    ccServiceGenerator(),
    generatedExtension: '.service.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Creates component-specific typed Service Clients from explicit dependencies.
Builder ccServiceProxyBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _serviceProxyBuildExtensions);
  return LibraryBuilder(
    ccServiceProxyGenerator(),
    generatedExtension: '.service_api.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Creates package-internal Command Handler registration bridges.
Builder ccCommandBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _commandBuildExtensions);
  return LibraryBuilder(
    ccCommandGenerator(),
    generatedExtension: '.command.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Emits disposable Command metadata into the build cache.
Builder ccCommandMetadataBuilder(BuilderOptions options) =>
    ccCommandMetadataBuilderInternal();

/// Creates package-internal Event Subscriber registration bridges.
Builder ccEventBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _eventBuildExtensions);
  return LibraryBuilder(
    ccEventGenerator(),
    generatedExtension: '.event.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Emits disposable Event metadata into the build cache.
Builder ccEventMetadataBuilder(BuilderOptions options) =>
    ccEventMetadataBuilderInternal();

/// Creates package-internal initialization task registration bridges.
Builder ccInitTaskBuilder(BuilderOptions options) {
  final config = Map<String, dynamic>.from(options.config);
  config.putIfAbsent('build_extensions', () => _initTaskBuildExtensions);
  return LibraryBuilder(
    ccInitTaskGenerator(),
    generatedExtension: '.init_task.g.dart',
    options: BuilderOptions(config, isRoot: options.isRoot),
    header:
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// ignore_for_file: type=lint, unused_element',
  );
}

/// Emits disposable initialization task metadata into the build cache.
Builder ccInitTaskMetadataBuilder(BuilderOptions options) =>
    ccInitTaskMetadataBuilderInternal();

/// Emits disposable machine-readable component metadata into the build cache.
Builder ccComponentMetadataBuilder(BuilderOptions options) =>
    ccComponentMetadataBuilderInternal();

/// Emits disposable machine-readable route metadata into the build cache.
///
/// Workspace generation consumes the JSON for ownership and contract-exposure
/// validation, then publishes one Package Index and optional readable catalog.
Builder ccRouteMetadataBuilder(BuilderOptions options) =>
    ccRouteMetadataBuilderInternal();

/// Emits disposable Service metadata into the build cache.
Builder ccServiceMetadataBuilder(BuilderOptions options) =>
    ccServiceMetadataBuilderInternal();

/// Maps route source libraries under `lib/` to package-level metadata files.
const _routeBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': ['lib/src/ccrouter_generated/route/{{}}.route.g.dart'],
};

/// Maps route sources to isolated Flutter page-binding libraries.
const _routeBindingBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': [
    'lib/src/ccrouter_generated/binding/{{}}.route_binding.g.dart',
  ],
};

/// Maps route sources to standalone Pure Dart contract libraries.
const _routeContractBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': [
    'lib/src/ccrouter_generated/contract/{{}}.route.contract.g.dart',
  ],
};

/// Maps Service contract sources to standalone typed Token libraries.
const _serviceContractBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': [
    'lib/src/ccrouter_generated/contract/{{}}.service.contract.g.dart',
  ],
};

/// Maps Service implementations to package-internal registration libraries.
const _serviceBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': [
    'lib/src/ccrouter_generated/service/{{}}.service.g.dart',
  ],
};

/// Maps component declarations to package-internal typed Service Client APIs.
const _serviceProxyBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': [
    'lib/src/ccrouter_generated/component/{{}}.service_api.g.dart',
  ],
};

/// Maps Handler sources to package-internal registration libraries.
const _commandBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': [
    'lib/src/ccrouter_generated/command/{{}}.command.g.dart',
  ],
};

/// Maps Subscriber sources to package-internal registration libraries.
const _eventBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': ['lib/src/ccrouter_generated/event/{{}}.event.g.dart'],
};

/// Maps initialization Handler sources to internal registration libraries.
const _initTaskBuildExtensions = <String, List<String>>{
  r'^lib/src/{{}}.dart': [
    'lib/src/ccrouter_generated/init_task/{{}}.init_task.g.dart',
  ],
};
