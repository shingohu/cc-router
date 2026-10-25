import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart' show CCComponentManifest;

import 'host_tool_integration.dart';
import 'host_lifecycle_binding.dart';
import 'route_catalog.dart';

/// Stable failure categories produced while resolving Host assembly data.
///
/// Host tooling may use these values for diagnostics. Feature code should not
/// catch them because generated package assembly is a Host configuration step.
enum CCHostAssemblyErrorCode {
  /// One Package ID resolved to incompatible versions or generated contents.
  packageConflict,

  /// Generated direct Package dependencies contain a cycle.
  packageDependencyCycle,

  /// More than one resolved Package declares the same component ID.
  duplicateComponent,

  /// A component's required dependency is absent from the resolved bundles.
  missingComponentDependency,

  /// Resolved component dependencies contain a cycle.
  componentDependencyCycle,

  /// Contract descriptors or consumer requirements are incompatible.
  contractCompatibility,

  /// Host tool integrations contain an empty or duplicate stable identity.
  hostToolIntegration,
}

/// Describes an invalid component, Contract, Package, or tooling graph.
///
/// Generation should normally reject generated-input failures before
/// compilation. The same validation protects handwritten Hosts, focused tests,
/// and stale or mixed artifacts from assembling an inconsistent Runtime.
final class CCHostAssemblyError implements Exception {
  /// Creates a typed Host assembly failure with a human-readable [message].
  const CCHostAssemblyError({
    required this.type,
    required this.message,
    this.contractIssue,
  });

  /// Stable category suitable for diagnostics and tests.
  final CCHostAssemblyErrorCode type;

  /// Explanation containing the conflicting Package or component identities.
  final String message;

  /// Structured Contract failure when [type] is [contractCompatibility].
  final CCContractCompatibilityIssue? contractIssue;

  @override
  String toString() => 'CCHostAssemblyError(${type.name}): $message';
}

/// Generated Host-only contribution published by one Dart Package.
///
/// A generated bundle contains only that Package's local runtime manifests and
/// Flutter destinations, plus references to bundles from its direct Pub
/// dependencies. This preserves Dart's direct-dependency import rule while a
/// Host can still assemble transitive CCRouter components without scanning or
/// importing nested Packages itself.
final class CCGeneratedPackageBundle {
  /// Creates an immutable Package contribution.
  ///
  /// [contentFingerprint] must cover the generated local contribution and its
  /// declared dependency identities. Two instances with the same [packageName]
  /// may be deduplicated only when both version and fingerprint match.
  CCGeneratedPackageBundle({
    required this.packageName,
    required this.packageVersion,
    required this.contentFingerprint,
    Iterable<CCComponentManifest> componentManifests = const [],
    CCFlutterRouteCatalog routeCatalog = const CCFlutterRouteCatalog.empty(),
    Iterable<CCGeneratedPackageBundle> dependencies = const [],
    this.contractBundle,
  }) : componentManifests = List.unmodifiable(componentManifests),
       routeCatalog = routeCatalog,
       dependencies = List.unmodifiable(dependencies) {
    if (packageName.trim().isEmpty) {
      throw ArgumentError.value(
        packageName,
        'packageName',
        'Must not be empty.',
      );
    }
    if (packageVersion.trim().isEmpty) {
      throw ArgumentError.value(
        packageVersion,
        'packageVersion',
        'Must not be empty.',
      );
    }
    if (contentFingerprint.trim().isEmpty) {
      throw ArgumentError.value(
        contentFingerprint,
        'contentFingerprint',
        'Must not be empty.',
      );
    }
  }

  /// Pub Package name used as the global deduplication identity.
  final String packageName;

  /// Package version recorded when this bundle was generated.
  final String packageVersion;

  /// Deterministic digest of this Package's generated assembly inputs.
  final String contentFingerprint;

  /// Runtime component manifests declared locally by this Package.
  final List<CCComponentManifest> componentManifests;

  /// Flutter destinations declared locally by this Package.
  final CCFlutterRouteCatalog routeCatalog;

  /// Generated bundles imported only from direct Pub dependencies.
  final List<CCGeneratedPackageBundle> dependencies;

  /// Contract descriptors and consumer requirements generated for this Package.
  final CCContractBundleDescriptor? contractBundle;

  /// Resolves root Package bundles for [CCHostAssembly].
  ///
  /// Dependencies precede dependants, Diamond dependencies are deduplicated,
  /// sibling Packages are ordered by Package name, and component manifests are
  /// ordered by their own required and present optional dependency graph.
  static CCHostAssembly _resolve(Iterable<CCGeneratedPackageBundle> roots) {
    final resolvedByName = <String, CCGeneratedPackageBundle>{};
    final orderedPackages = <CCGeneratedPackageBundle>[];
    final visiting = <String>{};

    void visit(CCGeneratedPackageBundle bundle) {
      final existing = resolvedByName[bundle.packageName];
      if (existing != null) {
        if (existing.packageVersion != bundle.packageVersion ||
            existing.contentFingerprint != bundle.contentFingerprint) {
          throw CCHostAssemblyError(
            type: CCHostAssemblyErrorCode.packageConflict,
            message:
                'Package "${bundle.packageName}" was resolved with '
                'incompatible generated identities '
                '(${existing.packageVersion}/${existing.contentFingerprint} '
                'and ${bundle.packageVersion}/${bundle.contentFingerprint}).',
          );
        }
        return;
      }
      if (!visiting.add(bundle.packageName)) {
        throw CCHostAssemblyError(
          type: CCHostAssemblyErrorCode.packageDependencyCycle,
          message:
              'Generated Package dependencies contain a cycle at '
              '"${bundle.packageName}".',
        );
      }
      final dependencies = bundle.dependencies.toList()
        ..sort((left, right) => left.packageName.compareTo(right.packageName));
      for (final dependency in dependencies) {
        visit(dependency);
      }
      visiting.remove(bundle.packageName);
      resolvedByName[bundle.packageName] = bundle;
      orderedPackages.add(bundle);
    }

    final sortedRoots = roots.toList()
      ..sort((left, right) => left.packageName.compareTo(right.packageName));
    for (final root in sortedRoots) {
      visit(root);
    }

    final contractBundles = [
      for (final package in orderedPackages)
        if (package.contractBundle != null) package.contractBundle!,
    ];
    _validateContractBundles(contractBundles);

    final manifests = _orderComponentManifests(orderedPackages);
    final versions = <String, String>{
      for (final manifest in manifests) manifest.id: manifest.version,
    };
    return CCHostAssembly._(
      packages: List.unmodifiable(orderedPackages),
      componentManifests: manifests,
      routeCatalog: CCFlutterRouteCatalog.merge(
        orderedPackages.map((bundle) => bundle.routeCatalog),
        componentVersions: versions,
      ),
      contractBundle: _mergeContractBundles(contractBundles),
    );
  }
}

/// Complete immutable inputs consumed by one application Host.
///
/// Generated Hosts create this snapshot from Package bundles. Handwritten
/// Hosts and focused tests may instead use [CCHostAssembly.fromComponents].
/// `CCRouterHost.initialize` accepts the complete assembly atomically so component,
/// Contract, route, and tooling inputs cannot be mixed across generations. The
/// assembly owns none of the referenced runtime objects.
final class CCHostAssembly {
  /// Extends complete Host inputs without dropping optional capability wiring.
  ///
  /// Host composition and integration tests may append handwritten components
  /// or replace the Flutter [routeCatalog]. Existing component identities cannot
  /// be removed or replaced: duplicate IDs and invalid dependency graphs fail
  /// with [CCHostAssemblyError]. New generated Contracts or UI contributions
  /// require regeneration, not handwritten manifests through this factory.
  ///
  /// Package provenance, Contract data, tooling and lifecycle bindings are
  /// preserved. Appended manifests do not invent Package bundle provenance.
  /// Catalog component versions are normalized against the extended graph.
  /// Bindings are shared plans, not cloned resources; initialize derived and
  /// original assemblies sequentially, awaiting shutdown between generations.
  factory CCHostAssembly.extend(
    CCHostAssembly assembly, {
    Iterable<CCComponentManifest> additionalComponents = const [],
    CCFlutterRouteCatalog? routeCatalog,
  }) {
    final extended = CCHostAssembly.fromComponents(
      components: [...assembly.componentManifests, ...additionalComponents],
      contractBundle: assembly.contractBundle,
      routeCatalog: routeCatalog ?? assembly.routeCatalog,
      hostToolIntegrations: assembly.hostToolIntegrations,
    );
    return CCHostAssembly._(
      packages: assembly.packages,
      componentManifests: extended.componentManifests,
      routeCatalog: extended.routeCatalog,
      contractBundle: assembly.contractBundle,
      hostToolIntegrations: assembly.hostToolIntegrations,
      lifecycleBindings: assembly.lifecycleBindings,
    );
  }

  /// Adds prevalidated optional capability bindings without splitting inputs.
  ///
  /// Optional adapters use this Host SPI to wrap an existing atomic assembly.
  /// Business components must not create bindings or control their lifecycle.
  factory CCHostAssembly.withLifecycleBindings(
    CCHostAssembly assembly,
    Iterable<CCHostLifecycleBinding> bindings,
  ) {
    final values = [...assembly.lifecycleBindings, ...bindings];
    final ids = <String>{};
    for (final binding in values) {
      if (binding.id.isEmpty || !ids.add(binding.id)) {
        throw StateError('Duplicate or empty Host lifecycle binding identity.');
      }
    }
    return CCHostAssembly._(
      packages: assembly.packages,
      componentManifests: assembly.componentManifests,
      routeCatalog: assembly.routeCatalog,
      contractBundle: assembly.contractBundle,
      hostToolIntegrations: assembly.hostToolIntegrations,
      lifecycleBindings: List.unmodifiable(values),
    );
  }

  /// Resolves Package bundles into one deterministic Host assembly.
  ///
  /// Dependencies precede dependants, diamond dependencies are deduplicated,
  /// sibling Packages are ordered by Package name, and component manifests are
  /// ordered by their required and present optional dependency graph.
  factory CCHostAssembly.fromPackageBundles(
    Iterable<CCGeneratedPackageBundle> roots, {
    Iterable<CCHostToolIntegration> hostToolIntegrations = const [],
  }) {
    final assembly = CCGeneratedPackageBundle._resolve(roots);
    return CCHostAssembly._(
      packages: assembly.packages,
      componentManifests: assembly.componentManifests,
      routeCatalog: assembly.routeCatalog,
      contractBundle: assembly.contractBundle,
      hostToolIntegrations: _validateHostToolIntegrations(hostToolIntegrations),
    );
  }

  /// Creates a deterministic assembly for a handwritten Host or focused test.
  ///
  /// Component dependencies are validated and ordered before the snapshot is
  /// returned. [contractBundle] is checked with the same compatibility rules
  /// used for generated Package bundles. [routeCatalog] remains backend-neutral
  /// and is normalized with the installed component versions.
  /// This creates fresh inputs with no optional lifecycle bindings or Package
  /// provenance. Use [CCHostAssembly.extend] to adapt an existing assembly.
  factory CCHostAssembly.fromComponents({
    required Iterable<CCComponentManifest> components,
    CCContractBundleDescriptor? contractBundle,
    CCFlutterRouteCatalog routeCatalog = const CCFlutterRouteCatalog.empty(),
    Iterable<CCHostToolIntegration> hostToolIntegrations = const [],
  }) {
    final componentManifests = _orderComponentManifestValues(components);
    if (contractBundle != null) {
      _validateContractBundles([contractBundle]);
    }
    final componentVersions = <String, String>{
      for (final manifest in componentManifests) manifest.id: manifest.version,
    };
    return CCHostAssembly._(
      packages: const [],
      componentManifests: componentManifests,
      routeCatalog: CCFlutterRouteCatalog.merge([
        routeCatalog,
      ], componentVersions: componentVersions),
      contractBundle: contractBundle,
      hostToolIntegrations: _validateHostToolIntegrations(hostToolIntegrations),
    );
  }

  /// Creates a validated snapshot after Package and component graph resolution.
  const CCHostAssembly._({
    required this.packages,
    required this.componentManifests,
    required this.routeCatalog,
    required this.contractBundle,
    this.hostToolIntegrations = const [],
    this.lifecycleBindings = const [],
  });

  /// Resolved Packages in dependency-before-dependant deterministic order.
  final List<CCGeneratedPackageBundle> packages;

  /// Component manifests in component dependency order.
  final List<CCComponentManifest> componentManifests;

  /// Merged backend-neutral Flutter destinations for this Host.
  final CCFlutterRouteCatalog routeCatalog;

  /// Resolved Contract descriptors and consumer requirements, when generated.
  final CCContractBundleDescriptor? contractBundle;

  /// Optional Host tooling started and stopped with the default Runtime.
  ///
  /// Generated assemblies populate this list only when the Host directly opts
  /// into a supported tool Package. Business components must not invoke these
  /// integrations or treat them as application capabilities.
  final List<CCHostToolIntegration> hostToolIntegrations;

  /// Optional capability bindings; empty for Hosts that do not opt in.
  final List<CCHostLifecycleBinding> lifecycleBindings;
}

/// Copies and validates Host tooling before the assembly becomes observable.
List<CCHostToolIntegration> _validateHostToolIntegrations(
  Iterable<CCHostToolIntegration> integrations,
) {
  final byId = <String, CCHostToolIntegration>{};
  for (final integration in integrations) {
    final id = integration.id.trim();
    if (id.isEmpty || byId.containsKey(id)) {
      throw CCHostAssemblyError(
        type: CCHostAssemblyErrorCode.hostToolIntegration,
        message: 'Invalid or duplicate Host tool integration ID "$id".',
      );
    }
    byId[id] = integration;
  }
  final ids = byId.keys.toList()..sort();
  return List.unmodifiable(ids.map((id) => byId[id]!));
}

/// Rejects incompatible Contract descriptors before a Host becomes visible.
void _validateContractBundles(Iterable<CCContractBundleDescriptor> bundles) {
  final contractIssues = CCContractBundleDescriptor.validate(bundles);
  if (contractIssues.isEmpty) return;
  throw CCHostAssemblyError(
    type: CCHostAssemblyErrorCode.contractCompatibility,
    contractIssue: contractIssues.first,
    message: contractIssues.map((issue) => issue.toString()).join(' '),
  );
}

CCContractBundleDescriptor? _mergeContractBundles(
  Iterable<CCContractBundleDescriptor> bundles,
) {
  final values = bundles.toList(growable: false);
  if (values.isEmpty) return null;
  final contracts = <String, CCContractDescriptor>{};
  final requirements = <String, CCContractRequirement>{};
  for (final bundle in values) {
    for (final contract in bundle.contracts) {
      contracts.putIfAbsent(contract.id, () => contract);
    }
    for (final requirement in bundle.requirements) {
      final key =
          '${requirement.consumerPackage}\u0000${requirement.kind.name}\u0000'
          '${requirement.contractId}\u0000${requirement.ownerComponentId}';
      requirements.putIfAbsent(key, () => requirement);
    }
  }
  return CCContractBundleDescriptor(
    packageName: 'resolved-host',
    packageVersion: '0.0.0',
    contracts: contracts.values,
    requirements: requirements.values,
  );
}

/// Orders component manifests and validates their cross-Package dependency graph.
List<CCComponentManifest> _orderComponentManifests(
  Iterable<CCGeneratedPackageBundle> packages,
) {
  return _orderComponentManifestValues(
    packages.expand((package) => package.componentManifests),
  );
}

/// Orders and validates one complete Host component graph.
List<CCComponentManifest> _orderComponentManifestValues(
  Iterable<CCComponentManifest> manifests,
) {
  final manifestsById = <String, CCComponentManifest>{};
  for (final manifest in manifests) {
    final existing = manifestsById[manifest.id];
    if (existing != null) {
      throw CCHostAssemblyError(
        type: CCHostAssemblyErrorCode.duplicateComponent,
        message:
            'Component "${manifest.id}" is declared more than once in the '
            'Host assembly.',
      );
    }
    manifestsById[manifest.id] = manifest;
  }

  for (final manifest in manifestsById.values) {
    for (final dependency in manifest.dependencies) {
      if (!manifestsById.containsKey(dependency)) {
        throw CCHostAssemblyError(
          type: CCHostAssemblyErrorCode.missingComponentDependency,
          message:
              'Component "${manifest.id}" requires missing component '
              '"$dependency".',
        );
      }
    }
  }

  final ordered = <CCComponentManifest>[];
  final visited = <String>{};
  final visiting = <String>{};

  void visit(String id) {
    if (visited.contains(id)) return;
    if (!visiting.add(id)) {
      throw CCHostAssemblyError(
        type: CCHostAssemblyErrorCode.componentDependencyCycle,
        message: 'Component dependencies contain a cycle at "$id".',
      );
    }
    final manifest = manifestsById[id]!;
    final dependencies = <String>{
      ...manifest.dependencies,
      ...manifest.optionalDependencies.where(manifestsById.containsKey),
    }.toList()..sort();
    for (final dependency in dependencies) {
      visit(dependency);
    }
    visiting.remove(id);
    visited.add(id);
    ordered.add(manifest);
  }

  final ids = manifestsById.keys.toList()..sort();
  for (final id in ids) {
    visit(id);
  }
  return List.unmodifiable(ordered);
}
