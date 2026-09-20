part of 'runtime.dart';

/// Stores a Shell definition together with its trusted component owner.
final class _RegisteredShell {
  /// Creates an active Shell owned by [ownerComponentId].
  _RegisteredShell({required this.ownerComponentId, required this.definition});

  /// Component ID captured from the component-bound Registry.
  final String ownerComponentId;

  /// Adapter-neutral Shell definition retained by Runtime.
  final CCShellDefinition definition;

  /// Whether routes targeting this Shell may currently navigate.
  bool active = true;
}

/// Registers and validates component-owned Shell contracts.
final class _ShellRegistry {
  /// Creates an empty Shell registry.
  _ShellRegistry();

  /// Shell records indexed by stable Shell ID.
  final Map<String, _RegisteredShell> _shells = {};

  /// Stable Shell IDs in deterministic order for diagnostics and tests.
  List<String> get shellIds => _shells.keys.toList()..sort();

  /// Adapter-facing Shell snapshots in deterministic ID order.
  List<CCNavigationShell> get navigationShells {
    final shells = _shells.values.toList()
      ..sort(
        (first, second) =>
            first.definition.shellId.compareTo(second.definition.shellId),
      );
    return List.unmodifiable(
      shells.map(
        (shell) => CCNavigationShell(
          shellId: shell.definition.shellId,
          type: shell.definition.type,
          outlets: shell.definition.outlets,
          initialOutlet: shell.definition.initialOutlet,
        ),
      ),
    );
  }

  /// Adds [definition] for [ownerComponentId] after structural validation.
  void register(String ownerComponentId, CCShellDefinition definition) {
    _validateDefinition(definition);
    if (_shells.containsKey(definition.shellId)) {
      throw CCShellRegistrationError(
        'Duplicate Shell ID "${definition.shellId}".',
      );
    }
    _shells[definition.shellId] = _RegisteredShell(
      ownerComponentId: ownerComponentId,
      definition: definition,
    );
  }

  /// Validates one route placement against installed Shell contracts.
  void validateRoutePlacement(String routeId, CCRoutePlacement placement) {
    final shellId = placement.shellId;
    if (shellId == null) return;
    final shell = _shells[shellId];
    if (shell == null) {
      throw CCRouteRegistrationError(
        'Route "$routeId" targets unknown Shell "$shellId".',
      );
    }
    if (!shell.definition.outlets.contains(placement.navigatorOutlet)) {
      throw CCRouteRegistrationError(
        'Route "$routeId" targets unknown Outlet '
        '"${placement.navigatorOutlet}" in Shell "$shellId".',
      );
    }
  }

  /// Rejects navigation through an inactive Shell owner.
  void ensureRouteAvailable(String routeId, CCRoutePlacement placement) {
    final shellId = placement.shellId;
    if (shellId == null) return;
    final shell = _shells[shellId];
    if (shell == null || !shell.active) {
      throw CCRouteUnavailableError(routeId);
    }
  }

  /// Marks all Shells owned by [componentId] available.
  void activateComponent(String componentId) {
    for (final shell in _shells.values) {
      if (shell.ownerComponentId == componentId) shell.active = true;
    }
  }

  /// Marks all Shells owned by [componentId] unavailable.
  void deactivateComponent(String componentId) {
    for (final shell in _shells.values) {
      if (shell.ownerComponentId == componentId) shell.active = false;
    }
  }

  /// Validates identity, ordered Outlets, and default Outlet rules.
  void _validateDefinition(CCShellDefinition definition) {
    final shellId = definition.shellId;
    if (!_isStableIdentifier(shellId)) {
      throw CCShellRegistrationError(
        'Shell ID "$shellId" is invalid; use lowercase alphanumeric '
        'segments separated by ".", "_", or "-".',
      );
    }
    if (definition.outlets.isEmpty) {
      throw CCShellRegistrationError(
        'Shell "$shellId" must declare at least one Outlet.',
      );
    }
    final seen = <String>{};
    for (final outlet in definition.outlets) {
      if (!_isStableIdentifier(outlet) || !seen.add(outlet)) {
        throw CCShellRegistrationError(
          'Shell "$shellId" contains an invalid or duplicate Outlet ID.',
        );
      }
    }
    if (!seen.contains(definition.initialOutlet)) {
      throw CCShellRegistrationError(
        'Shell "$shellId" initial Outlet '
        '"${definition.initialOutlet}" is not declared.',
      );
    }
    switch (definition.type) {
      case CCShellType.singleNavigator:
        if (definition.outlets.length != 1) {
          throw CCShellRegistrationError(
            'Single-Navigator Shell "$shellId" must declare one Outlet.',
          );
        }
        break;
      case CCShellType.statefulBranches:
        if (definition.outlets.length < 2) {
          throw CCShellRegistrationError(
            'Stateful Shell "$shellId" must declare at least two Outlets.',
          );
        }
    }
  }
}
