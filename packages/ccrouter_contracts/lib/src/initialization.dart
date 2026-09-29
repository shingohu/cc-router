import 'component.dart';

/// Identifies an explicit condition that allows InitTasks to run.
///
/// Use [appStarted] for ordinary startup work and [privacyGranted] for work
/// that must wait until the user has granted privacy consent. A Host may define
/// another constant gate for a stable product condition and opens it explicitly.
final class CCInitTaskGate {
  /// Creates a gate identified by the stable [id].
  const CCInitTaskGate(this.id);

  /// Gate used for ordinary post-`CCRouter.initialize` startup work.
  static const CCInitTaskGate appStarted = CCInitTaskGate('appStarted');

  /// Gate opened explicitly by the Host after privacy consent is granted.
  ///
  /// CCRouter does not read, persist, or infer consent. Tasks remain pending
  /// until the application opens this gate.
  static const CCInitTaskGate privacyGranted = CCInitTaskGate('privacyGranted');

  /// Stable identity used by generation, diagnostics, and execution.
  final String id;

  /// Compares gates by stable identity rather than object identity.
  @override
  bool operator ==(Object other) => other is CCInitTaskGate && other.id == id;

  /// Hashes the stable gate identity.
  @override
  int get hashCode => id.hashCode;
}

/// Defines how one InitTask failure is classified for startup decisions.
enum CCInitTaskFailurePolicy {
  /// Marks a capability as required for the Host's intended startup mode.
  ///
  /// Runtime records the failure and skips only dependent tasks. It does not
  /// throw the business failure from `runInitTasks`; a Host that intentionally
  /// uses fail-fast startup calls `CCInitTaskRunResult.throwIfRequiredFailed`.
  required,

  /// Records failure while allowing independent tasks to continue.
  optional,
}

/// Declares a stable InitTask identity that other tasks may depend on.
///
/// Keep a component-local constant private unless another Package genuinely
/// depends on it. A contracts Package must provide [componentId] and export the
/// constant through a public barrel.
final class CCInitTaskContract {
  /// Creates one immutable task contract.
  const CCInitTaskContract({
    required this.id,
    this.componentId,
    this.version = '0.1.0',
    this.description = '',
  });

  /// Globally stable task identity used by the DAG and diagnostics.
  final String id;

  /// Independent InitTask Contract SemVer used by dependent tasks.
  final String version;

  /// Component that owns the task, or null for local owner inference.
  final CCComponentId? componentId;

  /// Human-readable purpose and usage scenario exported to generated docs.
  final String description;
}

/// Marks one public top-level function as a generated InitTask.
///
/// Set exactly one of [contract] and [id]. Use [contract] when another task or
/// Package needs a typed dependency; use [id] for an independent internal task.
/// [gate] and [failurePolicy] are always explicit so execution timing and
/// startup degradation cannot change when framework defaults evolve. A
/// required task must use [contract], and an asynchronous required Handler must
/// declare a positive [timeout].
/// The function may accept no arguments or one invocation context and must
/// return `void`, `Future<void>`, or `FutureOr<void>`.
final class CCInitTask {
  /// Creates one static task declaration consumed by the generator.
  const CCInitTask({
    this.contract,
    this.id,
    this.dependsOn = const [],
    required this.gate,
    required this.failurePolicy,
    this.timeout,
  });

  /// Typed task identity used for shared or dependency-target tasks.
  final CCInitTaskContract? contract;

  /// Stable identity for an independent component-internal task.
  final String? id;

  /// Typed tasks that must succeed before this task may run.
  final List<CCInitTaskContract> dependsOn;

  /// Explicit condition that must be opened before execution.
  ///
  /// Use [CCInitTaskGate.appStarted] for ordinary startup work. The annotation
  /// intentionally has no default so every declaration exposes its timing.
  final CCInitTaskGate gate;

  /// Required or optional classification applied when this task fails.
  final CCInitTaskFailurePolicy failurePolicy;

  /// Optional positive deadline measured from actual task start.
  final Duration? timeout;
}
