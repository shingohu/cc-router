@TestOn('vm')
library;

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  for (final (builder, annotation, output, declaration) in [
    (
      ccServiceBuilder(BuilderOptions.empty),
      'CCService',
      'service/probe.service.g.dart',
      _service,
    ),
    (
      ccServiceMetadataBuilder(BuilderOptions.empty),
      'CCService',
      'metadata/src/probe.service.json',
      _service,
    ),
    (
      ccEventBuilder(BuilderOptions.empty),
      'CCEventSubscription',
      'event/probe.event.g.dart',
      _subscription,
    ),
    (
      ccEventMetadataBuilder(BuilderOptions.empty),
      'CCEventSubscription',
      'metadata/src/probe.event.json',
      _subscription,
    ),
    (
      ccRouteBuilder(BuilderOptions.empty),
      'CCRoute',
      'route/probe.route.g.dart',
      _page,
    ),
    (
      ccRouteMetadataBuilder(BuilderOptions.empty),
      'CCRoute',
      'metadata/src/probe.route.json',
      _page,
    ),
    (
      ccCommandBuilder(BuilderOptions.empty),
      'CCCommandHandler',
      'command/probe.command.g.dart',
      _handler,
    ),
    (
      ccCommandMetadataBuilder(BuilderOptions.empty),
      'CCCommandHandler',
      'metadata/src/probe.command.json',
      _handler,
    ),
    (
      ccRouteBindingBuilder(BuilderOptions.empty),
      'CCRouteImplementation',
      'binding/probe.route_binding.g.dart',
      _binding,
    ),
    (
      ccRouteMetadataBuilder(BuilderOptions.empty),
      'CCRouteImplementation',
      'metadata/src/probe.route.json',
      _binding,
    ),
    (
      ccRouteMetadataBuilder(BuilderOptions.empty),
      'CCComponentContribution',
      'metadata/src/probe.route.json',
      _contribution,
    ),
    (
      ccRouteContractBuilder(BuilderOptions.empty),
      'CCRouteContract',
      'contract/probe.route.contract.g.dart',
      _route,
    ),
    (
      ccRouteMetadataBuilder(BuilderOptions.empty),
      'CCRouteContract',
      'metadata/src/probe.route.json',
      _route,
    ),
    (
      ccInitTaskBuilder(BuilderOptions.empty),
      'CCInitTask',
      'init_task/probe.init_task.g.dart',
      _task,
    ),
    (
      ccInitTaskMetadataBuilder(BuilderOptions.empty),
      'CCInitTask',
      'metadata/src/probe.init_task.json',
      _task,
    ),
  ]) {
    test('$output rejects repeated $annotation annotations', () async {
      final reader = TestReaderWriter(
        rootPackage: 'ccrouter_test',
        flattenOutput: true,
      );
      await reader.testing.loadIsolateSources();
      final logs = <String>[];
      const input = 'lib/src/probe.dart';
      await testBuilder(
        builder,
        {
          'ccrouter_test|$input':
              "import 'package:ccrouter_contracts/ccrouter_contracts.dart';\nimport 'package:ccrouter/ccrouter_generated.dart' show CCRegistry;\n$declaration",
        },
        rootPackage: 'ccrouter_test',
        generateFor: {'ccrouter_test|$input'},
        isInput: (id) => id == AssetId('ccrouter_test', input),
        readerWriter: reader,
        flattenOutput: true,
        onLog: (entry) => logs.add(entry.message),
      );
      expect(
        await reader.canRead(
          AssetId('ccrouter_test', 'lib/src/ccrouter_generated/$output'),
        ),
        isFalse,
      );
      expect(logs.join('\n'), contains('exactly one $annotation annotation'));
    });
  }
}

const _route = '''
@CCRouteContract<void>(componentId: CCComponentId('owner'), id: 'owner.first', pattern: CCPathPattern('/first'))
@CCRouteContract<void>(componentId: CCComponentId('owner'), id: 'owner.second', pattern: CCPathPattern('/second'))
abstract class ProbeRouteContract { const ProbeRouteContract(); }
''';

const _service = '''
@CCService(id: 'owner.first', scope: CCServiceScope.app)
@CCService(id: 'owner.second', scope: CCServiceScope.route)
final class Cache { const Cache(); }
''';

const _subscription = '''
@CCEventContract(componentId: CCComponentId('owner'), id: 'owner.fact')
final class Fact implements CCEvent { const Fact(); }
@CCEventSubscription(id: 'owner.first')
@CCEventSubscription(id: 'owner.second')
void observe(Fact event) {}
''';

const _page = '''
@CCRoute<void>(id: 'owner.first', pattern: CCPathPattern('/first'))
@CCRoute<void>(id: 'owner.second', pattern: CCPathPattern('/second'))
final class Page { const Page(); }
''';

const _handler = '''
@CCCommandContract(id: 'owner.command')
final class Probe implements CCCommand<void> { const Probe(); }
@CCCommandHandler()
@CCCommandHandler()
void handle(Probe command) {}
''';

const _binding = '''
@CCRouteContract<void>(componentId: CCComponentId('owner'), id: 'owner.route', pattern: CCPathPattern('/'))
abstract class ProbeRouteContract { const ProbeRouteContract(); }
@CCRouteImplementation(ProbeRouteContract)
@CCRouteImplementation(ProbeRouteContract)
final class Page implements ProbeRouteContract { const Page(); }
''';

const _contribution = '''
@CCComponentContribution(id: 'owner.first')
@CCComponentContribution(id: 'owner.second')
void contribute(CCRegistry registry) {}
''';

const _task = '''
const first = CCInitTaskContract(id: 'owner.first');
const second = CCInitTaskContract(id: 'owner.second');
@CCInitTask(contract: first, gate: CCInitTaskGate.appStarted, failurePolicy: CCInitTaskFailurePolicy.optional)
@CCInitTask(contract: second, gate: CCInitTaskGate.privacyGranted, failurePolicy: CCInitTaskFailurePolicy.required)
void prepare() {}
''';
