import 'dart:async';

import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker/leak_tracker.dart' show forceGC;

class Command implements CCCommand<void> {}

class Event implements CCEvent {}

class Service {}

const token = CCServiceToken<Service>('probe.service');

class Gate {
  final started = Completer<void>();
  final release = Completer<void>();
  Future<void> run(CCInvocationContext _) {
    started.complete();
    return release.future;
  }
}

class EventRegistrar implements CCComponentRegistrar {
  EventRegistrar(this.gate);
  final Gate gate;
  @override
  void register(CCRegistry registry) {
    registry.registerEventSubscriber<Event>(
      CCEventSubscriber<Event>(
        id: const CCEventSubscriberId<Event>('probe.subscriber'),
        eventId: 'probe.changed',
        handler: (_, context) => gate.run(context),
      ),
    );
  }
}

Future<WeakReference<CCRouterRuntime>> runAndDispose(
  String mode,
  Gate gate,
  bool pending,
) async {
  final runtime = CCRouterRuntime.forTesting(
    components: mode == 'generatedEvent'
        ? [
            CCComponentManifest(
              id: 'probe',
              version: '1.0.0',
              registrar: EventRegistrar(gate),
            ),
          ]
        : const [],
  );
  runtime.registerCommand<Command, void>((_, context) => gate.run(context));
  if (mode == 'event') {
    runtime.registerEvent<Event>(
      'probe.event',
      (_, context) => gate.run(context),
    );
  }
  if (mode == 'typedEvent') {
    runtime.registerEventSubscriber<Event>(
      CCEventSubscriber<Event>(
        id: const CCEventSubscriberId<Event>('probe.subscriber'),
        handler: (_, context) => gate.run(context),
      ),
    );
  }
  runtime.registerService(
    CCServiceProvider<Service>(contractToken: token, factory: (_) => Service()),
  );
  runtime.registerInitTask(
    CCInitTaskDefinition(
      id: 'probe.start',
      gate: CCInitTaskGate.appStarted,
      failurePolicy: CCInitTaskFailurePolicy.required,
      run: gate.run,
    ),
  );
  runtime.initialize();
  final Future<Object?> work = switch (mode) {
    'command' => runtime.command(Command()),
    'event' => runtime.event(Event()),
    'typedEvent' => runtime.event(Event()),
    'generatedEvent' => runtime.invokeGeneratedEvent(
      Event(),
      eventId: 'probe.changed',
      publisherComponentId: 'probe',
    ),
    'service' => runtime.invokeService<Service, void>(
      contractToken: token,
      methodId: 'work',
      call: (_, context) => gate.run(context),
    ),
    'initTask' => runtime.runInitTasks(gate: CCInitTaskGate.appStarted),
    _ => throw StateError(mode),
  };
  final observed = work.then<Object?>(
    (_) => null,
    onError: (Object error, StackTrace _) => error,
  );
  await gate.started.future;
  if (!pending) {
    gate.release.complete();
    expect(await observed, isNull);
  }
  await runtime.dispose();
  if (pending) expect(await observed, isA<CCInvocationCancelledError>());
  return WeakReference(runtime);
}

void main() {
  for (final mode in [
    'command',
    'event',
    'typedEvent',
    'generatedEvent',
    'service',
    'initTask',
  ]) {
    for (final pending in [false, true]) {
      test('$mode pending=$pending releases ended Runtime', () async {
        final gate = Gate();
        final runtime = await runAndDispose(mode, gate, pending);
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        final retained = runtime.target != null;
        if (pending) gate.release.complete();
        await Future<void>.delayed(Duration.zero);
        await forceGC(fullGcCycles: 3, timeout: const Duration(seconds: 20));
        expect(runtime.target, isNull);
        expect(
          retained,
          isFalse,
          reason: 'application callback does not capture Runtime',
        );
      });
    }
  }
}
