import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/widgets.dart';

/// Builds one Flutter destination from already separated route arguments.
///
/// Generated component code supplies this function after decoding values with
/// its typed route codec. Navigation backends invoke it only while rendering a
/// route; business callers should construct generated Intents instead.
typedef CCFlutterRouteBuilder =
    Widget Function(CCEncodedRouteArguments arguments);

/// Describes one component-owned Flutter destination without backend types.
///
/// Generated component catalogs use this Host SPI to associate adapter-neutral
/// route metadata with the page factory that renders it. GoRouter, Navigator
/// 1.0, Navigator 2.0, or another backend may consume the same destination.
final class CCFlutterRouteDestination {
  /// Creates an immutable generated destination for [route].
  CCFlutterRouteDestination({required this.route, required this.builder});

  /// Adapter-neutral route metadata registered with the Runtime.
  final CCNavigationRoute route;

  /// Generated page factory that decodes and injects route arguments.
  final CCFlutterRouteBuilder builder;

  /// Stable route identity shared by Runtime and backend assemblies.
  String get routeId => route.routeId;

  /// Builds the destination after a backend separates Path, Query, and Extra.
  Widget build(CCEncodedRouteArguments arguments) => builder(arguments);
}

/// Immutable collection of Flutter destinations available to one Host.
///
/// Component generators create small catalogs and the host generator merges
/// them. Backend assemblers consume the merged catalog without importing page
/// libraries or discovering routes at runtime.
final class CCFlutterRouteCatalog {
  /// Creates a catalog and rejects duplicate route identities.
  ///
  /// Host-generated catalogs provide [componentVersions] so Backend attachment
  /// can reject a catalog assembled for a different Runtime component set.
  /// Component-local and test catalogs may omit it until they are merged by a
  /// Host generator.
  CCFlutterRouteCatalog(
    Iterable<CCFlutterRouteDestination> destinations, {
    Map<String, String> componentVersions = const {},
  }) : destinations = List.unmodifiable(destinations),
       componentVersions = Map.unmodifiable(componentVersions) {
    final routeIds = <String>{};
    for (final destination in this.destinations) {
      if (!routeIds.add(destination.routeId)) {
        throw ArgumentError.value(
          destination.routeId,
          'destinations',
          'A Flutter route catalog cannot contain duplicate route IDs.',
        );
      }
    }
  }

  /// Creates an empty catalog for Hosts without generated Flutter routes.
  const CCFlutterRouteCatalog.empty()
    : destinations = const [],
      componentVersions = const {};

  /// Merges component catalogs while preserving their declared order.
  ///
  /// Host generators use this constructor after sorting components and routes
  /// deterministically. Duplicate IDs remain an error at the final boundary.
  factory CCFlutterRouteCatalog.merge(
    Iterable<CCFlutterRouteCatalog> catalogs, {
    Map<String, String> componentVersions = const {},
  }) => CCFlutterRouteCatalog(
    catalogs.expand((catalog) => catalog.destinations),
    componentVersions: componentVersions,
  );

  /// Destinations in deterministic component and route order.
  final List<CCFlutterRouteDestination> destinations;

  /// Component versions used to generate this Host-level route catalog.
  ///
  /// Managed Hosts compare this provenance with the Runtime registration before
  /// attaching an Adapter. It is diagnostic assembly metadata and must not be
  /// used by feature code for availability or authorization decisions.
  final Map<String, String> componentVersions;

  /// Returns the destination for [routeId], or null when it is not installed.
  CCFlutterRouteDestination? destinationFor(String routeId) {
    for (final destination in destinations) {
      if (destination.routeId == routeId) return destination;
    }
    return null;
  }
}
