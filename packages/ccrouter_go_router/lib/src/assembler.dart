import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter/widgets.dart' show Page;
import 'package:go_router/go_router.dart';

import 'modal_pages.dart';
import 'page.dart';
import 'route_binding.dart';

/// Overrides generated GoRouter assembly for one exceptional destination.
///
/// Use this at the application composition root for Shell children, custom
/// redirects, backend-specific guards, or another route that cannot use the
/// default flat mapping. Ordinary component pages should stay generated.
final class CCGoRouterRouteOverride {
  /// Creates an override around one application-owned [binding].
  const CCGoRouterRouteOverride({
    required this.binding,
    this.includeInRootRoutes = true,
  });

  /// Binding used by the Adapter for route identity and capability validation.
  final CCGoRouterRouteBinding binding;

  /// Whether the overridden GoRoute belongs in the returned root route list.
  ///
  /// Set this to false when the Host mounts [binding]'s route below a Shell or
  /// another manually assembled parent. The binding is still returned so the
  /// Adapter can correlate Runtime navigation with that mounted route.
  final bool includeInRootRoutes;
}

/// Immutable GoRouter objects assembled from one Flutter route catalog.
///
/// Hosts pass [routes] to their application-owned GoRouter and [bindings] to
/// [CCGoRouterAdapter]. Both collections come from the same source, preventing
/// route-tree and Adapter registration drift.
final class CCGoRouterAssembly {
  /// Creates one validated assembly result.
  CCGoRouterAssembly({
    required Iterable<RouteBase> routes,
    required Iterable<CCGoRouterRouteBinding> bindings,
  }) : routes = List.unmodifiable(routes),
       bindings = List.unmodifiable(bindings);

  /// Generated root routes plus root-level overrides in stable catalog order.
  final List<RouteBase> routes;

  /// Adapter bindings for every destination, including externally mounted ones.
  final List<CCGoRouterRouteBinding> bindings;
}

/// Converts backend-neutral Flutter destinations into GoRouter configuration.
///
/// The Assembler is a Host API. It never registers Runtime routes and does not
/// own or dispose the resulting GoRouter. Feature code should navigate through
/// `CCRouter.navigator` rather than retaining this object.
abstract final class CCGoRouterAssembler {
  /// Assembles ordinary root routes and applies explicit [overrides].
  ///
  /// Automatic assembly rejects nested placement and full regular-expression
  /// aliases because GoRouter cannot reproduce those contracts as independent
  /// flat `GoRoute` declarations. Supply an override when the Host owns the
  /// corresponding route tree or compatibility matcher.
  static CCGoRouterAssembly assemble({
    required CCFlutterRouteCatalog catalog,
    Map<String, CCGoRouterRouteOverride> overrides = const {},
  }) {
    final routeIds = catalog.destinations
        .map((destination) => destination.routeId)
        .toSet();
    final unknownOverrides =
        overrides.keys.where((routeId) => !routeIds.contains(routeId)).toList()
          ..sort();
    if (unknownOverrides.isNotEmpty) {
      throw CCNavigationAdapterError(
        'GoRouter overrides reference unknown catalog routes: '
        '${unknownOverrides.join(', ')}.',
      );
    }

    final routes = <RouteBase>[];
    final bindings = <CCGoRouterRouteBinding>[];
    final generatedPaths = <String, String>{};
    for (final destination in catalog.destinations) {
      final override = overrides[destination.routeId];
      if (override != null) {
        if (override.binding.routeId != destination.routeId) {
          throw CCNavigationAdapterError(
            'GoRouter override key "${destination.routeId}" does not match '
            'binding "${override.binding.routeId}".',
          );
        }
        bindings.add(override.binding);
        if (override.includeInRootRoutes) routes.add(override.binding.goRoute);
        continue;
      }

      _validateAutomaticPlacement(destination.route);
      final routePatterns = _goRouterPatterns(destination.route);
      late CCGoRouterRouteBinding binding;
      for (final pattern in routePatterns) {
        final previousRouteId = generatedPaths[pattern.path];
        if (previousRouteId != null && previousRouteId != destination.routeId) {
          throw CCNavigationAdapterError(
            'GoRouter path "${pattern.path}" is shared by catalog routes '
            '"$previousRouteId" and "${destination.routeId}".',
          );
        }
        generatedPaths[pattern.path] = destination.routeId;
        final goRoute = GoRoute(
          path: pattern.path,
          name: pattern.primary ? destination.routeId : null,
          pageBuilder: (context, state) => _buildPage(destination, state),
        );
        routes.add(goRoute);
        if (pattern.primary) {
          binding = CCGoRouterRouteBinding(
            routeId: destination.routeId,
            goRoute: goRoute,
            presentationType: _presentationType(destination.route.presentation),
          );
        }
      }
      bindings.add(binding);
    }
    return CCGoRouterAssembly(routes: routes, bindings: bindings);
  }

  /// Rejects structures that require an application-owned GoRouter tree.
  static void _validateAutomaticPlacement(CCNavigationRoute route) {
    final placement = route.placement;
    if (placement.parentRouteId != null ||
        placement.shellId != null ||
        placement.navigatorOutlet != 'root') {
      throw CCNavigationAdapterError(
        'Route "${route.routeId}" has nested placement and requires a '
        'CCGoRouterRouteOverride mounted by the Host.',
      );
    }
  }

  /// Converts reversible Path and URI templates into unique GoRouter paths.
  static List<_CCGoRouterPattern> _goRouterPatterns(CCNavigationRoute route) {
    final patterns = <_CCGoRouterPattern>[];
    final paths = <String>{};
    for (final pattern in route.patterns) {
      final path = switch (pattern) {
        CCPathPattern(:final template) => template,
        CCUriPattern(:final template) => _pathFromUriTemplate(template),
        CCRegexPattern() => throw CCNavigationAdapterError(
          'Route "${route.routeId}" has a regular-expression alias and '
          'requires a CCGoRouterRouteOverride.',
        ),
      };
      if (paths.add(path)) {
        patterns.add(_CCGoRouterPattern(path, primary: pattern.primary));
      } else if (pattern.primary &&
          !patterns.any((item) => item.path == path && item.primary)) {
        final index = patterns.indexWhere((item) => item.path == path);
        patterns[index] = _CCGoRouterPattern(path, primary: true);
      }
    }
    if (!patterns.any((pattern) => pattern.primary)) {
      throw CCNavigationAdapterError(
        'Route "${route.routeId}" has no GoRouter-compatible primary path.',
      );
    }
    return patterns;
  }

  /// Removes URI authority because GoRouter matches the location path.
  static String _pathFromUriTemplate(String template) {
    final uri = Uri.parse(template);
    return uri.path.isEmpty ? '/' : uri.path;
  }

  /// Builds the matching Flutter Page family from adapter-neutral metadata.
  static Page<Object?> _buildPage(
    CCFlutterRouteDestination destination,
    GoRouterState state,
  ) {
    final payload = state.extra;
    final extra = CCRouterHostBinding.decodeRouteExtra(payload);
    final destinationChild = destination.build(
      CCEncodedRouteArguments(
        path: state.pathParameters,
        query: state.uri.queryParametersAll,
        extra: extra,
      ),
    );
    final child = CCRouterHostBinding.bindRouteEntry(
      payload: payload,
      child: destinationChild,
    );
    final presentation = destination.route.presentation;
    return switch (presentation) {
      final CCPagePresentation page => ccGoRouterPage(
        child: child,
        presentation: page,
        key: state.pageKey,
        name: destination.routeId,
        arguments: extra,
      ),
      final CCModalBottomSheetPresentation sheet => ccGoRouterBottomSheetPage(
        child: child,
        presentation: sheet,
        key: state.pageKey,
        name: destination.routeId,
        arguments: extra,
      ),
      final CCDialogPresentation dialog => ccGoRouterDialogPage(
        child: child,
        presentation: dialog,
        key: state.pageKey,
        name: destination.routeId,
        arguments: extra,
      ),
    };
  }

  /// Maps a route presentation to Adapter validation metadata.
  static CCGoRouterPresentationType _presentationType(
    CCRoutePresentation presentation,
  ) => switch (presentation) {
    CCPagePresentation() => CCGoRouterPresentationType.page,
    CCModalBottomSheetPresentation() => CCGoRouterPresentationType.bottomSheet,
    CCDialogPresentation() => CCGoRouterPresentationType.dialog,
  };
}

/// One normalized GoRouter path and its canonical-address status.
final class _CCGoRouterPattern {
  /// Creates an immutable normalized pattern.
  const _CCGoRouterPattern(this.path, {required this.primary});

  /// Slash-prefixed path understood by GoRouter.
  final String path;

  /// Whether this path receives the stable route name and Adapter binding.
  final bool primary;
}
