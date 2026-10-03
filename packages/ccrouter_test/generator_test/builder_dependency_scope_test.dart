@TestOn('vm')
library;

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

// These are cold, in-memory builds of the production builders, not a new
// invalidation algorithm. Physical reads and resolver entrypoints are different
// evidence; neither is a complete symbol-level dependency certificate.
const _input = 'scope_consumer|lib/src/read_scope_probe.dart';
const _barrel = 'scope_contracts|lib/contracts.dart';
const _values = 'scope_contracts|lib/src/values.dart';
const _types = 'scope_contracts|lib/src/types.dart';

final _builders = <String, Builder Function(BuilderOptions)>{
  'routes': ccRouteBuilder,
  'route_bindings': ccRouteBindingBuilder,
  'route_contracts': ccRouteContractBuilder,
  'route_metadata': ccRouteMetadataBuilder,
  'services': ccServiceBuilder,
  'service_contracts': ccServiceContractBuilder,
  'service_proxies': ccServiceProxyBuilder,
  'service_metadata': ccServiceMetadataBuilder,
  'commands': ccCommandBuilder,
  'command_metadata': ccCommandMetadataBuilder,
  'events': ccEventBuilder,
  'event_metadata': ccEventMetadataBuilder,
  'init_tasks': ccInitTaskBuilder,
  'init_task_metadata': ccInitTaskMetadataBuilder,
  'component_metadata': ccComponentMetadataBuilder,
};

const _source = r'''
import 'package:ccrouter/ccrouter.dart';
import 'package:scope_contracts/contracts.dart';

const probeComponent = CCComponent(
  id: CCComponentId(probeId),
  version: '1.0.0',
  dependencies: [CCComponentId('provider')],
  serviceDependencies: [CCServiceDependency<SharedService>()],
);

@CCRoute<void>(id: '$probeId.page', pattern: CCPathPattern('/probe'))
final class ProbePage {
  const ProbePage({@CCQueryParam() this.count = defaultCount});
  /// Number of entries.
  final int count;
}

@CCRouteContract<void>(
  id: '$probeId.contract', componentId: CCComponentId('provider'),
  pattern: CCPathPattern('/contract'),
)
abstract class ProbeRouteContract {
  const ProbeRouteContract({@CCQueryParam() this.count = defaultCount});
  final int count;
}

@CCServiceContract(id: '$probeId.local', componentId: CCComponentId('provider'))
abstract interface class LocalService { String read(); }

@CCService()
final class SharedServiceImpl implements SharedService {
  const SharedServiceImpl();
  @override
  String read([int count = defaultCount]) => 'value';
}

@CCCommandContract(id: '$probeId.command')
final class ProbeCommand implements CCCommand<String> {
  const ProbeCommand();
}
@CCCommandHandler()
String handleCommand(ProbeCommand command) => 'value';

@CCEventContract(id: '$probeId.event')
final class ProbeEvent implements CCEvent { const ProbeEvent(); }
@CCEventSubscription(id: '$probeId.subscriber')
void handleEvent(ProbeEvent event) {}

const probeTask = CCInitTaskContract(id: '$probeId.task');
@CCInitTask(
  contract: probeTask, dependsOn: [sharedTask],
  gate: CCInitTaskGate.appStarted,
  failurePolicy: CCInitTaskFailurePolicy.required,
)
void initializeProbe() {}
''';

const _typeSource = r'''
import 'package:ccrouter/ccrouter.dart';
import 'values.dart';
@CCServiceContract(
  id: '$probeId.shared', componentId: CCComponentId('provider'),
)
abstract interface class SharedService {
  String read([int count = defaultCount]);
}
const sharedTask = CCInitTaskContract(
  id: '$probeId.foundation', componentId: CCComponentId('provider'),
);
''';

void main() {
  for (final name in _builders.keys) {
    test(
      '$name resolves transitive cross-package inputs and constants',
      () async {
        final baseline = await _build(name);
        expect(baseline.outputs, isNotEmpty, reason: baseline.logs);
        expect(baseline.logs, isNot(contains('Could not resolve')));
        expect(baseline.entrypoints, contains(_input));
        // Snapshot reads before inspecting outputs: test assertions must not
        // contaminate the measured production reader access set.
        expect(baseline.reads, containsAll([_input, _barrel, _values, _types]));

        final changed = await _build(
          name,
          values: _valuesSource(id: 'changed'),
        );
        expect(changed.outputs, isNotEmpty, reason: changed.logs);
        // A binding delegates to the generated descriptor. It must validate
        // the changed ID, although a valid new ID need not change its bytes.
        expect(
          changed.outputs,
          name == 'route_bindings'
              ? equals(baseline.outputs)
              : isNot(equals(baseline.outputs)),
        );

        final invalid = await _build(
          name,
          values: _valuesSource(id: 'Bad Id'),
          fails: true,
        );
        expect(invalid.outputs, isEmpty);
        expect(invalid.logs, contains('invalid'));
      },
    );
  }

  for (final name in [
    'route_metadata',
    'service_metadata',
    'command_metadata',
    'event_metadata',
    'init_task_metadata',
  ]) {
    test(
      '$name observes location but ignores a trailing ordinary comment',
      () async {
        final baseline = await _build(name);
        final trailing = await _build(
          name,
          source: '$_source\n// trailing note\n',
        );
        expect(trailing.outputs, equals(baseline.outputs));
        final moved = await _build(name, source: '// added line\n$_source');
        expect(moved.outputs, isNot(equals(baseline.outputs)));
      },
    );
  }

  for (final name in ['routes', 'route_contracts', 'service_proxies']) {
    test('$name embeds a changed transitive default constant', () async {
      final baseline = await _build(name);
      final changed = await _build(name, values: _valuesSource(count: 7));
      expect(changed.outputs, isNotEmpty, reason: changed.logs);
      expect(changed.outputs, isNot(equals(baseline.outputs)));
    });
  }

  for (final kind in ['command', 'event']) {
    test(
      '$kind metadata validates bodies even without local declarations',
      () async {
        final declarations = kind == 'command'
            ? "@CCCommandContract(id: 'provider.command')\n"
                  'final class Payload implements CCCommand<void> { const Payload(); }'
            : "@CCEventContract(id: 'provider.event')\n"
                  'final class Payload implements CCEvent { const Payload(); }';
        final source =
            "import 'package:ccrouter/ccrouter.dart';\n"
            "import 'package:scope_contracts/contracts.dart';\n"
            'void ordinaryFunction() {}';
        final types = "import 'package:ccrouter/ccrouter.dart';\n$declarations";
        final baseline = await _build(
          '${kind}_metadata',
          source: source,
          types: types,
        );
        expect(baseline.outputs, isEmpty);
        expect(baseline.logs, isNot(contains('must use its generated')));
        final changed = await _build(
          '${kind}_metadata',
          source: source.replaceFirst(
            '{}',
            '{ CCRouter.$kind(const Payload()); }',
          ),
          types: types,
          fails: true,
        );
        expect(changed.outputs, isEmpty);
        expect(changed.logs, contains('must use its generated'));
      },
    );
  }

  test(
    'InitTask metadata distinguishes equal constants from reference syntax',
    () async {
      final baseline = await _build('init_task_metadata');
      final changed = await _build(
        'init_task_metadata',
        source: _source.replaceFirst(
          'contract: probeTask',
          "contract: CCInitTaskContract(id: '\$probeId.task')",
        ),
        fails: true,
      );
      expect(baseline.outputs, isNotEmpty);
      expect(changed.outputs, isEmpty);
      expect(changed.logs, contains('must reference a top-level'));
    },
  );

  test(
    'barrel changes must re-resolve even when the consumer bytes are unchanged',
    () async {
      final baseline = await _build('routes');
      final changed = await _build(
        'routes',
        barrel: "export 'src/alternate.dart'; export 'src/types.dart';",
      );
      expect(changed.outputs, isNotEmpty, reason: changed.logs);
      expect(changed.outputs, isNot(equals(baseline.outputs)));
    },
  );

  test('part declarations contribute output and source locations', () async {
    const source =
        "library;\nimport 'package:ccrouter/ccrouter.dart';\n"
        "part 'read_scope_part.dart';\n";
    const part =
        "part of 'read_scope_probe.dart';\n"
        "@CCEventContract(id: 'probe.part')\n"
        'final class PartEvent implements CCEvent { const PartEvent(); }';
    final baseline = await _build('event_metadata', source: source, part: part);
    final moved = await _build(
      'event_metadata',
      source: source,
      part: '// line\n$part',
    );
    expect(baseline.outputs, isNotEmpty, reason: baseline.logs);
    expect(
      baseline.reads,
      contains('scope_consumer|lib/src/read_scope_part.dart'),
    );
    expect(moved.outputs, isNot(equals(baseline.outputs)));
  });

  test(
    'Route DartDoc affects metadata without changing executable output',
    () async {
      final changedSource = _source.replaceFirst(
        'Number of entries.',
        'Count of records.',
      );
      for (final name in ['routes', 'route_metadata']) {
        final baseline = await _build(name);
        final changed = await _build(name, source: changedSource);
        expect(baseline.outputs, isNotEmpty, reason: baseline.logs);
        expect(changed.outputs, isNotEmpty, reason: changed.logs);
        expect(
          changed.outputs,
          name == 'routes'
              ? equals(baseline.outputs)
              : isNot(equals(baseline.outputs)),
        );
      }
    },
  );

  test(
    'Service Proxy consumes imported generic bounds and typedef targets',
    () async {
      const types = r'''
import 'package:ccrouter/ccrouter.dart';
@CCServiceContract(id: 'provider.service', componentId: CCComponentId('provider'))
abstract interface class SharedService {
  T echo<T extends num>(T value);
  Payload read();
}
typedef Payload = String;
''';
      final baseline = await _build('service_proxies', types: types);
      expect(baseline.outputs, isNotEmpty, reason: baseline.logs);
      final bound = await _build(
        'service_proxies',
        types: types.replaceFirst('extends num', 'extends int'),
      );
      expect(bound.outputs, isNotEmpty, reason: bound.logs);
      expect(bound.outputs, isNot(equals(baseline.outputs)));
      final invalidAlias = await _build(
        'service_proxies',
        types: types.replaceFirst(
          'typedef Payload = String;',
          'typedef Payload = void Function();',
        ),
        fails: true,
      );
      expect(invalidAlias.outputs, isEmpty);
      expect(invalidAlias.logs, contains('callback or function types'));
    },
  );

  test('Route Codec validation follows imported supertype arguments', () async {
    const source = r'''
import 'package:ccrouter/ccrouter.dart';
import 'package:scope_contracts/contracts.dart';
@CCRoute<void>(id: 'probe.codec', pattern: CCPathPattern('/codec'))
final class ProbePage {
  const ProbePage({@CCQueryParam(codec: ValueCodec) required this.value});
  final Value value;
}
''';
    const types = r'''
import 'package:ccrouter/ccrouter.dart';
class Value { const Value(); }
class ValueCodec implements CCRouteQueryCodec<Value> {
  const ValueCodec();
  Value decode(List<String> values) => const Value();
  List<String> encode(Value value) => [];
}
''';
    final baseline = await _build('routes', source: source, types: types);
    expect(baseline.outputs, isNotEmpty, reason: baseline.logs);
    final changed = await _build(
      'routes',
      source: source,
      types: types
          .replaceFirst('CCRouteQueryCodec<Value>', 'CCRouteQueryCodec<String>')
          .replaceFirst(
            'Value decode(List<String> values) => const Value();',
            "String decode(List<String> values) => '';",
          )
          .replaceFirst('encode(Value value)', 'encode(String value)'),
      fails: true,
    );
    expect(changed.outputs, isEmpty);
    expect(changed.logs, contains('must exactly match the parameter type'));
  });

  test(
    'a transitive annotation changes diagnostics in an unchanged ordinary body',
    () async {
      const source =
          "import 'package:ccrouter/ccrouter.dart';\n"
          "import 'package:scope_contracts/contracts.dart';\n"
          'void invoke() { CCRouter.command(makeCommand()); }';
      const types =
          "import 'package:ccrouter/ccrouter.dart';\n"
          'final class Payload implements CCCommand<void> { const Payload(); }\n'
          'Payload makeCommand() => const Payload();';
      final baseline = await _build(
        'command_metadata',
        source: source,
        types: types,
      );
      final changed = await _build(
        'command_metadata',
        source: source,
        types: types.replaceFirst(
          'final class Payload',
          "@CCCommandContract(id: 'provider.command')\nfinal class Payload",
        ),
        fails: true,
      );
      expect(baseline.outputs, isEmpty);
      expect(baseline.logs, isNot(contains('must use its generated')));
      expect(changed.outputs, isEmpty);
      expect(changed.logs, contains('must use its generated'));
    },
  );

  test(
    'a previously empty input can gain a Route without changing the graph',
    () async {
      final baseline = await _build('routes', source: '// no declarations\n');
      final changed = await _build('routes');
      expect(baseline.outputs, isEmpty);
      expect(changed.outputs, isNotEmpty, reason: changed.logs);
    },
  );
}

String _valuesSource({String id = 'probe', int count = 3}) =>
    "const probeId = '$id';\nconst defaultCount = $count;\n";

Future<_Evidence> _build(
  String name, {
  String source = _source,
  String? values,
  String types = _typeSource,
  String barrel = "export 'src/values.dart'; export 'src/types.dart';",
  String? part,
  bool fails = false,
}) async {
  final reader = TestReaderWriter(
    rootPackage: 'scope_consumer',
    flattenOutput: true,
  );
  await reader.testing.loadIsolateSources();
  // Keep dependency fixtures out of sourceAssets: build_test applies factories
  // to every Package listed there, even when generateFor selects one input.
  // Only the consumer may run this factory; dependency reads come from resolve.
  final dependencyAssets = {
    _barrel: barrel,
    _values: values ?? _valuesSource(),
    _types: types,
    'scope_contracts|lib/src/alternate.dart': _valuesSource(count: 9),
    if (part != null) 'scope_consumer|lib/src/read_scope_part.dart': part,
  };
  for (final entry in dependencyAssets.entries) {
    reader.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  final logs = <String>[];
  final result = await testBuilder(
    _builders[name]!(BuilderOptions.empty),
    {_input: source},
    rootPackage: 'scope_consumer',
    generateFor: {_input},
    isInput: (id) => id == _input,
    readerWriter: reader,
    flattenOutput: true,
    onLog: (log) => logs.add(log.message),
  );
  expect(result.succeeded, !fails, reason: logs.join('\n'));
  final reads = reader.testing.assetsRead.map((id) => '$id').toSet();
  final entrypoints = reader.testing
      .resolverEntrypointsTrackedFor(primaryInput: AssetId.parse(_input))
      .map((id) => '$id')
      .toSet();
  return _Evidence(reads, entrypoints, {
    for (final id in reader.testing.assetsWritten.where(
      (id) =>
          id.path.contains('/ccrouter_generated/') &&
          id.path.split('/').last.startsWith('read_scope_probe.') &&
          (id.path.endsWith('.g.dart') || id.path.endsWith('.json')),
    ))
      '$id': reader.testing.readString(id),
  }, logs.join('\n'));
}

final class _Evidence {
  const _Evidence(this.reads, this.entrypoints, this.outputs, this.logs);
  final Set<String> reads;
  final Set<String> entrypoints;
  final Map<String, String> outputs;
  final String logs;
}
