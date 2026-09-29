part of 'runtime.dart';

/// Runs one statically registered InitTask.
///
/// A task observes Runtime deadline and cancellation through [context]. It must
/// not retain the context after completion or assume Dart can preempt work that
/// ignores cooperative cancellation.
typedef CCInitTaskHandler =
    FutureOr<void> Function(CCInvocationContext context);

/// Immutable definition of one Runtime-wide InitTask.
///
/// Component registrars create tasks during static assembly. Use this for
/// one-time startup work with cross-component ordering; Service instance setup
/// belongs in `CCServiceInitializer`, and repeatable operations use Command.
final class CCInitTaskDefinition {
  /// Creates a task with immutable dependency and execution metadata.
  CCInitTaskDefinition({
    required this.id,
    Iterable<String> dependsOn = const [],
    this.gate = CCInitTaskGate.appStarted,
    this.failurePolicy = CCInitTaskFailurePolicy.critical,
    this.timeout,
    required this.run,
  }) : dependsOn = List.unmodifiable(dependsOn);

  /// Globally stable task identity.
  final String id;

  /// Task IDs that must succeed before this task may run.
  final List<String> dependsOn;

  /// Explicit condition that must be opened before the task may run.
  final CCInitTaskGate gate;

  /// Behavior applied when task execution fails.
  final CCInitTaskFailurePolicy failurePolicy;

  /// Optional per-task deadline measured from actual task start.
  final Duration? timeout;

  /// Work executed exactly once during the Runtime lifetime.
  final CCInitTaskHandler run;
}

/// Runtime state of a registered InitTask.
enum CCInitTaskState {
  /// Waiting for its gate or dependencies.
  pending,

  /// Currently executing.
  running,

  /// Completed successfully and will not run again.
  succeeded,

  /// Failed and will not be retried automatically.
  failed,

  /// Cannot run because one of its dependencies failed or was skipped.
  skipped,
}

/// Immutable, sanitized diagnostic view of an InitTask.
final class CCInitTaskSnapshot {
  /// Creates one read-only task snapshot.
  CCInitTaskSnapshot({
    required this.id,
    required this.ownerComponentId,
    required this.gateId,
    required this.state,
    required this.failurePolicy,
    List<String> dependsOn = const [],
    this.duration,
    this.errorType,
    this.blockedByTaskId,
  }) : dependsOn = List.unmodifiable(dependsOn);

  /// Stable task identity.
  final String id;

  /// Trusted component owner supplied by the Runtime registry.
  final String ownerComponentId;

  /// Stable gate identity required by the task.
  final String gateId;

  /// Current execution state.
  final CCInitTaskState state;

  /// Failure behavior declared by the task.
  final CCInitTaskFailurePolicy failurePolicy;

  /// Stable task IDs that must succeed before this task may run.
  ///
  /// The list is exposed for read-only diagnostics such as an InitTask DAG;
  /// it does not grant callers permission to reorder, retry, or mutate tasks.
  final List<String> dependsOn;

  /// Execution duration after the task has started, when available.
  final Duration? duration;

  /// Sanitized runtime type of a task failure, when applicable.
  final String? errorType;

  /// First failed or skipped dependency that prevented execution.
  final String? blockedByTaskId;
}

/// Mutable Runtime-owned state for one statically registered task.
final class _InitTaskRecord {
  /// Creates a pending record for [task] and its trusted component owner.
  _InitTaskRecord({required this.ownerComponentId, required this.task});

  /// Component that registered the task, or empty for low-level tests.
  final String ownerComponentId;

  /// Immutable task definition.
  final CCInitTaskDefinition task;

  /// Current one-way task state.
  CCInitTaskState state = CCInitTaskState.pending;

  /// Measured execution duration, populated after a task starts.
  Duration? duration;

  /// Sanitized failure type without an exception message or payload.
  String? errorType;

  /// Dependency that caused this task to be skipped.
  String? blockedByTaskId;

  /// Creates an immutable diagnostic snapshot of the current record.
  CCInitTaskSnapshot get snapshot => CCInitTaskSnapshot(
    id: task.id,
    ownerComponentId: ownerComponentId,
    gateId: task.gate.id,
    state: state,
    failurePolicy: task.failurePolicy,
    dependsOn: task.dependsOn,
    duration: duration,
    errorType: errorType,
    blockedByTaskId: blockedByTaskId,
  );
}

/// Captures one failed task without retaining its original exception message.
final class _InitTaskFailure {
  /// Creates a scheduler result for [record] and the original [error].
  const _InitTaskFailure(this.record, this.error);

  /// Task record updated by the failed execution.
  final _InitTaskRecord record;

  /// Original error used only for cancellation classification before returning.
  final Object error;
}
