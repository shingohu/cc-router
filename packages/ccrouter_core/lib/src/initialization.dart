part of 'runtime.dart';

/// Runs one statically registered initialization task.
///
/// A task observes Runtime deadline and cancellation through [context]. It must
/// not retain the context after completion or assume Dart can preempt work that
/// ignores cooperative cancellation.
typedef CCInitializationTaskHandler =
    FutureOr<void> Function(CCInvocationContext context);

/// Identifies an explicit condition that allows initialization tasks to run.
///
/// Use [appStarted] for ordinary startup work. Product conditions such as
/// privacy consent or remote configuration use a `const CCInitializationGate`
/// with a stable ID and are opened explicitly by the application host.
final class CCInitializationGate {
  /// Creates a gate identified by the stable [id].
  const CCInitializationGate(this.id);

  /// Gate used for ordinary post-`CCRouter.initialize` startup work.
  static const CCInitializationGate appStarted = CCInitializationGate(
    'appStarted',
  );

  /// Stable identity used by task registration, diagnostics, and execution.
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

/// Immutable definition of one Runtime-wide initialization task.
///
/// Component registrars create tasks during static assembly. Use this for
/// one-time startup work with cross-component ordering; Service instance setup
/// belongs in `CCServiceInitializer`, and repeatable operations use Command.
final class CCInitializationTask {
  /// Creates a task with immutable dependency and execution metadata.
  CCInitializationTask({
    required this.id,
    Iterable<String> dependsOn = const [],
    this.gate = CCInitializationGate.appStarted,
    this.failurePolicy = CCInitializationFailurePolicy.critical,
    this.timeout,
    required this.run,
  }) : dependsOn = List.unmodifiable(dependsOn);

  /// Globally stable task identity.
  final String id;

  /// Task IDs that must succeed before this task may run.
  final List<String> dependsOn;

  /// Explicit condition that must be opened before the task may run.
  final CCInitializationGate gate;

  /// Behavior applied when task execution fails.
  final CCInitializationFailurePolicy failurePolicy;

  /// Optional per-task deadline measured from actual task start.
  final Duration? timeout;

  /// Work executed exactly once during the Runtime lifetime.
  final CCInitializationTaskHandler run;
}

/// Runtime state of a registered initialization task.
enum CCInitializationTaskState {
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

/// Immutable, sanitized diagnostic view of an initialization task.
final class CCInitializationTaskSnapshot {
  /// Creates one read-only task snapshot.
  const CCInitializationTaskSnapshot({
    required this.id,
    required this.ownerComponentId,
    required this.gateId,
    required this.state,
    required this.failurePolicy,
    this.duration,
    this.errorType,
    this.blockedByTaskId,
  });

  /// Stable task identity.
  final String id;

  /// Trusted component owner supplied by the Runtime registry.
  final String ownerComponentId;

  /// Stable gate identity required by the task.
  final String gateId;

  /// Current execution state.
  final CCInitializationTaskState state;

  /// Failure behavior declared by the task.
  final CCInitializationFailurePolicy failurePolicy;

  /// Execution duration after the task has started, when available.
  final Duration? duration;

  /// Sanitized runtime type of a task failure, when applicable.
  final String? errorType;

  /// First failed or skipped dependency that prevented execution.
  final String? blockedByTaskId;
}

/// Mutable Runtime-owned state for one statically registered task.
final class _InitializationTaskRecord {
  /// Creates a pending record for [task] and its trusted component owner.
  _InitializationTaskRecord({
    required this.ownerComponentId,
    required this.task,
  });

  /// Component that registered the task, or empty for low-level tests.
  final String ownerComponentId;

  /// Immutable task definition.
  final CCInitializationTask task;

  /// Current one-way task state.
  CCInitializationTaskState state = CCInitializationTaskState.pending;

  /// Measured execution duration, populated after a task starts.
  Duration? duration;

  /// Sanitized failure type without an exception message or payload.
  String? errorType;

  /// Dependency that caused this task to be skipped.
  String? blockedByTaskId;

  /// Creates an immutable diagnostic snapshot of the current record.
  CCInitializationTaskSnapshot get snapshot => CCInitializationTaskSnapshot(
    id: task.id,
    ownerComponentId: ownerComponentId,
    gateId: task.gate.id,
    state: state,
    failurePolicy: task.failurePolicy,
    duration: duration,
    errorType: errorType,
    blockedByTaskId: blockedByTaskId,
  );
}

/// Captures one failed task without retaining its original exception message.
final class _InitializationTaskFailure {
  /// Creates a scheduler result for [record] and the original [error].
  const _InitializationTaskFailure(this.record, this.error);

  /// Task record updated by the failed execution.
  final _InitializationTaskRecord record;

  /// Original error used only for cancellation classification before returning.
  final Object error;
}
