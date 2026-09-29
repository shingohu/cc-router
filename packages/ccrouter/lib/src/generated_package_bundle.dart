import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart' show CCComponentManifest;

import 'route_catalog.dart';

/// Stable failure categories produced while resolving generated Package data.
///
/// Host tooling may use these values for diagnostics. Feature code should not
/// catch them because generated package assembly is a Host configuration step.
enum CCGeneratedPackageBundleErrorCode {
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
}

/// Describes an invalid generated Package graph at the Host boundary.
///
/// Generation should normally reject these failures before compilation. The
/// runtime check protects handwritten fixtures and stale or mixed generated
/// artifacts from silently assembling an inconsistent Host.
final class CCGeneratedPackageBundleError implements Exception {
  /// Creates a typed Host assembly failure with a human-readable [message].
  const CCGeneratedPackageBundleError({
    required this.type,
    required this.message,
    this.contractIssue,
  });

  /// Stable category suitable for diagnostics and tests.
  final CCGeneratedPackageBundleErrorCode type;

  /// Explanation containing the conflicting Package or component identities.
  final String message;

  /// Structured Contract failure when [type] is [contractCompatibility].
  final CCContractCompatibilityIssue? contractIssue;

  @override
  String toString() => 'CCGeneratedPackageBundleError(${type.name}): $message';
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

  /// Resolves root Package bundles for [CCGeneratedHostAssembly].
  ///
  /// Dependencies precede dependants, Diamond dependencies are deduplicated,
  /// sibling Packages are ordered by Package name, and component manifests are
  /// ordered by their own required and present optional dependency graph.
  static CCGeneratedHostAssembly _resolve(
    Iterable<CCGeneratedPackageBundle> roots,
  ) {
    final resolvedByName = <String, CCGeneratedPackageBundle>{};
    final orderedPackages = <CCGeneratedPackageBundle>[];
    final visiting = <String>{};

    void visit(CCGeneratedPackageBundle bundle) {
      final existing = resolvedByName[bundle.packageName];
      if (existing != null) {
        if (existing.packageVersion != bundle.packageVersion ||
            existing.contentFingerprint != bundle.contentFingerprint) {
          throw CCGeneratedPackageBundleError(
            type: CCGeneratedPackageBundleErrorCode.packageConflict,
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
        throw CCGeneratedPackageBundleError(
          type: CCGeneratedPackageBundleErrorCode.packageDependencyCycle,
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
    final contractIssues = CCContractBundleDescriptor.validate(contractBundles);
    if (contractIssues.isNotEmpty) {
      throw CCGeneratedPackageBundleError(
        type: CCGeneratedPackageBundleErrorCode.contractCompatibility,
        contractIssue: contractIssues.first,
        message: contractIssues.map((issue) => issue.toString()).join(' '),
      );
    }

    final manifests = _orderComponentManifests(orderedPackages);
    final versions = <String, String>{
      for (final manifest in manifests) manifest.id: manifest.version,
    };
    return CCGeneratedHostAssembly._(
      packages: orderedPackages,
      componentManifests: manifests,
      routeCatalog: CCFlutterRouteCatalog.merge(
        orderedPackages.map((bundle) => bundle.routeCatalog),
        componentVersions: versions,
      ),
      contractBundle: _mergeContractBundles(contractBundles),
    );
  }
}

/// Fully validated generated inputs consumed by one application Host.
///
/// Host bootstrap code passes [componentManifests] to `CCRouter.initialize`
/// and [routeCatalog] to its chosen navigation backend. The assembly is a
/// read-only snapshot and owns none of the referenced runtime objects.
final class CCGeneratedHostAssembly {
  /// Resolves Package bundles into one deterministic Host assembly.
  ///
  /// Dependencies precede dependants, diamond dependencies are deduplicated,
  /// sibling Packages are ordered by Package name, and component manifests are
  /// ordered by their required and present optional dependency graph.
  factory CCGeneratedHostAssembly.fromPackageBundles(
    Iterable<CCGeneratedPackageBundle> roots,
  ) => CCGeneratedPackageBundle._resolve(roots);

  /// Creates a validated snapshot after Package and component graph resolution.
  const CCGeneratedHostAssembly._({
    required this.packages,
    required this.componentManifests,
    required this.routeCatalog,
    required this.contractBundle,
  });

  /// Resolved Packages in dependency-before-dependant deterministic order.
  final List<CCGeneratedPackageBundle> packages;

  /// Component manifests in component dependency order.
  final List<CCComponentManifest> componentManifests;

  /// Merged backend-neutral Flutter destinations for this Host.
  final CCFlutterRouteCatalog routeCatalog;

  /// Resolved Contract descriptors and consumer requirements, when generated.
  final CCContractBundleDescriptor? contractBundle;
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
  final manifestsById = <String, CCComponentManifest>{};
  for (final package in packages) {
    for (final manifest in package.componentManifests) {
      final existing = manifestsById[manifest.id];
      if (existing != null) {
        throw CCGeneratedPackageBundleError(
          type: CCGeneratedPackageBundleErrorCode.duplicateComponent,
          message:
              'Component "${manifest.id}" is declared more than once in the '
              'resolved Package graph.',
        );
      }
      manifestsById[manifest.id] = manifest;
    }
  }

  for (final manifest in manifestsById.values) {
    for (final dependency in manifest.dependencies) {
      if (!manifestsById.containsKey(dependency)) {
        throw CCGeneratedPackageBundleError(
          type: CCGeneratedPackageBundleErrorCode.missingComponentDependency,
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
      throw CCGeneratedPackageBundleError(
        type: CCGeneratedPackageBundleErrorCode.componentDependencyCycle,
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
