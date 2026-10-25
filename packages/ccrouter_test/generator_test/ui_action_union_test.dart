@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

const _source = '''
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_ui/ccrouter_ui.dart';
import 'package:flutter/widgets.dart';
const owner = CCComponentId('orders');
final class Props {
  const Props({required this.orderId});
  final int orderId;
}
enum Action { openDetails }
@CCUIFragmentContract<Props, Action>(componentId: owner, id: 'orders.summary', version: '1.0.0')
abstract final class Summary {}
''';

Future<({String output, String logs})> _generate(
  String source, {
  bool metadata = true,
  Map<String, String> additionalSources = const {},
}) async {
  final reader = TestReaderWriter(
    rootPackage: 'ccrouter_test',
    flattenOutput: true,
  );
  await reader.testing.loadIsolateSources();
  final logs = <String>[];
  await testBuilder(
    metadata
        ? ccUIFragmentMetadataBuilder(BuilderOptions.empty)
        : ccUIFragmentBuilder(BuilderOptions.empty),
    {'ccrouter_test|lib/src/ui_probe.dart': source, ...additionalSources},
    rootPackage: 'ccrouter_test',
    generateFor: {'ccrouter_test|lib/src/ui_probe.dart'},
    isInput: (id) => id == 'ccrouter_test|lib/src/ui_probe.dart',
    readerWriter: reader,
    flattenOutput: true,
    onLog: (log) => logs.add(log.message),
  );
  final output = AssetId(
    'ccrouter_test',
    metadata
        ? 'lib/src/ccrouter_generated/metadata/ui_probe.ui.json'
        : 'lib/src/ccrouter_generated/ui/ui_probe.ui.g.dart',
  );
  return (
    output: await reader.canRead(output)
        ? await reader.readAsString(output)
        : '',
    logs: logs.join('\n'),
  );
}

const _union = '''
sealed class Target {
  const Target(this.id);
  final String id;
}
final class UserTarget extends Target { const UserTarget(super.id); }
final class ScoreTarget extends Target { const ScoreTarget(super.id); }
final class VideoTarget extends Target { const VideoTarget(super.id); }
final class ArtistTarget extends Target { const ArtistTarget(super.id); }
sealed class Action { const Action(); }
final class SettingsRequested extends Action { const SettingsRequested(); }
final class TargetSelected extends Action {
  const TargetSelected(this.target);
  final Target target;
}
''';

String _withAction(String action) =>
    _source.replaceFirst('enum Action { openDetails }', action);

String _fingerprint(String output) =>
    (jsonDecode(output) as Map)['uiContracts'][0]['shapeFingerprint'] as String;

void main() {
  test('legacy enum fingerprint stays byte compatible', () async {
    final result = await _generate(_source);
    expect(
      _fingerprint(result.output),
      '00ada274a3626f31de2b44ebd56e4818ede659e4fdc961fb69a146fb2bf88dca',
    );
  });
  test('legacy DTO fingerprint stays byte compatible', () async {
    final result = await _generate(
      _withAction(
        'final class Action { const Action({this.id = 1}); final int id; }',
      ),
    );
    expect(
      _fingerprint(result.output),
      'd8ee3f0b589e35ebdecf41c5454de61383b9e53ab4284ce122896df1768e474e',
    );
  });
  test('sealed root and nested inherited targets use UI schema 3', () async {
    final result = await _generate(_withAction(_union));
    expect(result.output, isNotEmpty, reason: result.logs);
    final metadata = jsonDecode(result.output) as Map;
    expect(metadata['uiSchemaVersion'], 3);
    final contract = (metadata['uiContracts'] as List).single as Map;
    expect(contract['uiSchemaVersion'], 3);
    expect(
      (contract['publicTypes'] as List).map((t) => t['symbol']),
      containsAll([
        'Action',
        'SettingsRequested',
        'TargetSelected',
        'Target',
        'UserTarget',
        'ScoreTarget',
        'VideoTarget',
        'ArtistTarget',
      ]),
    );
  });
  test('DTO Action can contain a union without opening Props', () async {
    final model =
        _union.substring(0, _union.indexOf('sealed class Action')) +
        'final class Action { const Action(this.target); final Target target; }';
    final result = await _generate(_withAction(model));
    expect(result.output, isNotEmpty, reason: result.logs);
    expect((jsonDecode(result.output) as Map)['uiSchemaVersion'], 3);
    final invalid = await _generate(
      _withAction(
        _union,
      ).replaceFirst('final int orderId;', 'final Target orderId;'),
    );
    expect(invalid.output, isEmpty);
    expect(invalid.logs, contains('UI DTOs must be final'));
  });
  test(
    'generated Renderer and Client preserve the exact Action type',
    () async {
      final result = await _generate('''${_withAction(_union)}
@CCUIFragmentRenderer(Summary)
Widget render(CCUIFragmentRenderInput<Props, Action> input) => const SizedBox();
const component = CCComponent(id: CCComponentId('account'), version: '1.0.0',
  dependencies: [owner], uiDependencies: [CCUIFragmentDependency<Summary>(alias: 'summary', versionRange: '^1.0.0')]);
''', metadata: false);
      expect(
        result.output,
        contains('ValueChanged<ui_0.Action>'),
        reason: result.logs,
      );
      expect(result.output, contains('CCUIRenderer<ui_0.Props, ui_0.Action>'));
    },
  );
  test('part variants are discovered with defining-library identity', () async {
    final source = _withAction(
      'sealed class Action { const Action(); }',
    ).replaceFirst('const owner', "part 'ui_variants.dart';\nconst owner");
    final result = await _generate(
      source,
      additionalSources: {
        'ccrouter_test|lib/src/ui_variants.dart':
            "part of 'ui_probe.dart'; final class Selected extends Action { const Selected(); }",
      },
    );
    expect(result.output, isNotEmpty, reason: result.logs);
    final types =
        (jsonDecode(result.output) as Map)['uiContracts'][0]['publicTypes']
            as List;
    expect(types, contains(containsPair('symbol', 'Selected')));
    expect(
      types.singleWhere((t) => t['symbol'] == 'Selected')['source'],
      'lib/src/ui_probe.dart',
    );
    final inline = await _generate(
      _withAction(
        'sealed class Action { const Action(); } final class Selected extends Action { const Selected(); }',
      ),
    );
    expect(inline.output, isNotEmpty, reason: inline.logs);
    expect(_fingerprint(result.output), _fingerprint(inline.output));
  });
  test(
    'nested unions imported from another Package retain all public types',
    () async {
      final source =
          _withAction('''
sealed class Action { const Action(); }
final class Selected extends Action { const Selected(this.target); final payload.Target target; }
''').replaceFirst(
            "import 'package:ccrouter/ccrouter.dart';",
            "import 'package:ccrouter/ccrouter.dart';\nimport 'package:demo_order_contracts/targets.dart' as payload;",
          );
      final result = await _generate(
        source,
        additionalSources: {
          'demo_order_contracts|lib/targets.dart': _union.substring(
            0,
            _union.indexOf('sealed class Action'),
          ),
        },
      );
      expect(result.output, isNotEmpty, reason: result.logs);
      expect(
        (jsonDecode(result.output) as Map)['uiContracts'][0]['publicTypes'],
        contains(
          allOf(
            containsPair('package', 'demo_order_contracts'),
            containsPair('symbol', 'ArtistTarget'),
          ),
        ),
      );
    },
  );
  test(
    'variant order is inert but variant, inherited data and default changes alter shape',
    () async {
      Future<String> shape(String model) async {
        final result = await _generate(_withAction(model));
        expect(result.output, isNotEmpty, reason: result.logs);
        return _fingerprint(result.output);
      }

      final baseline = await shape(_union);
      const first =
          'final class UserTarget extends Target { const UserTarget(super.id); }';
      const second =
          'final class ScoreTarget extends Target { const ScoreTarget(super.id); }';
      expect(
        await shape(_union.replaceFirst('$first\n$second', '$second\n$first')),
        baseline,
      );
      expect(await shape(_union.replaceFirst(first, '')), isNot(baseline));
      expect(
        await shape(_union.replaceAll('UserTarget', 'PersonTarget')),
        isNot(baseline),
      );
      expect(
        await shape(_union.replaceFirst('final String id;', 'final num id;')),
        isNot(baseline),
      );
      final defaults = _union.replaceFirst(
        'const TargetSelected(this.target);',
        "const TargetSelected([this.target = const UserTarget('same')]);",
      );
      final userDefault = await shape(defaults);
      expect(
        await shape(
          defaults.replaceFirst(
            "const UserTarget('same')",
            "const ScoreTarget('same')",
          ),
        ),
        isNot(userDefault),
      );
      expect(
        await shape(
          defaults.replaceFirst(
            "const UserTarget('same')",
            "const UserTarget('different')",
          ),
        ),
        isNot(userDefault),
      );
    },
  );
  test(
    'implicit super defaults and inherited nullable values are fingerprinted',
    () async {
      Future<String> shape(String defaultValue) async {
        final model =
            '''
sealed class Target { const Target({this.id = $defaultValue}); final String? id; }
final class UserTarget extends Target { const UserTarget(); }
sealed class Action { const Action(); }
final class Selected extends Action {
  const Selected({this.target = const UserTarget()}); final Target target;
}
''';
        final result = await _generate(_withAction(model));
        expect(result.output, isNotEmpty, reason: result.logs);
        return _fingerprint(result.output);
      }

      expect(await shape('null'), isNot(await shape("'changed'")));
    },
  );
  final invalidModels = <String, String>{
    'empty union': 'sealed class Action { const Action(); }',
    'open leaf':
        'sealed class Action { const Action(); } class Open extends Action { const Open(); }',
    'abstract leaf':
        'sealed class Action { const Action(); } abstract final class Open extends Action { const Open(); }',
    'nested inheritance':
        _union +
        'final class Grandchild extends SettingsRequested { const Grandchild(); }',
    'implements edge':
        _union + 'final class Impostor implements Action { const Impostor(); }',
    'private leaf':
        _union + 'final class _Private extends Action { const _Private(); }',
    'generic leaf':
        _union + 'final class Generic<T> extends Action { const Generic(); }',
    'mutable': _union.replaceFirst('final Target target;', 'Target target;'),
    'non-const': _union.replaceFirst(
      'const TargetSelected(this.target);',
      'TargetSelected(this.target);',
    ),
    'resource': _union.replaceFirst(
      'final Target target;',
      'final Future<String> target;',
    ),
    'behavior': _union.replaceFirst(
      'final Target target;',
      'final Target target; void run() {}',
    ),
    'field cycle': _union.replaceFirst(
      'final Target target;',
      'final Action target;',
    ),
    'field override': _union.replaceFirst(
      'const UserTarget(super.id);',
      "const UserTarget(super.id); @override final String id = 'other';",
    ),
    'explicit super initializer': _union.replaceFirst(
      'const UserTarget(super.id);',
      'const UserTarget(String id) : super(id);',
    ),
    'assert initializer': _union.replaceFirst(
      'const UserTarget(super.id);',
      "const UserTarget(super.id) : assert(id != '');",
    ),
    'redirect': _union.replaceFirst(
      'const UserTarget(super.id);',
      "const UserTarget(String id) : this.other(id); const UserTarget.other(super.id);",
    ),
    'factory': _union.replaceFirst(
      'const UserTarget(super.id);',
      'const factory UserTarget(String id) = ScoreTarget;',
    ),
  };
  for (final entry in invalidModels.entries) {
    test('union rejects ${entry.key}', () async {
      final result = await _generate(_withAction(entry.value));
      expect(result.output, isEmpty);
      expect(result.logs, contains('UI DTO Action'), reason: result.logs);
    });
  }
  test(
    'legacy deep DTO generation remains outside the union depth limit',
    () async {
      final nodes = List.generate(
        40,
        (i) =>
            "final class Node$i { const Node$i(); final ${i == 39 ? 'String' : 'Node${i + 1}'} next = ${i == 39 ? "'tail'" : 'const Node${i + 1}()'}; }",
      ).join('\n');
      final result = await _generate(
        _withAction(
          'final class Action { const Action(); final Node0 next = const Node0(); }\n$nodes',
        ),
      );
      expect(result.output, isNotEmpty, reason: result.logs);
      expect((jsonDecode(result.output) as Map)['uiSchemaVersion'], 2);
    },
  );
  test('union width is bounded to 512 expanded schema nodes', () async {
    final variants = List.generate(
      513,
      (i) => 'final class Variant$i extends Action { const Variant$i(); }',
    ).join('\n');
    final result = await _generate(
      _withAction('sealed class Action { const Action(); }\n$variants'),
    );
    expect(result.output, isEmpty);
    expect(result.logs, contains('512 nodes'));
  });
  test('union data graph expansion is bounded', () async {
    final fields = List.generate(
      34,
      (i) =>
          'final class Node$i { const Node$i(this.next); final ${i == 33 ? 'String' : 'Node${i + 1}'} next; }',
    ).join('\n');
    final model =
        '${_union.replaceFirst('final Target target;', 'final Node0 target;')}\n$fields';
    final result = await _generate(_withAction(model));
    expect(result.output, isEmpty);
    expect(result.logs, contains('32 data levels'));
  });
}
