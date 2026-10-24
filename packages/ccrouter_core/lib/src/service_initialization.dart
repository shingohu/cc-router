part of 'runtime.dart';

/// Runs business initialization without capturing the resolving Runtime frame.
///
/// A third-party Future may outlive cancellation. Its continuation retains only
/// the initializer inputs and non-owning Zone values, never the resolver's
/// Scope or RouteEntry locals. Owner cancellation settles readiness separately;
/// this Future still consumes late success/failure under the original Zone.
Future<void> _runServiceInitializer({
  required CCServiceInitializer<Object> initializer,
  required Object instance,
  required CCInvocationContext context,
  required String identity,
  required Map<Object, Object> zoneValues,
}) => runZoned(() async {
  try {
    await initializer(instance, context);
    if (context.cancellation.isCancelled) {
      throw const CCInvocationCancelledError();
    }
  } on CCRouterError {
    rethrow;
  } catch (error) {
    throw CCServiceInitializationError(identity, error.runtimeType.toString());
  }
}, zoneValues: zoneValues);
