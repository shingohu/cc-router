import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter/widgets.dart';

/// Sanitized UI composition failure; never retains Props or callback values.
final class CCUIFragmentError implements Exception {
  /// Creates a stable code associated only with a declared capability identity.
  const CCUIFragmentError(this.code, this.contractId);

  /// Stable UI-only failure code, independent of the five Core Contract kinds.
  final String code;

  /// Declared contract identifier; no runtime business payload.
  final String contractId;

  /// Reports only the safe failure code and declared capability identity.
  @override
  String toString() => 'CCUIFragmentError($code, $contractId)';
}

/// Payload-free local UI diagnostic; contains only generated identity and code.
final class CCUIDiagnostic {
  /// Created only at framework lifecycle boundaries.
  const CCUIDiagnostic._(this.code, this.contractId);

  /// Stable lifecycle or ignored-action reason.
  final String code;

  /// Generated contract ID; never a Props-derived label.
  final String contractId;
}

/// Small diagnostic ring; it never owns Widget or callback references.
final _uiDiagnostics = <CCUIDiagnostic>[];

/// Retains at most 128 safe boundary summaries, with no per-frame build events.
void _record(String code, String contractId) {
  if (_uiDiagnostics.length == 128) _uiDiagnostics.removeAt(0);
  _uiDiagnostics.add(CCUIDiagnostic._(code, contractId));
}

/// Current immutable inputs passed to a synchronous Widget factory.
final class CCUIFragmentRenderInput<P extends Object, A extends Object> {
  /// Supplies one render snapshot; resources belong in the returned State.
  const CCUIFragmentRenderInput({
    required this.props,
    required this.onAction,
    required this.active,
  });

  /// Immutable business input; update by supplying new Props to the Client.
  final P props;

  /// Instance-local action sink guarded by mount, activity and generation.
  final ValueChanged<A> onAction;

  /// Host activity permission, not pixel visibility or a security decision.
  final bool active;
}

/// Generated public schema identity; contains no Flutter or business instances.
final class CCUIFragmentDescriptor {
  /// Captures a verified version and complete DTO/Action shape fingerprint.
  const CCUIFragmentDescriptor({
    required this.owner,
    required this.id,
    required this.version,
    required this.fingerprint,
  });

  /// Canonical owning component ID.
  final String owner;

  /// Owner-local capability ID.
  final String id;

  /// Contract SemVer, distinct from component version.
  final String version;

  /// Generated SHA-256 shape including fields and enum members.
  final String fingerprint;

  /// Internal composite identity; keys do not contain Props.
  String get identity => '$owner/$id';
}

/// One generated, required consumer edge in the UI composition graph.
final class CCUIFragmentRequirement {
  /// Records the consumer's schema snapshot and accepted version range.
  const CCUIFragmentRequirement({
    required this.consumer,
    required this.contract,
    required this.versionRange,
  });

  /// Component whose generated Client is authorized for this edge.
  final String consumer;

  /// Exact public shape observed during consumer generation.
  final CCUIFragmentDescriptor contract;

  /// Explicit compatible versions accepted by the consumer.
  final String versionRange;
}

/// Generated erased catalog boundary; construction stays typed in [CCUIRenderer].
abstract interface class CCUIFragmentContribution {
  /// Public schema provided by this factory.
  CCUIFragmentDescriptor get contract;

  /// Tests the generated Props and Action type pair without reflective lookup.
  bool accepts<P extends Object, A extends Object>();

  /// Builds a Widget from one correctly typed render snapshot.
  Widget build(Object input);
}

/// Typed generated adapter for one owner-owned synchronous Renderer.
final class CCUIRenderer<P extends Object, A extends Object>
    implements CCUIFragmentContribution {
  /// Keeps only a top-level factory and schema, never a built Widget or Context.
  const CCUIRenderer({required this.contract, required this.renderer});

  /// Schema installed alongside this typed factory at the Host boundary.
  @override
  final CCUIFragmentDescriptor contract;

  /// Stateless construction callback; the returned State owns resources.
  final Widget Function(CCUIFragmentRenderInput<P, A>) renderer;

  /// Requires the exact generated type pair before erasing render inputs.
  @override
  bool accepts<X extends Object, Y extends Object>() => X == P && Y == A;

  /// Rejects mismatched generated glue before invoking the owner factory.
  @override
  Widget build(Object input) {
    if (input is! CCUIFragmentRenderInput<P, A>) {
      throw CCUIFragmentError('rendererSignatureMismatch', contract.id);
    }
    return renderer(input);
  }
}

/// Composition Root wrapper keeping Flutter factory payloads outside Core.
abstract final class CCUIHostAssembly {
  /// Bounded read-only diagnostic snapshot for the Composition Root.
  static List<CCUIDiagnostic> get diagnostics =>
      List.unmodifiable(_uiDiagnostics);

  /// Validates all edges atomically and adds one Host lifecycle binding.
  ///
  /// Call only from generated Host assembly or a focused handwritten test.
  /// Registration is static. Duplicate implementations, missing owners and
  /// incompatible required edges fail before Runtime initialization.
  static CCHostAssembly attach(
    CCHostAssembly assembly, {
    required Iterable<CCUIFragmentContribution> contributions,
    required Iterable<CCUIFragmentRequirement> requirements,
  }) {
    final components = {
      for (final component in assembly.componentManifests)
        component.id: component,
    };
    final renderers = <String, CCUIFragmentContribution>{};
    for (final contribution in contributions) {
      final contract = contribution.contract;
      _validateDescriptor(contract);
      if (!components.containsKey(contract.owner)) {
        throw CCUIFragmentError('ownerMismatch', contract.id);
      }
      if (renderers.containsKey(contract.identity)) {
        throw CCUIFragmentError('duplicateImplementation', contract.id);
      }
      renderers[contract.identity] = contribution;
    }
    final edges = <String, CCUIFragmentRequirement>{};
    for (final requirement in requirements) {
      final expected = requirement.contract;
      _validateDescriptor(expected);
      final consumer = components[requirement.consumer];
      if (consumer == null ||
          !consumer.dependencies.contains(expected.owner) ||
          consumer.id == expected.owner) {
        throw CCUIFragmentError('dependencyMissing', expected.id);
      }
      final actual = renderers[expected.identity]?.contract;
      if (actual == null) {
        throw CCUIFragmentError('missingImplementation', expected.id);
      }
      if (!CCContractVersionRange.parse(
        requirement.versionRange,
      ).allows(CCSemVer.parse(actual.version))) {
        throw CCUIFragmentError('versionOutOfRange', expected.id);
      }
      if (expected.fingerprint != actual.fingerprint) {
        throw CCUIFragmentError('fingerprintChanged', expected.id);
      }
      final edge = '${requirement.consumer}/${expected.identity}';
      final previous = edges[edge];
      if (previous != null &&
          (previous.contract.fingerprint != expected.fingerprint ||
              previous.versionRange != requirement.versionRange)) {
        throw CCUIFragmentError('staleGeneratedOutput', expected.id);
      }
      edges[edge] = requirement;
    }
    return CCHostAssembly.withLifecycleBindings(assembly, [
      _UIBinding(Map.unmodifiable(renderers), Map.unmodifiable(edges)),
    ]);
  }
}

/// Rejects malformed generated SPI at the Host boundary without payload logs.
void _validateDescriptor(CCUIFragmentDescriptor contract) {
  final id = RegExp(r'^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$');
  if (!id.hasMatch(contract.id) ||
      !id.hasMatch(contract.owner) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(contract.fingerprint)) {
    throw CCUIFragmentError('staleGeneratedOutput', contract.id);
  }
  CCSemVer.parse(contract.version);
}

/// Current process-default UI generation; no instances or callbacks retained.
_UICatalog? _activeCatalog;

/// Immutable factory snapshot plus a terminal generation validity flag.
final class _UICatalog {
  /// Takes lifecycle-local copies so detaching can release factory references.
  _UICatalog(this.renderers, this.requirements);

  /// Live factories, released when this generation stops.
  Map<String, CCUIFragmentContribution> renderers;

  /// Required edges used to revalidate generated Client identity on every build.
  Map<String, CCUIFragmentRequirement> requirements;

  /// Terminal once invalidated; never revived on reinitialization.
  bool valid = true;
}

/// Host-owned factory plan; each attach creates a new, non-revivable generation.
final class _UIBinding implements CCHostLifecycleBinding {
  /// Stores validated, instance-free static inputs.
  _UIBinding(this.renderers, this.requirements);

  /// Immutable factories retained by the application-owned Assembly.
  final Map<String, CCUIFragmentContribution> renderers;

  /// Immutable required edges retained by the Assembly.
  final Map<String, CCUIFragmentRequirement> requirements;

  /// This binding's active generation, never another binding's global state.
  _UICatalog? _catalog;

  /// Reserves one UI catalog binding per default Host assembly.
  @override
  String get id => 'ccrouter.ui';

  /// Installs a fresh generation without retaining any mounted instance.
  @override
  void attach() {
    if (_activeCatalog != null || _catalog != null) {
      throw const CCUIFragmentError('runtimeUnavailable', 'ccrouter.ui');
    }
    _activeCatalog = _catalog = _UICatalog(renderers, requirements);
    _record('attached', 'ccrouter.ui');
  }

  /// Invalidates callbacks immediately and releases generation factory maps.
  @override
  void detach() {
    final catalog = _catalog;
    _catalog = null;
    if (catalog == null) return;
    catalog.valid = false;
    catalog.renderers = const {};
    catalog.requirements = const {};
    if (identical(_activeCatalog, catalog)) _activeCatalog = null;
    _record('detached', 'ccrouter.ui');
  }
}

/// Generated-only managed Widget preserving normal Flutter identity semantics.
final class CCUIGeneratedFragment<P extends Object, A extends Object>
    extends StatefulWidget {
  /// Captures one current input; call through the consumer's generated Client.
  const CCUIGeneratedFragment({
    required this.requirement,
    required this.props,
    required this.onAction,
    this.active = true,
    super.key,
  });

  /// Trusted generated consumer and schema snapshot, revalidated at lookup.
  final CCUIFragmentRequirement requirement;

  /// Current immutable data passed to the owner Renderer.
  final P props;

  /// Latest consumer callback; never put into the global catalog.
  final ValueChanged<A> onAction;

  /// Whether this instance is currently permitted to emit actions.
  final bool active;

  /// Gives each Flutter mount its own action guard and captured generation.
  @override
  State<CCUIGeneratedFragment<P, A>> createState() => _FragmentState<P, A>();
}

/// Revocable action forwarding that never retains the Fragment State or Widget.
///
/// A Renderer may temporarily retain this sink through asynchronous work. After
/// revocation it keeps only schema/generation data, never Props or the consumer.
final class _FragmentActionSink<A extends Object> {
  /// Binds delivery to one installed catalog and capability identity.
  _FragmentActionSink(this._catalog, this._contractId);

  /// Catalog generation captured at mount; invalidated by Host shutdown.
  final _UICatalog _catalog;

  /// Payload-free identity used for ignored-action diagnostics.
  final String _contractId;

  /// Latest consumer callback, cleared at the exact unmount/identity boundary.
  ValueChanged<A>? _callback;

  /// Current Host activity permission; hiding does not dispose the instance.
  bool _active = false;

  /// Refreshes delivery without forcing retained Renderer callbacks to rebuild.
  void update(ValueChanged<A> callback, bool active) {
    _callback = callback;
    _active = active;
  }

  /// Makes old sinks inert and releases their reference to the consumer.
  void revoke() {
    _callback = null;
    _active = false;
  }

  /// Forwards only while this exact mounted identity and generation are active.
  void emit(A action) {
    final callback = _callback;
    if (callback == null ||
        !_active ||
        !_catalog.valid ||
        !identical(_activeCatalog, _catalog)) {
      _record('actionIgnored', _contractId);
      return;
    }
    callback(action);
  }
}

/// One Flutter instance; no RouteEntry, Scope or global instance registration.
final class _FragmentState<P extends Object, A extends Object>
    extends State<CCUIGeneratedFragment<P, A>> {
  /// Captured generation prevents old callbacks from targeting a new Runtime.
  _UICatalog? _generation;

  /// Current revocable identity, shared only by callbacks for this capability.
  _FragmentActionSink<A>? _actions;

  /// Revokes earlier callbacks if a reused element changes capability identity.
  @override
  void didUpdateWidget(CCUIGeneratedFragment<P, A> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requirement.consumer != widget.requirement.consumer ||
        oldWidget.requirement.contract.identity !=
            widget.requirement.contract.identity) {
      _actions?.revoke();
      _actions = null;
    } else {
      _actions?.update(widget.onAction, widget.active);
    }
  }

  /// Revalidates generated identity and forwards only this instance's snapshot.
  @override
  Widget build(BuildContext context) {
    final catalog = _activeCatalog;
    final expected = widget.requirement;
    final contract = expected.contract;
    if (catalog == null || !catalog.valid) {
      throw CCUIFragmentError('runtimeUnavailable', contract.id);
    }
    if (_generation != null && !identical(_generation, catalog)) {
      // A new Runtime requires an explicit subtree remount by the Host.
      throw CCUIFragmentError('runtimeGenerationMismatch', contract.id);
    }
    if (_generation == null) _record('mounted', contract.id);
    _generation = catalog;
    final installed =
        catalog.requirements['${expected.consumer}/${contract.identity}'];
    if (installed == null) {
      throw CCUIFragmentError('dependencyMissing', contract.id);
    }
    if (installed.contract.fingerprint != contract.fingerprint ||
        installed.contract.version != contract.version ||
        installed.versionRange != expected.versionRange) {
      throw CCUIFragmentError('staleGeneratedOutput', contract.id);
    }
    final renderer = catalog.renderers[contract.identity]!;
    if (!renderer.accepts<P, A>()) {
      throw CCUIFragmentError('rendererSignatureMismatch', contract.id);
    }
    final actions = _actions ??= _FragmentActionSink<A>(catalog, contract.id);
    actions.update(widget.onAction, widget.active);
    return KeyedSubtree(
      key: ValueKey('${expected.consumer}/${contract.identity}'),
      child: renderer.build(
        CCUIFragmentRenderInput<P, A>(
          props: widget.props,
          active: widget.active,
          onAction: actions.emit,
        ),
      ),
    );
  }

  /// Revokes retained action sinks and releases their consumer references.
  @override
  void dispose() {
    _record('unmounted', widget.requirement.contract.id);
    _actions?.revoke();
    _actions = null;
    _generation = null;
    super.dispose();
  }
}
