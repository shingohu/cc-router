import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:meta/meta.dart';

part 'component.dart';
part 'diagnostics.dart';
part 'initialization.dart';
part 'memory_navigation_adapter.dart';
part 'navigation.dart';
part 'navigation_aspect.dart';
part 'navigation_backend.dart';
part 'navigation_callback.dart';
part 'navigation_capability_diagnostics.dart';
part 'navigation_concurrency.dart';
part 'navigation_diagnostics.dart';
part 'navigation_failure.dart';
part 'navigation_lifecycle.dart';
part 'navigation_pending.dart';
part 'navigation_pop_guard.dart';
part 'navigation_restoration_diagnostics.dart';
part 'registry.dart';
part 'route.dart';
part 'route_entry.dart';
part 'route_visibility.dart';
part 'runtime_host.dart';
part 'session.dart';
part 'shell.dart';
part 'scope.dart';

/// Maximum length accepted for framework-owned stable identifiers.
const int _maxStableIdentifierLength = 128;

/// Maximum length accepted for caller-provided telemetry attribution IDs.
const int _maxTelemetryIdentifierLength = 64;

/// Maximum length accepted for full route regular expressions.
const int _maxRouteRegularExpressionLength = 2048;

/// Maximum named captures accepted in one full route expression.
const int _maxRouteRegularExpressionCaptures = 32;

/// Maximum length accepted for one path-parameter constraint.
const int _maxConstraintRegularExpressionLength = 256;

/// Stable identifier syntax used at handwritten Runtime boundaries.
final RegExp _stableIdentifierPattern = RegExp(
  r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$',
);

/// Opaque analytics syntax that accepts UUID-style leading digits.
final RegExp _anonymousTelemetryIdentifierPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]*$',
);

/// Lowercase package-style syntax retained for component ownership IDs.
final RegExp _componentIdentifierPattern = RegExp(
  r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$',
);

/// Full SemVer 2.0 syntax used by handwritten component manifests.
final RegExp _semanticVersionPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)'
  r'(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

/// Whether [value] is a bounded stable identifier accepted by Runtime.
bool _isStableIdentifier(String value) =>
    value.length <= _maxStableIdentifierLength &&
    _stableIdentifierPattern.hasMatch(value);

/// Whether [value] is a bounded stable product navigation source ID.
bool _isNavigationSourceIdentifier(String value) =>
    value.length <= _maxTelemetryIdentifierLength &&
    _stableIdentifierPattern.hasMatch(value);

/// Whether [value] is a bounded opaque analytics correlation ID.
bool _isAnonymousTelemetryIdentifier(String value) =>
    value.length <= _maxTelemetryIdentifierLength &&
    _anonymousTelemetryIdentifierPattern.hasMatch(value);

/// Whether [value] can identify a component in generated Package metadata.
bool _isComponentIdentifier(String value) =>
    value.length <= _maxStableIdentifierLength &&
    _componentIdentifierPattern.hasMatch(value);
