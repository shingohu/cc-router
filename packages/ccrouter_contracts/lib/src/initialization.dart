import 'component.dart';

/// Identifies an explicit condition that allows initialization tasks to run.
///
/// Use [appStarted] for ordinary startup work and [privacyGranted] for work
/// that must wait until the user has granted privacy consent. A Host may define
/// another constant gate for a stable product condition and opens it explicitly.
final class CCInitializationGate {
  /// Creates a gate identified by the stable [id].
  const CCInitializationGate(this.id);

  /// Gate used for ordinary post-`CCRouter.initialize` startup work.
  static const CCInitializationGate appStarted = CCInitializationGate(
    'appStarted',
  );

  /// Gate opened explicitly by the Host after privacy consent is granted.
  ///
  /// CCRouter does not read, persist, or infer consent. Tasks remain pending
  /// until the application opens this gate.
  static const CCInitializationGate privacyGranted = CCInitializationGate(
    'privacyGranted',
  );

  /// Stable identity used by generation, diagnostics, and execution.
  final String id;

  /// Compares gates by stable identity rather than object identity.
  @override
  bool operator ==(Object other) =>
      other is CCInitializationGate && other.id == id;

  /// Hashes the stable gate identity.
  @override
  int get hashCode => id.hashCode;
}

/// Defines whether one initialization failure aborts its execution phase.
enum CCInitializationFailurePolicy {
  /// Reports a sanitized error and prevents later initialization progress.
  critical,

  /// Records failure while allowing independent tasks to continue.
  optional,
}

/// Declares a stable initialization task identity that other tasks may depend on.
///
/// Keep a component-local constant private unless another Package genuinely
/// depends on it. A contracts Package must provide [componentId] and export the
/// constant through a public barrel.
final class CCInitTaskContract {
  /// Creates one immutable task contract.
  const CCInitTaskContract({
    required this.id,
    this.componentId,
    this.description = '',
  });

  /// Globally stable task identity used by the DAG and diagnostics.
  final String id;

  /// Component that owns the task, or null for local owner inference.
  final CCComponentId? componentId;

  /// Human-readable purpose and usage scenario exported to generated docs.
  final String description;
}

/// Marks one public top-level function as a generated initialization task.
///
/// Set exactly one of [contract] and [id]. Use [contract] when another task or
/// Package needs a typed dependency; use [id] for an independent internal task.
/// The function may accept no arguments or one invocation context and must
/// return `void`, `Future<void>`, or `FutureOr<void>`.
final class CCInitTask {
  /// Creates one static task declaration consumed by the generator.
  const CCInitTask({
    this.contract,
    this.id,
    this.dependsOn = const [],
    this.gate = CCInitializationGate.appStarted,
    this.failurePolicy = CCInitializationFailurePolicy.critical,
    this.timeout,
  });

  /// Typed task identity used for shared or dependency-target tasks.
  final CCInitTaskContract? contract;

  /// Stable identity for an independent component-internal task.
  final String? id;

  /// Typed tasks that must succeed before this task may run.
  final List<CCInitTaskContract> dependsOn;

  /// Explicit condition that must be opened before execution.
  final CCInitializationGate gate;

  /// Behavior applied when this task fails.
  final CCInitializationFailurePolicy failurePolicy;

  /// Optional positive deadline measured from actual task start.
  final Duration? timeout;
}
