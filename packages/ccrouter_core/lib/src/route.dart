part of 'runtime.dart';

/// Stores a route definition together with its trusted component owner.
///
/// The internal registry uses this record to apply component availability and
/// ownership rules without accepting an owner supplied by component code.
final class _RegisteredRoute {
  /// Creates an active route owned by [ownerComponentId].
  _RegisteredRoute({required this.ownerComponentId, required this.definition});

  /// Component ID captured from the component-bound Registry.
  final String ownerComponentId;

  /// Type-erased definition retained by the Runtime route table.
  final CCRouteDefinition<dynamic, dynamic> definition;

  /// Whether navigation may currently resolve this route.
  bool active = true;
}

/// Captures parameters and specificity from one successful pattern match.
///
/// Pattern-specific matchers use this value before attaching route ownership,
/// query parameters, and the normalized location to a final candidate.
final class _PatternMatch {
  /// Creates immutable match metadata for one route pattern.
  _PatternMatch({required this.pathParameters, required this.specificity});

  /// Named values captured by a template or regular expression.
  final Map<String, String> pathParameters;

  /// Specificity within one pattern priority tier.
  final int specificity;
}

/// Route data prepared for one adapter-bound navigation request.
///
/// The registry creates this value after availability, Pattern, and Codec checks
/// so Runtime navigation code does not access mutable registry implementation.
final class _PreparedRoute {
  /// Creates a fully validated internal navigation payload.
  _PreparedRoute({
    required this.routeId,
    required this.ownerComponentId,
    required this.uri,
    required this.arguments,
    required this.extra,
    required this.presentation,
    required this.placement,
    required this.interceptorIds,
    required this.popGuardIds,
  });

  /// Stable route identity selected by Intent or URI resolution.
  final String routeId;

  /// Component that owns the selected route definition.
  final String ownerComponentId;

  /// Canonical generated URI or normalized dynamically supplied URI.
  final Uri uri;

  /// Typed route arguments accepted or produced by the registered Codec.
  final Object arguments;

  /// Optional in-memory value retained only for typed internal navigation.
  final Object? extra;

  /// Adapter-neutral presentation metadata for this route.
  final CCRoutePresentation presentation;

  /// Structural parent, Shell, and Navigator outlet for this request.
  final CCRoutePlacement placement;

  /// Route interceptor IDs declared by the selected route definition.
  final List<String> interceptorIds;

  /// Route Pop guard IDs declared by the selected route definition.
  final List<String> popGuardIds;
}

/// Candidate produced while comparing one URI against an installed pattern.
final class _RouteCandidate {
  /// Creates a candidate with deterministic matching metadata.
  _RouteCandidate({
    required this.location,
    required this.priority,
    required this.specificity,
  });

  /// Decoded route location returned to the navigation pipeline.
  final CCRouteLocation location;

  /// Pattern tier, where URI outranks Path and Path outranks Regex.
  final int priority;

  /// Specificity within [priority].
  final int specificity;
}

/// Registers and resolves the Runtime's component-owned route definitions.
///
/// This class is kept inside the Runtime library so component ownership and
/// active-state checks cannot be bypassed by a public route table API.
/// Component assembly uses it for registration, while navigation adapters use
/// it for matching and argument decoding.
final class _RouteRegistry {
  /// Creates a registry with Host placement and external-ingress policies.
  _RouteRegistry(this._shellRegistry, this._deepLinkIngressPolicy);

  /// Installed Shell contracts used to validate and gate route placement.
  final _ShellRegistry _shellRegistry;

  /// Immutable Host allowlist checked before external route matching.
  final CCDeepLinkIngressPolicy _deepLinkIngressPolicy;

  /// Priority assigned to structured absolute-URI patterns.
  static const int _uriPriority = 3;

  /// Priority assigned to authority-independent path patterns.
  static const int _pathPriority = 2;

  /// Priority assigned to full regular-expression compatibility patterns.
  static const int _regexPriority = 1;

  /// Definitions indexed by stable route ID.
  final Map<String, _RegisteredRoute> _routes = {};

  /// Stable IDs in deterministic order for diagnostics and tests.
  List<String> get routeIds => _routes.keys.toList()..sort();

  /// Adapter-facing snapshots of all installed routes in stable ID order.
  List<CCNavigationRoute> get navigationRoutes {
    final routes = _routes.values.toList()
      ..sort(
        (first, second) =>
            first.definition.routeId.compareTo(second.definition.routeId),
      );
    return List.unmodifiable(
      routes.map(
        (route) => CCNavigationRoute(
          routeId: route.definition.routeId,
          patterns: route.definition.patterns,
          presentation: route.definition.presentation,
          deepLink: route.definition.deepLink,
          placement: route.definition.placement,
        ),
      ),
    );
  }

  /// Adds [definition] for [ownerComponentId] after static validation.
  void register<A, R>(
    String ownerComponentId,
    CCRouteDefinition<A, R> definition,
  ) {
    _validateDefinition(definition);
    if (_routes.containsKey(definition.routeId)) {
      throw CCRouteRegistrationError(
        'Duplicate route ID "${definition.routeId}".',
      );
    }
    final normalized = definition as CCRouteDefinition<dynamic, dynamic>;
    for (var index = 0; index < normalized.patterns.length; index++) {
      for (
        var otherIndex = index + 1;
        otherIndex < normalized.patterns.length;
        otherIndex++
      ) {
        final pattern = normalized.patterns[index];
        final other = normalized.patterns[otherIndex];
        if (_patternsConflict(pattern, other)) {
          throw CCRouteRegistrationError(
            'Route "${definition.routeId}" contains ambiguous patterns '
            '"${_patternLabel(pattern)}" and "${_patternLabel(other)}".',
          );
        }
      }
    }
    for (final existing in _routes.values) {
      for (final existingPattern in existing.definition.patterns) {
        for (final pattern in normalized.patterns) {
          if (_patternsConflict(existingPattern, pattern)) {
            throw CCRouteRegistrationError(
              'Pattern "${_patternLabel(pattern)}" conflicts with route '
              '"${existing.definition.routeId}".',
            );
          }
        }
      }
    }
    _routes[definition.routeId] = _RegisteredRoute(
      ownerComponentId: ownerComponentId,
      definition: normalized,
    );
  }

  /// Decodes a matched [location] through its generated route codec.
  Object decode(CCRouteLocation location, {Object? extra}) {
    final route = _requireActiveRoute(location.routeId);
    try {
      return route.definition.codec.decode(
            CCEncodedRouteArguments(
              path: location.pathParameters,
              query: location.queryParameters,
              extra: extra,
            ),
          )
          as Object;
    } on CCRouteParameterError {
      rethrow;
    } catch (error) {
      throw CCRouteParameterError(
        'Route "${location.routeId}" parameters are invalid: '
        '${error.runtimeType}.',
      );
    }
  }

  /// Resolves [location] to an active route allowed for external entry.
  CCRouteLocation resolve(String location, {bool external = false}) {
    final uri = _parseLocation(location);
    return _resolveUri(uri, external: external);
  }

  /// Encodes a typed [intent] through its route's canonical primary Pattern.
  _PreparedRoute prepareIntent<R>(
    CCRouteIntent<R> intent, {
    CCNavigationOrigin origin = CCNavigationOrigin.internal,
  }) {
    final route = _requireActiveRoute(intent.routeId);
    if (origin.isExternal &&
        route.definition.deepLink == CCDeepLinkPolicy.disabled) {
      throw CCRouteUnavailableError(intent.routeId);
    }
    late final CCEncodedRouteArguments encoded;
    try {
      encoded = route.definition.codec.encode(intent.arguments);
    } on CCRouteParameterError {
      rethrow;
    } catch (error) {
      throw CCRouteParameterError(
        'Route "${intent.routeId}" arguments could not be encoded: '
        '${error.runtimeType}.',
      );
    }
    final primary = route.definition.patterns.singleWhere(
      (pattern) => pattern.primary,
    );
    final uri = _generateUri(route.definition.routeId, primary, encoded);
    return _PreparedRoute(
      routeId: route.definition.routeId,
      ownerComponentId: route.ownerComponentId,
      uri: uri,
      arguments: intent.arguments,
      extra: encoded.extra,
      presentation: route.definition.presentation,
      placement: route.definition.placement,
      interceptorIds: route.definition.interceptorIds,
      popGuardIds: route.definition.popGuardIds,
    );
  }

  /// Resolves and decodes a dynamic [location] under its trusted [origin].
  _PreparedRoute prepareUri(Uri location, CCNavigationOrigin origin) {
    final uri = _parseLocation(location.toString());
    if (origin.isExternal) _validateDeepLinkIngress(uri);
    final resolved = _resolveUri(uri, external: origin.isExternal);
    final route = _requireActiveRoute(resolved.routeId);
    final arguments = decode(resolved);
    return _PreparedRoute(
      routeId: route.definition.routeId,
      ownerComponentId: route.ownerComponentId,
      uri: uri,
      arguments: arguments,
      extra: null,
      presentation: route.definition.presentation,
      placement: route.definition.placement,
      interceptorIds: route.definition.interceptorIds,
      popGuardIds: route.definition.popGuardIds,
    );
  }

  /// Rejects untrusted external authority data before any route can match it.
  void _validateDeepLinkIngress(Uri uri) {
    if (!uri.hasScheme && !uri.hasAuthority) {
      if (_deepLinkIngressPolicy.allowRelativePaths &&
          uri.path.startsWith('/')) {
        return;
      }
      throw const CCDeepLinkIngressRejectedError(
        CCDeepLinkIngressRejectionReason.relativePathNotAllowed,
      );
    }
    if (!uri.hasScheme ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const CCDeepLinkIngressRejectedError(
        CCDeepLinkIngressRejectionReason.invalidAuthority,
      );
    }
    for (final rule in _deepLinkIngressPolicy.allowedAuthorities) {
      final rulePort = Uri(
        scheme: rule.scheme,
        host: rule.host,
        port: rule.port,
      ).port;
      if (rule.scheme == uri.scheme.toLowerCase() &&
          rule.host == uri.host.toLowerCase() &&
          rulePort == uri.port) {
        return;
      }
    }
    throw const CCDeepLinkIngressRejectedError(
      CCDeepLinkIngressRejectionReason.authorityNotAllowed,
    );
  }

  /// Resolves one already parsed [uri] without depending on registration order.
  CCRouteLocation _resolveUri(Uri uri, {required bool external}) {
    final candidates = <_RouteCandidate>[];
    for (final route in _routes.values) {
      for (final pattern in route.definition.patterns) {
        final candidate = _matchPattern(route, pattern, uri);
        if (candidate != null) candidates.add(candidate);
      }
    }
    if (candidates.isEmpty) throw CCRouteNotFoundError(uri.path);
    candidates.sort(_compareCandidates);
    final selected = candidates.first;
    final ambiguous = candidates
        .takeWhile(
          (candidate) =>
              candidate.priority == selected.priority &&
              candidate.specificity == selected.specificity,
        )
        .toList();
    if (ambiguous.length > 1) {
      throw CCRouteAmbiguityError(
        ambiguous.map((candidate) => candidate.location.routeId),
      );
    }
    final route = _routes[selected.location.routeId]!;
    if (external && route.definition.deepLink == CCDeepLinkPolicy.disabled) {
      throw CCDeepLinkRejectedError(selected.location.routeId);
    }
    if (!route.active) {
      throw CCRouteUnavailableError(selected.location.routeId);
    }
    _shellRegistry.ensureRouteAvailable(
      selected.location.routeId,
      route.definition.placement,
    );
    return selected.location;
  }

  /// Verifies a generated Intent targets an installed active route.
  void checkIntent(CCRouteIntent<Object?> intent) {
    _requireActiveRoute(intent.routeId);
  }

  /// Returns an installed route definition for Runtime interceptor dispatch.
  CCRouteDefinition<dynamic, dynamic> routeDefinition(String routeId) =>
      _requireActiveRoute(routeId).definition;

  /// Returns the canonical template used by safe telemetry snapshots.
  String routePattern(String routeId) {
    final primary = retainedRouteDefinition(
      routeId,
    ).patterns.singleWhere((pattern) => pattern.primary);
    return switch (primary) {
      CCPathPattern(:final template) ||
      CCUriPattern(:final template) => template,
      CCRegexPattern(:final expression) => expression,
    };
  }

  /// Returns a canonical pattern only when [routeId] is registered.
  ///
  /// Diagnostic conversion uses this non-throwing lookup for foreign backend
  /// entries whose optional route ID is not owned by CCRouter.
  String? routePatternOrNull(String? routeId) {
    if (routeId == null || !_routes.containsKey(routeId)) return null;
    return routePattern(routeId);
  }

  /// Returns an installed definition even when new navigation is deactivated.
  ///
  /// Existing Route Entries still need their Pop policy while a component is
  /// inactive. This lookup never resolves a new request or bypasses placement
  /// checks and remains internal to retained-entry lifecycle handling.
  CCRouteDefinition<dynamic, dynamic> retainedRouteDefinition(String routeId) {
    final route = _routes[routeId];
    if (route == null) throw CCRouteNotFoundError(routeId);
    return route.definition;
  }

  /// Returns the installed active route identified by [routeId].
  _RegisteredRoute _requireActiveRoute(String routeId) {
    final route = _routes[routeId];
    if (route == null) throw CCRouteNotFoundError(routeId);
    if (!route.active) throw CCRouteUnavailableError(routeId);
    _shellRegistry.ensureRouteAvailable(routeId, route.definition.placement);
    return route;
  }

  /// Validates all route placements after every component has registered.
  void validatePlacements() {
    for (final route in _routes.values) {
      _shellRegistry.validateRoutePlacement(
        route.definition.routeId,
        route.definition.placement,
      );
    }
  }

  /// Validates interceptor existence and component-private ownership.
  ///
  /// An empty registered owner is accepted only for low-level Runtime tests.
  /// Production component routes must reference interceptors registered by the
  /// same component; shared application policies belong in the global layer.
  void validateInterceptors(Map<String, String> registeredOwners) {
    for (final route in _routes.values) {
      for (final id in route.definition.interceptorIds) {
        final interceptorOwner = registeredOwners[id];
        if (interceptorOwner == null) {
          throw CCRouteRegistrationError(
            'Route "${route.definition.routeId}" references unknown '
            'interceptor "$id".',
          );
        }
        if (interceptorOwner.isNotEmpty &&
            interceptorOwner != route.ownerComponentId) {
          throw CCRouteRegistrationError(
            'Route "${route.definition.routeId}" cannot reference '
            'interceptor "$id" owned by component "$interceptorOwner".',
          );
        }
      }
    }
  }

  /// Validates Pop guard existence and component-private ownership.
  ///
  /// Route-local guards belong to their route's component. Application-wide
  /// policies use host-provided global guards instead of cross-component IDs.
  void validatePopGuards(Map<String, String> registeredOwners) {
    for (final route in _routes.values) {
      for (final id in route.definition.popGuardIds) {
        final guardOwner = registeredOwners[id];
        if (guardOwner == null) {
          throw CCRouteRegistrationError(
            'Route "${route.definition.routeId}" references unknown '
            'Pop guard "$id".',
          );
        }
        if (guardOwner.isNotEmpty && guardOwner != route.ownerComponentId) {
          throw CCRouteRegistrationError(
            'Route "${route.definition.routeId}" cannot reference Pop guard '
            '"$id" owned by component "$guardOwner".',
          );
        }
      }
    }
  }

  /// Marks all routes owned by [componentId] unavailable.
  ///
  /// Component lifecycle orchestration uses this to reject new navigation; it
  /// does not remove existing RouteEntries or unload compiled Dart code.
  void deactivateComponent(String componentId) {
    for (final route in _routes.values) {
      if (route.ownerComponentId == componentId) route.active = false;
    }
  }

  /// Reactivates all routes owned by [componentId].
  ///
  /// Component lifecycle orchestration uses this after the component and its
  /// adapter bindings are ready to accept new navigation.
  void activateComponent(String componentId) {
    for (final route in _routes.values) {
      if (route.ownerComponentId == componentId) route.active = true;
    }
  }

  /// Validates route identity, canonical pattern, and expressions.
  void _validateDefinition<A, R>(CCRouteDefinition<A, R> definition) {
    final routeId = definition.routeId.trim();
    if (routeId.isEmpty) {
      throw const CCRouteRegistrationError('Route ID must not be empty.');
    }
    if (definition.patterns.isEmpty) {
      throw CCRouteRegistrationError('Route "$routeId" has no patterns.');
    }
    final primary = definition.patterns
        .where((pattern) => pattern.primary)
        .toList();
    if (primary.length != 1) {
      throw CCRouteRegistrationError(
        'Route "$routeId" must have exactly one primary pattern.',
      );
    }
    if (primary.single is CCRegexPattern) {
      throw CCRouteRegistrationError(
        'Route "$routeId" primary pattern must be reversible.',
      );
    }
    final interceptorIds = <String>{};
    for (final id in definition.interceptorIds) {
      final normalizedId = id.trim();
      if (normalizedId != id ||
          normalizedId.isEmpty ||
          !interceptorIds.add(normalizedId)) {
        throw CCRouteRegistrationError(
          'Route "$routeId" contains an empty or duplicate interceptor ID.',
        );
      }
    }
    final seen = <String>{};
    for (final pattern in definition.patterns) {
      _validatePattern(routeId, pattern);
      final key = _patternKey(pattern);
      if (!seen.add(key)) {
        throw CCRouteRegistrationError(
          'Route "$routeId" contains duplicate pattern '
          '"${_patternLabel(pattern)}".',
        );
      }
    }
  }

  /// Validates one concrete [pattern] and all expressions it contains.
  void _validatePattern(String routeId, CCRoutePattern pattern) {
    switch (pattern) {
      case CCPathPattern():
        _validatePathTemplate(
          routeId,
          pattern.template,
          pattern.constraints,
          kind: 'path',
        );
      case CCUriPattern():
        final uri = _parseUriPattern(routeId, pattern.template);
        _validatePathTemplate(
          routeId,
          uri.path.isEmpty ? '/' : uri.path,
          pattern.constraints,
          kind: 'URI path',
        );
      case CCRegexPattern():
        if (pattern.expression.isEmpty) {
          throw CCRouteRegistrationError(
            'Route "$routeId" regex must not be empty.',
          );
        }
        try {
          RegExp('^(?:${pattern.expression})\$');
        } on FormatException {
          throw CCRouteRegistrationError(
            'Route "$routeId" contains an invalid full regex.',
          );
        }
    }
  }

  /// Validates template syntax, parameter names, and segment constraints.
  void _validatePathTemplate(
    String routeId,
    String template,
    Map<String, String> constraints, {
    required String kind,
  }) {
    if (!template.startsWith('/')) {
      throw CCRouteRegistrationError(
        'Route "$routeId" $kind must start with "/".',
      );
    }
    if (template.contains('?') || template.contains('#')) {
      throw CCRouteRegistrationError(
        'Route "$routeId" $kind cannot contain Query or Fragment text.',
      );
    }
    late final List<String> segments;
    try {
      segments = _segments(template);
    } on FormatException {
      throw CCRouteRegistrationError(
        'Route "$routeId" contains an invalid $kind template.',
      );
    }
    final names = <String>{};
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (!segment.startsWith(':') && !segment.startsWith('*')) continue;
      final name = segment.substring(1);
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
        throw CCRouteRegistrationError(
          'Route "$routeId" contains invalid parameter "$name".',
        );
      }
      if (!names.add(name)) {
        throw CCRouteRegistrationError(
          'Route "$routeId" repeats parameter "$name".',
        );
      }
      if (segment.startsWith('*') && index != segments.length - 1) {
        throw CCRouteRegistrationError(
          'Route "$routeId" wildcard "$name" must be the final segment.',
        );
      }
    }
    for (final entry in constraints.entries) {
      if (!names.contains(entry.key)) {
        throw CCRouteRegistrationError(
          'Route "$routeId" constrains unknown parameter "${entry.key}".',
        );
      }
      try {
        RegExp('^(?:${entry.value})\$');
      } on FormatException {
        throw CCRouteRegistrationError(
          'Route "$routeId" has invalid regex for "${entry.key}".',
        );
      }
    }
  }

  /// Parses and validates one absolute structured URI pattern.
  Uri _parseUriPattern(String routeId, String template) {
    late final Uri uri;
    try {
      uri = Uri.parse(template);
    } on FormatException {
      throw CCRouteRegistrationError(
        'Route "$routeId" contains an invalid URI pattern.',
      );
    }
    if (!uri.hasScheme || !uri.hasAuthority || uri.host.isEmpty) {
      throw CCRouteRegistrationError(
        'Route "$routeId" URI pattern must contain a scheme and host.',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw CCRouteRegistrationError(
        'Route "$routeId" URI pattern cannot contain user-info.',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw CCRouteRegistrationError(
        'Route "$routeId" URI pattern cannot contain Query or Fragment text.',
      );
    }
    return uri;
  }

  /// Parses a slash path or URI and normalizes its empty path to `/`.
  Uri _parseLocation(String location) {
    try {
      if (location.isEmpty || location.trim() != location) {
        throw const FormatException();
      }
      final uri = Uri.parse(location);
      if (!uri.hasScheme && (!location.startsWith('/') || uri.hasAuthority)) {
        throw const FormatException();
      }
      return uri.path.isEmpty ? uri.replace(path: '/') : uri;
    } on FormatException {
      throw const CCRouteNotFoundError('/');
    }
  }

  /// Generates a canonical URI from [pattern] and encoded route arguments.
  Uri _generateUri(
    String routeId,
    CCRoutePattern pattern,
    CCEncodedRouteArguments encoded,
  ) {
    final template = switch (pattern) {
      CCPathPattern() => pattern.template,
      CCUriPattern() => Uri.parse(pattern.template).path,
      CCRegexPattern() => throw CCRouteParameterError(
        'Route "$routeId" cannot generate an address from a regex Pattern.',
      ),
    };
    final remaining = Map<String, String>.of(encoded.path);
    final generatedSegments = <String>[];
    for (final segment in _segments(template.isEmpty ? '/' : template)) {
      if (segment.startsWith(':')) {
        final name = segment.substring(1);
        final value = remaining.remove(name);
        if (value == null) {
          throw CCRouteParameterError(
            'Route "$routeId" is missing Path parameter "$name".',
          );
        }
        generatedSegments.add(value);
      } else if (segment.startsWith('*')) {
        final name = segment.substring(1);
        final value = remaining.remove(name);
        if (value == null) {
          throw CCRouteParameterError(
            'Route "$routeId" is missing wildcard parameter "$name".',
          );
        }
        if (value.isNotEmpty) generatedSegments.addAll(value.split('/'));
      } else {
        generatedSegments.add(segment);
      }
    }
    if (remaining.isNotEmpty) {
      final names = remaining.keys.toList()..sort();
      throw CCRouteParameterError(
        'Route "$routeId" encoded unknown Path parameters: '
        '${names.join(', ')}.',
      );
    }

    final query = _queryForUri(encoded.query);
    final uri = switch (pattern) {
      CCPathPattern() =>
        generatedSegments.isEmpty
            ? Uri(path: '/', queryParameters: query)
            : Uri(
                pathSegments: ['', ...generatedSegments],
                queryParameters: query,
              ),
      CCUriPattern() => _generateStructuredUri(
        Uri.parse(pattern.template),
        generatedSegments,
        query,
      ),
      CCRegexPattern() => throw StateError('Regex Pattern cannot be primary.'),
    };
    final match = switch (pattern) {
      CCPathPattern() => _matchTemplate(
        pattern.template,
        pattern.constraints,
        uri.pathSegments,
      ),
      CCUriPattern() => _matchUri(pattern, uri),
      CCRegexPattern() => null,
    };
    if (match == null) {
      throw CCRouteParameterError(
        'Route "$routeId" encoded Path parameters violate its primary Pattern.',
      );
    }
    return uri;
  }

  /// Builds an absolute URI while preserving explicit authority semantics.
  Uri _generateStructuredUri(
    Uri template,
    List<String> pathSegments,
    Map<String, Object>? query,
  ) => Uri(
    scheme: template.scheme,
    host: template.host,
    port: template.hasPort ? template.port : null,
    pathSegments: pathSegments,
    queryParameters: query,
  );

  /// Converts repeated Codec Query values to values accepted by [Uri].
  Map<String, Object>? _queryForUri(Map<String, List<String>> query) {
    if (query.isEmpty) return null;
    return query.map(
      (key, values) => MapEntry<String, Object>(
        key,
        values.length == 1 ? values.single : List<String>.of(values),
      ),
    );
  }

  /// Dispatches [pattern] to its structural or regular-expression matcher.
  _RouteCandidate? _matchPattern(
    _RegisteredRoute route,
    CCRoutePattern pattern,
    Uri uri,
  ) {
    late final _PatternMatch? match;
    late final int priority;
    switch (pattern) {
      case CCPathPattern():
        priority = _pathPriority;
        match = _matchTemplate(
          pattern.template,
          pattern.constraints,
          uri.pathSegments,
        );
      case CCUriPattern():
        priority = _uriPriority;
        match = _matchUri(pattern, uri);
      case CCRegexPattern():
        priority = _regexPriority;
        match = _matchRegex(pattern, uri);
    }
    if (match == null) return null;
    return _RouteCandidate(
      location: CCRouteLocation(
        routeId: route.definition.routeId,
        pathParameters: match.pathParameters,
        queryParameters: _queryParameters(uri),
      ),
      priority: priority,
      specificity: match.specificity,
    );
  }

  /// Matches an absolute [uri] against scheme, authority, port, and path.
  _PatternMatch? _matchUri(CCUriPattern pattern, Uri uri) {
    if (!uri.hasScheme ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final template = Uri.parse(pattern.template);
    if (template.scheme.toLowerCase() != uri.scheme.toLowerCase() ||
        template.host.toLowerCase() != uri.host.toLowerCase() ||
        template.port != uri.port) {
      return null;
    }
    return _matchTemplate(
      template.path.isEmpty ? '/' : template.path,
      pattern.constraints,
      uri.pathSegments,
    );
  }

  /// Full-matches the encoded [uri] and decodes each named capture once.
  ///
  /// Matching retains percent-encoded separators so `%2F` cannot change the
  /// route structure before a Pattern accepts it. Captures are decoded only
  /// after the full match so every route codec receives the same value
  /// semantics as structural Path and URI Patterns. A capture that splits an
  /// encoded code point is treated as a non-match instead of exposing a raw
  /// decoder failure.
  _PatternMatch? _matchRegex(CCRegexPattern pattern, Uri uri) {
    final target = _locationWithoutQueryOrFragment(uri);
    final match = RegExp('^(?:${pattern.expression})\$').firstMatch(target);
    if (match == null) return null;
    final parameters = <String, String>{};
    for (final name in match.groupNames) {
      final value = match.namedGroup(name);
      if (value == null) continue;
      try {
        parameters[name] = Uri.decodeComponent(value);
      } on FormatException {
        return null;
      }
    }
    return _PatternMatch(pathParameters: parameters, specificity: 0);
  }

  /// Rebuilds [uri] without Query or Fragment for full regex matching.
  String _locationWithoutQueryOrFragment(Uri uri) {
    if (uri.hasAuthority) {
      return Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString();
    }
    if (uri.hasScheme) {
      return Uri(scheme: uri.scheme, path: uri.path).toString();
    }
    return Uri(path: uri.path).toString();
  }

  /// Matches decoded [actual] segments against one path [template].
  _PatternMatch? _matchTemplate(
    String template,
    Map<String, String> constraints,
    List<String> actual,
  ) {
    final pattern = _segments(template);
    final parameters = <String, String>{};
    var specificity = 0;
    var actualIndex = 0;
    for (final segment in pattern) {
      if (segment.startsWith('*')) {
        final name = segment.substring(1);
        final value = actual.sublist(actualIndex).join('/');
        if (!_matchesConstraint(constraints[name], value)) return null;
        parameters[name] = value;
        specificity -= 10;
        actualIndex = actual.length;
        break;
      }
      if (actualIndex >= actual.length) return null;
      final value = actual[actualIndex++];
      if (segment.startsWith(':')) {
        final name = segment.substring(1);
        final expression = constraints[name];
        if (!_matchesConstraint(expression, value)) return null;
        parameters[name] = value;
        specificity += expression == null ? 10 : 20;
      } else {
        if (segment != value) return null;
        specificity += 100;
      }
    }
    if (actualIndex != actual.length) return null;
    return _PatternMatch(pathParameters: parameters, specificity: specificity);
  }

  /// Returns immutable repeated Query values decoded by [uri].
  Map<String, List<String>> _queryParameters(Uri uri) {
    final query = <String, List<String>>{};
    for (final entry in uri.queryParametersAll.entries) {
      query[entry.key] = List<String>.unmodifiable(entry.value);
    }
    return query;
  }

  /// Compares candidates by fixed tier and then template specificity.
  int _compareCandidates(_RouteCandidate first, _RouteCandidate second) {
    final priority = second.priority.compareTo(first.priority);
    if (priority != 0) return priority;
    return second.specificity.compareTo(first.specificity);
  }

  /// Splits and decodes a slash template into non-empty path segments.
  List<String> _segments(String template) => Uri.parse(template).pathSegments;

  /// Whether [value] satisfies an optional full segment constraint.
  bool _matchesConstraint(String? expression, String value) =>
      expression == null || RegExp('^(?:$expression)\$').hasMatch(value);

  /// Creates a stable equality key for duplicate-pattern validation.
  String _patternKey(CCRoutePattern pattern) {
    final constraints = switch (pattern) {
      CCPathPattern() => pattern.constraints,
      CCUriPattern() => pattern.constraints,
      CCRegexPattern() => const <String, String>{},
    };
    final constraintEntries = constraints.entries.toList()
      ..sort((first, second) => first.key.compareTo(second.key));
    final constraintKey = constraintEntries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    return switch (pattern) {
      CCPathPattern() => 'path|${pattern.template}|$constraintKey',
      CCUriPattern() => _uriPatternKey(pattern, constraintKey),
      CCRegexPattern() => 'regex|${pattern.expression}',
    };
  }

  /// Creates a normalized key for a validated structured URI [pattern].
  String _uriPatternKey(CCUriPattern pattern, String constraintKey) {
    final uri = Uri.parse(pattern.template);
    return 'uri|${uri.scheme.toLowerCase()}|${uri.host.toLowerCase()}|'
        '${uri.port}|${uri.path}|$constraintKey';
  }

  /// Returns a concise pattern value suitable for registration diagnostics.
  String _patternLabel(CCRoutePattern pattern) => switch (pattern) {
    CCPathPattern() => pattern.template,
    CCUriPattern() => pattern.template,
    CCRegexPattern() => pattern.expression,
  };

  /// Whether two same-tier patterns can tie for at least one location.
  bool _patternsConflict(CCRoutePattern first, CCRoutePattern second) {
    if (first is CCRegexPattern && second is CCRegexPattern) {
      return first.expression == second.expression;
    }
    if (first is CCPathPattern && second is CCPathPattern) {
      return _templatesConflict(
        first.template,
        first.constraints,
        second.template,
        second.constraints,
      );
    }
    if (first is CCUriPattern && second is CCUriPattern) {
      final firstUri = Uri.parse(first.template);
      final secondUri = Uri.parse(second.template);
      if (firstUri.scheme.toLowerCase() != secondUri.scheme.toLowerCase() ||
          firstUri.host.toLowerCase() != secondUri.host.toLowerCase() ||
          firstUri.port != secondUri.port) {
        return false;
      }
      return _templatesConflict(
        firstUri.path.isEmpty ? '/' : firstUri.path,
        first.constraints,
        secondUri.path.isEmpty ? '/' : secondUri.path,
        second.constraints,
      );
    }
    return false;
  }

  /// Whether two templates can match one path with equal specificity.
  bool _templatesConflict(
    String firstTemplate,
    Map<String, String> firstConstraints,
    String secondTemplate,
    Map<String, String> secondConstraints,
  ) {
    final first = _segments(firstTemplate);
    final second = _segments(secondTemplate);
    final firstHasWildcard = first.isNotEmpty && first.last.startsWith('*');
    final secondHasWildcard = second.isNotEmpty && second.last.startsWith('*');
    if (!firstHasWildcard &&
        !secondHasWildcard &&
        first.length != second.length) {
      return false;
    }
    final comparedLength = min(first.length, second.length);
    for (var index = 0; index < comparedLength; index++) {
      final firstSegment = first[index];
      final secondSegment = second[index];
      if (firstSegment.startsWith('*') || secondSegment.startsWith('*')) break;
      final firstExpression = _segmentExpression(
        firstSegment,
        firstConstraints,
      );
      final secondExpression = _segmentExpression(
        secondSegment,
        secondConstraints,
      );
      if (firstExpression == null && secondExpression == null) {
        if (firstSegment != secondSegment) return false;
      } else if (firstExpression == null) {
        if (!_matchesConstraint(secondExpression, firstSegment)) return false;
      } else if (secondExpression == null) {
        if (!_matchesConstraint(firstExpression, secondSegment)) return false;
      }
    }
    return _templateSpecificity(first, firstConstraints) ==
        _templateSpecificity(second, secondConstraints);
  }

  /// Returns the regular expression for a dynamic segment, or null if static.
  String? _segmentExpression(String segment, Map<String, String> constraints) {
    if (segment.startsWith('*')) {
      return constraints[segment.substring(1)] ?? r'.*';
    }
    if (!segment.startsWith(':')) return null;
    return constraints[segment.substring(1)] ?? r'[^/]+';
  }

  /// Calculates the same specificity used by the runtime template matcher.
  int _templateSpecificity(
    List<String> segments,
    Map<String, String> constraints,
  ) {
    var score = 0;
    for (final segment in segments) {
      if (segment.startsWith('*')) {
        score -= 10;
      } else if (segment.startsWith(':')) {
        score += constraints.containsKey(segment.substring(1)) ? 20 : 10;
      } else {
        score += 100;
      }
    }
    return score;
  }
}
