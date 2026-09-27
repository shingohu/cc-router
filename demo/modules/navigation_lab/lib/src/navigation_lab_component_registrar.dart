import 'package:ccrouter/ccrouter.dart';

import 'component_capabilities.dart';
import 'lab_configuration.dart';
import 'policy_pages.dart';
import 'shell_contract.dart';

/// Registers capabilities that do not yet have dedicated declarations.
@CCComponentContribution(id: 'demo_navigation_lab.capabilities')
void registerDemoNavigationLabCapabilities(CCRegistry registry) {
  registerDemoNavigationLabPolicies(registry);
  _registerComponentCapabilities(registry);
  registry.registerShell(demoSingleShellDefinition);
  registry.registerShell(demoWorkspaceShellDefinition);
}

void _registerComponentCapabilities(CCRegistry registry) {
  registry.registerInitializationTask(
    CCInitializationTask(
      id: DemoInitializationTaskIds.foundation,
      run: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        demoNavigationLabStore.record('InitTask · foundation ready');
      },
    ),
  );
  registry.registerInitializationTask(
    CCInitializationTask(
      id: DemoInitializationTaskIds.optionalSdk,
      failurePolicy: CCInitializationFailurePolicy.optional,
      run: (_) => throw StateError('simulated optional SDK failure'),
    ),
  );
  registry.registerInitializationTask(
    CCInitializationTask(
      id: DemoInitializationTaskIds.optionalDependent,
      dependsOn: const [DemoInitializationTaskIds.optionalSdk],
      run: (_) => demoNavigationLabStore.record(
        'InitTask · optional dependent should not run',
      ),
    ),
  );
  registry.registerInitializationTask(
    CCInitializationTask(
      id: DemoInitializationTaskIds.analytics,
      dependsOn: const [DemoInitializationTaskIds.foundation],
      gate: CCInitializationGate.privacyGranted,
      run: (_) => demoNavigationLabStore.record(
        'InitTask · privacy-gated analytics ready',
      ),
    ),
  );

  registry.registerService<DemoAppService>(
    CCServiceProvider(
      factory: (_) => DemoAppService(
        DemoCapabilityInstanceIds.next(),
        demoNavigationLabStore.record,
      ),
    ),
  );
  registry.registerService<DemoSessionService>(
    CCServiceProvider(
      scope: CCServiceScope.session,
      factory: (_) => DemoSessionService(
        DemoCapabilityInstanceIds.next(),
        demoNavigationLabStore.record,
      ),
    ),
  );
  registry.registerService<DemoRouteService>(
    CCServiceProvider(
      scope: CCServiceScope.route,
      factory: (_) => DemoRouteService(
        DemoCapabilityInstanceIds.next(),
        demoNavigationLabStore.record,
      ),
    ),
  );
  registry.registerService<DemoNewInstanceService>(
    CCServiceProvider(
      creationPolicy: CCServiceCreationPolicy.newInstance,
      factory: (_) => DemoNewInstanceService(DemoCapabilityInstanceIds.next()),
    ),
  );
  registry.registerService<DemoLazyService>(
    CCServiceProvider(
      factory: (_) => DemoLazyService(DemoCapabilityInstanceIds.next()),
      initializer: (service, context) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (context.cancellation.isCancelled) return;
        service.ready = true;
        demoNavigationLabStore.record(
          'Lazy Service #${service.instanceId} ready',
        );
      },
    ),
  );
  registry.registerService<DemoChannelService>(
    CCServiceProvider(factory: (_) => const DemoPrimaryChannelService()),
  );
  registry.registerService<DemoChannelService>(
    CCServiceProvider(
      key: demoBackupChannelKey,
      factory: (_) => const DemoBackupChannelService(),
    ),
  );
}

/// Records the completed order through an independent analytics Subscriber.
@CCEventSubscription(id: DemoEventSubscriberIds.orderAnalytics)
void trackDemoOrderCompleted(DemoOrderCompletedEvent event) {
  demoNavigationLabStore.record(
    'Event analytics subscriber · order=${event.orderId}',
  );
}

/// Throws a deliberate Subscriber failure to demonstrate failure isolation.
@CCEventSubscription(id: DemoEventSubscriberIds.orderFailure)
void failDemoOrderCompleted(DemoOrderCompletedEvent event) {
  throw StateError('simulated private Subscriber failure');
}

/// Waits for timeout, caller cancellation, or Runtime shutdown.
@CCEventSubscription()
Future<void> waitForDemoSlowEvent(
  DemoSlowEvent event,
  CCInvocationContext context,
) => context.cancellation.whenCancelled;

/// Creates one deterministic receipt for the typed-result Command example.
@CCCommandHandler()
String handleDemoCreateReceipt(DemoCreateReceiptCommand command) =>
    'receipt:${command.amount}';

/// Refreshes the Demo cache and records observable completion.
@CCCommandHandler()
Future<void> handleDemoRefreshCache(DemoRefreshCacheCommand command) async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  demoNavigationLabStore.record('Command Handler · cache refreshed');
}

/// Waits for cooperative cancellation from timeout, caller, or Runtime.
@CCCommandHandler()
Future<void> handleDemoWait(
  DemoWaitCommand command,
  CCInvocationContext context,
) async {
  await context.cancellation.whenCancelled;
  throw const CCInvocationCancelledError();
}

/// Throws a deliberate business error for diagnostic propagation testing.
@CCCommandHandler()
void handleDemoFail(DemoFailCommand command) {
  throw StateError('simulated private Command failure');
}
