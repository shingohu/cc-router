import 'package:ccrouter/ccrouter.dart';

import 'ccrouter_generated/component/demo_navigation_lab_component.routes.g.dart';
import 'component_capabilities.dart';
import 'lab_configuration.dart';
import 'navigation_lab_component.dart';
import 'policy_pages.dart';
import 'shell_contract.dart';

part 'ccrouter_generated/component/navigation_lab_component_registrar.component.g.dart';

@CCComponent(demoNavigationLabComponent)
final class _DemoNavigationLabComponentRegistrar
    implements CCComponentRegistrar {
  const _DemoNavigationLabComponentRegistrar();

  @override
  void register(CCRegistry registry) {
    registerDemoNavigationLabPolicies(registry);
    _registerComponentCapabilities(registry);
    registry.registerShell(demoSingleShellDefinition);
    registry.registerShell(demoWorkspaceShellDefinition);
    demoNavigationLabComponentGeneratedRoutes.register(registry);
  }
}

void _registerComponentCapabilities(CCRegistry registry) {
  registry.registerCommand<DemoCreateReceiptCommand, String>((command, _) {
    return 'receipt:${command.amount}';
  });
  registry.registerCommand<DemoRefreshCacheCommand, void>((_, _) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    demoNavigationLabStore.record('Command Handler · cache refreshed');
  });
  registry.registerCommand<DemoWaitCommand, void>((_, context) async {
    await context.cancellation.whenCancelled;
    throw const CCInvocationCancelledError();
  });
  registry.registerCommand<DemoFailCommand, void>((_, _) {
    throw StateError('simulated private Command failure');
  });

  registry.registerEventSubscriber<DemoOrderCompletedEvent>(
    CCEventSubscriber<DemoOrderCompletedEvent>(
      id: DemoEventSubscribers.orderAnalytics,
      handler: (event, _) {
        demoNavigationLabStore.record(
          'Event analytics subscriber · order=${event.orderId}',
        );
      },
    ),
  );
  registry.registerEventSubscriber<DemoOrderCompletedEvent>(
    CCEventSubscriber<DemoOrderCompletedEvent>(
      id: DemoEventSubscribers.orderFailure,
      handler: (_, _) =>
          throw StateError('simulated private Subscriber failure'),
    ),
  );
  registry.registerEventSubscriber<DemoSlowEvent>(
    CCEventSubscriber<DemoSlowEvent>(
      id: DemoEventSubscribers.slow,
      handler: (_, context) => context.cancellation.whenCancelled,
    ),
  );

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
      gate: demoPrivacyGrantedGate,
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
  registry.registerService<DemoFactoryService>(
    CCServiceProvider(
      creationPolicy: CCServiceCreationPolicy.factory,
      factory: (_) => DemoFactoryService(DemoCapabilityInstanceIds.next()),
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
