@TestOn('vm')
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:ccrouter_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  late TestReaderWriter reader;

  setUp(() async {
    reader = TestReaderWriter(
      rootPackage: 'ccrouter_test',
      flattenOutput: true,
    );
    await reader.testing.loadIsolateSources();
  });

  test('handler builder emits stable typed registration', () async {
    final output = await _generate(
      reader,
      ccCommandBuilder(BuilderOptions.empty),
      r'''
@CCCommandContract(id: 'orders.submit')
final class SubmitOrderCommand implements CCCommand<String> {
  const SubmitOrderCommand(this.orderId);
  final int orderId;
}
@CCCommandHandler()
Future<String> handleSubmit(
  SubmitOrderCommand command,
  CCInvocationContext context,
) async => 'receipt:${command.orderId}';
''',
      'lib/src/ccrouter_generated/command/probe.command.g.dart',
    );

    expect(
      output,
      contains('registerCommand<command_source.SubmitOrderCommand, String>'),
    );
    expect(output, contains('commandId: "orders.submit"'));
    expect(output, contains('command_source.handleSubmit'));
  });

  test('one-parameter handler is adapted to the registry signature', () async {
    final output = await _generate(
      reader,
      ccCommandBuilder(BuilderOptions.empty),
      r'''
@CCCommandContract(id: 'orders.refresh')
final class RefreshCommand implements CCCommand<void> {
  const RefreshCommand();
}
@CCCommandHandler()
void handleRefresh(RefreshCommand command) {}
''',
      'lib/src/ccrouter_generated/command/probe.command.g.dart',
    );

    expect(
      output,
      contains('(command, _) => command_source.handleRefresh(command)'),
    );
  });

  test('metadata contains portable contract and handler locations', () async {
    final output = await _generate(
      reader,
      ccCommandMetadataBuilder(BuilderOptions.empty),
      r'''
@CCCommandContract(id: 'orders.submit', description: 'Submit one order.')
final class SubmitOrderCommand implements CCCommand<String> {
  const SubmitOrderCommand(this.orderId);
  final int orderId;
}
@CCCommandHandler()
String handleSubmit(SubmitOrderCommand command) => 'ok';
''',
      'lib/src/ccrouter_generated/metadata/src/probe.command.json',
    );
    final metadata = jsonDecode(output) as Map<String, dynamic>;
    expect(metadata['commandContracts'], hasLength(1));
    expect(metadata['commandHandlers'], hasLength(1));
    expect(metadata['commandContracts'][0]['version'], '0.1.0');
    expect(
      metadata['commandContracts'][0]['shapeFingerprint'],
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );
    expect(
      metadata['commandContracts'][0]['declaration']['packageUri'],
      'package:ccrouter_test/src/probe.dart',
    );
  });

  test('mutable payload fields fail generation', () async {
    final logs = await _generate(
      reader,
      ccCommandMetadataBuilder(BuilderOptions.empty),
      r'''
@CCCommandContract(id: 'orders.submit')
final class SubmitOrderCommand implements CCCommand<String> {
  SubmitOrderCommand(this.orderId);
  int orderId;
}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.command.json',
      fails: true,
    );
    expect(logs, contains('must be final'));
  });

  test('handler result mismatch fails generation', () async {
    final logs = await _generate(
      reader,
      ccCommandBuilder(BuilderOptions.empty),
      r'''
@CCCommandContract(id: 'orders.submit')
final class SubmitOrderCommand implements CCCommand<String> {
  const SubmitOrderCommand();
}
@CCCommandHandler()
int handleSubmit(SubmitOrderCommand command) => 1;
''',
      'lib/src/ccrouter_generated/command/probe.command.g.dart',
      fails: true,
    );
    expect(logs, contains('does not match CCCommand<String>'));
  });

  test('invalid stable ID fails generation', () async {
    final logs = await _generate(
      reader,
      ccCommandMetadataBuilder(BuilderOptions.empty),
      r'''
@CCCommandContract(id: 'Orders Submit')
final class SubmitOrderCommand implements CCCommand<void> {
  const SubmitOrderCommand();
}
''',
      'lib/src/ccrouter_generated/metadata/src/probe.command.json',
      fails: true,
    );
    expect(logs, contains('Command ID "Orders Submit" is invalid'));
  });

  test('annotated Command cannot bypass its generated Client', () async {
    final logs = await _generate(
      reader,
      ccCommandMetadataBuilder(BuilderOptions.empty),
      r'''
@CCCommandContract(id: 'orders.submit')
final class SubmitOrderCommand implements CCCommand<void> {
  const SubmitOrderCommand();
}
Future<void> bypass() => CCRouter.command(const SubmitOrderCommand());
''',
      'lib/src/ccrouter_generated/metadata/src/probe.command.json',
      fails: true,
    );
    expect(logs, contains('must use its generated component Client'));
  });
}

Future<String> _generate(
  TestReaderWriter reader,
  Builder builder,
  String declarations,
  String outputPath, {
  bool fails = false,
}) async {
  final logs = <String>[];
  const sourcePath = 'lib/src/probe.dart';
  await testBuilder(
    builder,
    {
      'ccrouter_test|$sourcePath':
          "import 'package:ccrouter/ccrouter.dart';\n$declarations",
    },
    rootPackage: 'ccrouter_test',
    generateFor: {'ccrouter_test|$sourcePath'},
    isInput: (id) => id == 'ccrouter_test|$sourcePath',
    readerWriter: reader,
    flattenOutput: true,
    onLog: (log) => logs.add(log.message),
  );
  final output = AssetId('ccrouter_test', outputPath);
  if (fails) {
    expect(await reader.canRead(output), isFalse);
    return logs.join('\n');
  }
  return reader.readAsString(output);
}
