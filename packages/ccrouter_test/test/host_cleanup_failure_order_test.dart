import 'dart:async';
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'backend_rejection_ownership_test.dart' show Reusable;

class _Binding implements CCHostLifecycleBinding {
  _Binding(this.onDetach);
  final void Function() onDetach;
  int detaches = 0;
  @override
  String get id => 'review.cleanup';
  @override
  void attach() {}
  @override
  void detach() {
    detaches++;
    onDetach();
  }
}

typedef _Failure = ({Object error, StackTrace stack});
Future<_Failure?> _settle(Zone zone, Future<void> Function() action) {
  final completion = Completer<_Failure?>();
  zone.run(
    () => unawaited(
      Future<void>.sync(action).then<void>(
        (_) => completion.complete(null),
        onError: (Object error, StackTrace stack) =>
            completion.complete((error: error, stack: stack)),
      ),
    ),
  );
  return completion.future;
}

Zone _zone(List<Object> errors) {
  late Zone zone;
  runZonedGuarded(() => zone = Zone.current, (error, _) => errors.add(error));
  return zone;
}

void main() {
  for (final bindingFails in [false, true]) {
    for (final adapterFails in [false, true]) {
      for (final backendFails in [false, true]) {
        test(
          'Host cleanup returns first structural error binding=$bindingFails adapter=$adapterFails backend=$backendFails',
          () async {
            final uncaught = <Object>[];
            final owner = _zone(uncaught);
            final joiner = _zone(uncaught);
            final bindingError = StateError('first binding failure');
            final adapterError = StateError('second Adapter failure');
            final backendError = StateError('last Backend failure');
            final bindingStack = StackTrace.fromString(
              'original Binding stack',
            );
            final adapterStack = StackTrace.fromString(
              'original Adapter stack',
            );
            final backendStack = StackTrace.fromString(
              'original Backend stack',
            );
            final expected = bindingFails
                ? bindingError
                : adapterFails
                ? adapterError
                : backendFails
                ? backendError
                : null;
            final expectedStack = bindingFails
                ? bindingStack
                : adapterFails
                ? adapterStack
                : backendFails
                ? backendStack
                : null;
            final binding = _Binding(() {
              if (bindingFails)
                Error.throwWithStackTrace(bindingError, bindingStack);
            });
            final adapter = Reusable(
              onDispose: () {
                if (adapterFails)
                  Error.throwWithStackTrace(adapterError, adapterStack);
              },
            );
            final release = Completer<void>();
            var backendDisposals = 0;
            owner.run(() {
              CCRouterHost.initialize(
                hostAssembly: CCHostAssembly.withLifecycleBindings(
                  CCHostAssembly.fromComponents(components: const []),
                  [binding],
                ),
              );
              CCRouterHostBinding.attachNavigationAdapter(
                adapter,
                disposeBackend: () async {
                  backendDisposals++;
                  await release.future;
                  if (backendFails)
                    Error.throwWithStackTrace(backendError, backendStack);
                },
              );
            });
            final first = _settle(owner, CCRouterHost.shutdown);
            await Future<void>.delayed(Duration.zero);
            final second = _settle(joiner, CCRouterHost.shutdown);
            expect(binding.detaches, 1);
            expect(adapter.disposeCalls, 1);
            expect(backendDisposals, 1);
            release.complete();
            for (final result in [await first, await second]) {
              expect(result?.error, same(expected));
              expect(result?.stack.toString(), expectedStack?.toString());
            }
            expect(uncaught, isEmpty);
            expect(CCRouter.isInitialized, isFalse);
            await CCRouterHost.shutdown();
            expect(binding.detaches, 1);
            expect(adapter.disposeCalls, 1);
            expect(backendDisposals, 1);
          },
        );
      }
    }
  }
}
