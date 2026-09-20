part of 'route_generator.dart';

/// Emits structured route metadata for documentation and CI.
final class _RouteMetadataBuilder implements Builder {
  /// Creates the route metadata builder with package-level output paths.
  _RouteMetadataBuilder()
    : buildExtensions = const {
        r'^lib/{{}}.dart': ['ccrouter_generated/{{}}.route.json'],
      };

  /// Writes route metadata while preserving the source-relative path.
  @override
  final Map<String, List<String>> buildExtensions;

  /// Emits no files for libraries without route declarations.
  @override
  Future<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.path.contains('/ccrouter_generated/')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final library = LibraryReader(
      await buildStep.resolver.libraryFor(buildStep.inputId),
    );
    final routes = <_RouteModel>[];
    for (final annotated in library.annotatedWith(_RouteGenerator._route)) {
      routes.add(_RouteModel.read(annotated.element, annotated.annotation));
    }
    for (final annotated in library.annotatedWith(
      _RouteContractGenerator._contract,
    )) {
      routes.add(
        _RouteModel.read(
          annotated.element,
          annotated.annotation,
          contractFirst: true,
        ),
      );
    }
    final implementations = _readRouteImplementationModels(library);
    if (routes.isEmpty && implementations.isEmpty) return;
    final payload = _metadataPayload(
      package: buildStep.inputId.package,
      source: buildStep.inputId.path,
      components: [
        ...routes.map((route) => route.component),
        ...implementations.map(
          (implementation) => implementation.contract.component,
        ),
      ],
      routes: routes,
      routeImplementations: implementations,
      componentDeclarations: const [],
    );
    final jsonOutput = buildStep.allowedOutputs.singleWhere(
      (output) => output.path.endsWith('.route.json'),
    );
    await buildStep.writeAsString(
      jsonOutput,
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }
}

/// Creates a stable metadata schema without exposing analyzer objects.
Map<String, Object?> _metadataPayload({
  required String package,
  required String source,
  required List<_ComponentModel> components,
  required List<_RouteModel> routes,
  List<_RouteImplementationModel> routeImplementations = const [],
  List<String>? componentDeclarations,
  Map<String, String> componentManifests = const {},
}) => {
  'schemaVersion': 3,
  'package': package,
  'source': source,
  'componentDeclarations':
      componentDeclarations ??
      components.map((component) => component.id).toList(),
  'componentManifests': componentManifests,
  'components': {
    for (final component in [
      ...components,
      ...routes.map((route) => route.component),
    ])
      component.id: _componentJson(component),
  }.values.toList(),
  'routes': routes
      .map((route) => _routeJson(route, package: package, source: source))
      .toList(),
  'routeImplementations': routeImplementations
      .map(
        (implementation) => _routeImplementationJson(
          implementation,
          package: package,
          source: source,
        ),
      )
      .toList(),
};

/// Serializes one component descriptor deterministically.
Map<String, Object?> _componentJson(_ComponentModel component) => {
  'id': component.id,
  'version': component.version,
  'dependencies': component.dependencies,
  'optionalDependencies': component.optionalDependencies,
};

/// Serializes ownership, derived exposure, addresses and documented parameters.
Map<String, Object?> _routeJson(
  _RouteModel route, {
  required String package,
  required String source,
}) => {
  'id': route.id,
  'componentId': route.component.id,
  'componentVersion': route.component.version,
  'exposure': route.exposure,
  'deepLink': _enumValue(
    route.annotation.read('deepLink').objectValue,
  ).split('.').last,
  'description': route.annotation.read('description').isNull
      ? null
      : route.annotation.read('description').stringValue,
  'interceptorIds': route.annotation
      .read('interceptors')
      .listValue
      .map((value) => value.toStringValue())
      .toList(),
  'popGuardIds': route.annotation
      .read('popGuards')
      .listValue
      .map((value) => value.toStringValue())
      .toList(),
  'declaration': {
    'package': package,
    'library': source,
    'kind': route.contractFirst ? 'contract' : 'page',
    ..._sourceReference(route.page),
  },
  'navigationSources': [
    'typedIntent',
    'internalUri',
    if (_enumValue(
      route.annotation.read('deepLink').objectValue,
    ).endsWith('.enabled'))
      'externalDeepLink',
  ],
  'restoration': {'status': 'unsupported'},
  'placement': _placementJson(route.annotation.read('placement').objectValue),
  'presentation': _presentationJson(
    route.annotation.read('presentation').objectValue,
  ),
  'contracts': {
    'route': route.api,
    'arguments': route.arguments,
    'package': package,
    'library': route.contractFirst
        ? _routeContractOutputPath(source)
        : _routeLibraryOutputPath(source),
    if (!route.contractFirst) 'intentFactory': route.intentFactory,
  },
  if (!route.contractFirst) 'registration': route.registrationFunction,
  if (!route.contractFirst)
    'registrationLibrary': _routeLibraryOutputPath(source),
  if (!route.contractFirst)
    'destination': {
      'descriptor': route.descriptorFunction,
      'builder': route.builderFunction,
      'library': _routeLibraryOutputPath(source),
      'builderLibrary': _routeBindingOutputPath(source),
    },
  'generatedArtifacts': [
    {
      'role': route.contractFirst ? 'routeContract' : 'routeLibrary',
      'symbol': route.api,
      'packageUri': _packageUri(
        package,
        route.contractFirst
            ? _routeContractOutputPath(source)
            : _routeLibraryOutputPath(source),
      ),
    },
    if (!route.contractFirst)
      {
        'role': 'routeBinding',
        'symbol': route.builderFunction,
        'packageUri': _packageUri(package, _routeBindingOutputPath(source)),
      },
  ],
  'patterns': route.patterns.indexed.map((entry) {
    final index = entry.$1;
    final pattern = entry.$2;
    final type = (pattern.type as InterfaceType).element.displayName;
    return <String, Object?>{
      'type': type,
      'value': _field(
        pattern,
        type == 'CCRegexPattern' ? 'expression' : 'template',
      ).toStringValue(),
      'primary': index == route.primaryPatternIndex,
      if (type != 'CCRegexPattern')
        'constraints': _field(pattern, 'constraints').toMapValue()!.map(
          (key, value) =>
              MapEntry(key!.toStringValue()!, value!.toStringValue()!),
        ),
    };
  }).toList(),
  'parameters': route.parameters
      .map(
        (parameter) => <String, Object?>{
          'name': parameter.name,
          'wireName': parameter.wireName,
          'source': parameter.source,
          'type': parameter.type,
          if (parameter.source == 'query')
            'cardinality': parameter.queryCardinality,
          if (parameter.queryCodecType case final codecType?)
            'codec': codecType.getDisplayString(),
          'required': parameter.required,
          'default': parameter.defaultCode,
          'description': _documentation(
            parameter.element.documentationComment ??
                route.page.getField(parameter.name)?.documentationComment,
          ),
        },
      )
      .toList(),
  'resultType': route.result,
};

/// Serializes adapter-neutral Host, Shell, parent, and Outlet placement.
Map<String, Object?> _placementJson(DartObject placement) => {
  'hostId': _field(placement, 'hostId').toStringValue(),
  'parentRouteId': _field(placement, 'parentRouteId').toStringValue(),
  'shellId': _field(placement, 'shellId').toStringValue(),
  'navigatorOutlet': _field(placement, 'navigatorOutlet').toStringValue(),
};

/// Serializes the closed presentation hierarchy without backend-specific APIs.
Map<String, Object?> _presentationJson(DartObject presentation) {
  final type = (presentation.type as InterfaceType).element.displayName;
  return switch (type) {
    'CCPagePresentation' => {
      'type': 'page',
      'routeType': _enumValue(
        _field(presentation, 'routeType'),
      ).split('.').last,
      'transition': _enumValue(
        _field(presentation, 'transition'),
      ).split('.').last,
      'opaque': _field(presentation, 'opaque').toBoolValue(),
      'fullscreenDialog': _field(
        presentation,
        'fullscreenDialog',
      ).toBoolValue(),
    },
    'CCModalBottomSheetPresentation' => {
      'type': 'modalBottomSheet',
      'isDismissible': _field(presentation, 'isDismissible').toBoolValue(),
      'enableDrag': _field(presentation, 'enableDrag').toBoolValue(),
      'isScrollControlled': _field(
        presentation,
        'isScrollControlled',
      ).toBoolValue(),
      'showDragHandle': _field(presentation, 'showDragHandle').toBoolValue(),
      'useSafeArea': _field(presentation, 'useSafeArea').toBoolValue(),
    },
    'CCDialogPresentation' => {
      'type': 'dialog',
      'routeType': _enumValue(
        _field(presentation, 'routeType'),
      ).split('.').last,
      'barrierDismissible': _field(
        presentation,
        'barrierDismissible',
      ).toBoolValue(),
      'useSafeArea': _field(presentation, 'useSafeArea').toBoolValue(),
    },
    _ => throw StateError('Unsupported route presentation: $type'),
  };
}

/// Serializes one page binding without duplicating its public route contract.
Map<String, Object?> _routeImplementationJson(
  _RouteImplementationModel implementation, {
  required String package,
  required String source,
}) => {
  'routeId': implementation.contract.id,
  'componentId': implementation.contract.component.id,
  'package': package,
  'source': source,
  'contract': _sourceReference(implementation.contract.page),
  'implementation': _sourceReference(implementation.page),
  'registration': implementation.registrationFunction,
  'registrationLibrary': _routeBindingOutputPath(source),
  'destination': {
    'descriptor': implementation.descriptorFunction,
    'builder': implementation.builderFunction,
    'library': _routeBindingOutputPath(source),
    'builderLibrary': _routeBindingOutputPath(source),
  },
  'generatedArtifacts': [
    {
      'role': 'routeBinding',
      'symbol': implementation.registrationFunction,
      'packageUri': _packageUri(package, _routeBindingOutputPath(source)),
    },
  ],
};

/// Encodes an Analyzer declaration as a portable Package URI and exact span.
///
/// The generated metadata never stores an absolute checkout path. CLI and IDE
/// tooling can resolve the Package URI through `package_config.json` on the
/// machine where a developer is inspecting the catalog.
Map<String, Object?> _sourceReference(Element element) {
  final fragment = element.firstFragment;
  final libraryFragment = fragment.libraryFragment!;
  final location = libraryFragment.lineInfo.getLocation(
    fragment.nameOffset ?? fragment.offset,
  );
  return <String, Object?>{
    'symbol': element.displayName,
    'packageUri': libraryFragment.source.uri.toString(),
    'line': location.lineNumber,
    'column': location.columnNumber,
  };
}

/// Converts a Package-relative `lib/` path into a portable Package URI.
String _packageUri(String package, String libraryPath) {
  if (!libraryPath.startsWith('lib/')) {
    throw StateError('Generated library must be below lib/.');
  }
  return 'package:$package/${libraryPath.substring('lib/'.length)}';
}

/// Removes source comment markers while retaining authored explanations.
String? _documentation(String? comment) {
  if (comment == null) return null;
  return comment
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'^\s*/// ?'), ''))
      .join('\n')
      .trim();
}
