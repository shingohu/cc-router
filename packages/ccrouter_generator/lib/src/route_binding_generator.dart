part of 'route_generator.dart';

/// Generates Flutter page construction separately from typed route contracts.
final class _RouteBindingGenerator extends Generator {
  /// Emits no library when the source owns neither routes nor implementations.
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return '';
    final routes = _readRouteModels(library);
    final implementations = _readRouteImplementationModels(library);
    if (routes.isEmpty && implementations.isEmpty) return '';
    final sourceUri = _sourcePackageUri(buildStep.inputId);
    final routeUri = _packageUri(
      buildStep.inputId.package,
      _routeLibraryOutputPath(buildStep.inputId.path),
    );
    final contractUris =
        <Uri>{
            for (final implementation in implementations)
              _generatedContractUri(implementation.contract.page),
          }.toList()
          ..sort((left, right) => left.toString().compareTo(right.toString()));
    final aliases = {
      for (final entry in contractUris.indexed)
        entry.$2: 'route_contract_${entry.$1}',
    };
    final out = StringBuffer()
      ..writeln("import 'package:ccrouter/ccrouter.dart';")
      ..writeln("import '$sourceUri' as route_page;");
    if (routes.any((route) => route.parameters.isNotEmpty)) {
      out.writeln("import '$routeUri' as route_contract;");
    }
    for (final entry in aliases.entries) {
      out.writeln("import '${entry.key}' as ${entry.value};");
    }
    out.writeln();
    for (final route in routes) {
      out
        ..writeln(
          _emitRouteBinding(
            route,
            pageType: 'route_page.${route.page.displayName}',
            definition: 'route_contract.${route.descriptorFunction}()',
          ),
        )
        ..writeln();
    }
    for (final implementation in implementations) {
      final contractUri = _generatedContractUri(implementation.contract.page);
      out
        ..writeln(
          _emitImplementationGlue(
            implementation,
            pageType: 'route_page.${implementation.page.displayName}',
            contractApi:
                '${aliases[contractUri]}.${implementation.contract.api}',
          ),
        )
        ..writeln();
    }
    return out.toString();
  }
}
