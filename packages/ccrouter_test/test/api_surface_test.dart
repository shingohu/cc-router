import 'dart:io';
import 'dart:convert';

import 'package:ccrouter/ccrouter.dart' as business;
import 'package:ccrouter/ccrouter_host.dart' as host;
import 'package:test/test.dart';

const _adapterSpiNames = <String>{
  'CCNavigationAdapter',
  'CCNavigationAdapterCapabilities',
  'CCNavigationAdapterCapabilitySource',
  'CCNavigationAdapterHostBinding',
  'CCInitialBackendEntrySnapshot',
  'CCNavigationBackendEvent',
  'CCNavigationBackendEventListener',
  'CCNavigationBackendEventSource',
  'CCNavigationBackendSnapshotSource',
  'CCNavigationHostCapabilitySource',
  'CCNavigationManagedEntryReleaseSink',
  'CCNavigationPopCoordinator',
  'CCNavigationPopGuardBinding',
  'CCNavigationPopTarget',
  'CCNavigationPopTargetSource',
  'CCNavigationPredictiveBackSource',
  'CCNavigationPredictiveBackSourceProvider',
  'CCNavigationRoute',
  'CCNavigationRequest',
  'CCNavigationShell',
  'CCPopGuardEvaluator',
  'CCPredictiveBackEvent',
  'CCPredictiveBackEventListener',
  'CCPredictiveBackPhase',
  'CCRouteRestorationOpportunitySignal',
  'CCRouteRestorationOpportunitySource',
};

const _hostContractNames = <String>{
  ..._adapterSpiNames,
  'CCRouteRestorationOpportunityReason',
  'CCContractBundleDescriptor',
  'CCContractCompatibilityCode',
  'CCContractCompatibilityError',
  'CCContractCompatibilityIssue',
  'CCContractDescriptor',
  'CCContractKind',
  'CCContractRequirement',
};

const _businessHiddenContractNames = <String>{
  ..._adapterSpiNames,
  'CCServiceToken',
};

const _hostSpiTypes = <Type>[
  host.CCNavigationAdapter,
  host.CCNavigationAdapterCapabilities,
  host.CCNavigationAdapterCapabilitySource,
  host.CCNavigationAdapterHostBinding,
  host.CCInitialBackendEntrySnapshot,
  host.CCNavigationBackendEvent,
  host.CCNavigationBackendEventSource,
  host.CCNavigationBackendSnapshotSource,
  host.CCNavigationHostCapabilitySource,
  host.CCNavigationManagedEntryReleaseSink,
  host.CCNavigationPopCoordinator,
  host.CCNavigationPopGuardBinding,
  host.CCNavigationPopTarget,
  host.CCNavigationPopTargetSource,
  host.CCNavigationPredictiveBackSource,
  host.CCNavigationPredictiveBackSourceProvider,
  host.CCNavigationRoute,
  host.CCNavigationRequest,
  host.CCNavigationShell,
  host.CCPredictiveBackEvent,
  host.CCRouteRestorationOpportunityReason,
  host.CCGeneratedPackageBundle,
  host.CCHostAssembly,
  host.CCRouterHost,
  host.CCHostAssemblyError,
  host.CCHostAssemblyErrorCode,
  host.CCFlutterRouteFactory,
  host.CCFlutterPage,
  host.CCFlutterBottomSheetPage,
  host.CCFlutterDialogPage,
];

const _businessFacadeTypes = <Type>[business.CCRouter];

void main() {
  test('business barrel hides the complete Adapter SPI snapshot', () {
    expect(_businessFacadeTypes, contains(business.CCRouter));
    final root = _workspaceRoot();
    final businessBarrel = File(
      '${root.path}/packages/ccrouter/lib/ccrouter.dart',
    ).readAsStringSync();

    expect(
      _contractCombinatorNames(businessBarrel, 'hide'),
      _businessHiddenContractNames,
    );
    expect(
      RegExp(
        "export 'src/facade.dart'[\\s\\S]*?hide[\\s\\S]*?"
        'CCRouterTestBinding[\\s\\S]*?;',
      ).hasMatch(businessBarrel),
      isTrue,
    );
  });

  test(
    'Dart rejects lifecycle and assembly from the business surface',
    () async {
      final root = _workspaceRoot();
      final fixture = Directory(
        '${root.path}/.dart_tool',
      ).createTempSync('host-api-boundary-');
      try {
        final original = File('${root.path}/.dart_tool/package_config.json');
        final config =
            jsonDecode(original.readAsStringSync()) as Map<String, dynamic>;
        for (final entry in config['packages'] as List) {
          entry['rootUri'] = original.uri
              .resolve(entry['rootUri'] as String)
              .toString();
        }
        Directory('${fixture.path}/.dart_tool').createSync();
        File(
          '${fixture.path}/.dart_tool/package_config.json',
        ).writeAsStringSync(jsonEncode(config));
        File('${fixture.path}/pubspec.yaml').writeAsStringSync(
          'name: host_boundary_probe\nenvironment:\n  sdk: ^3.10.0\n',
        );
        final probe = File('${fixture.path}/probe.dart');
        probe.writeAsStringSync("""
import 'package:ccrouter/ccrouter.dart';
void probe() {
  CCRouter.initialize();
  CCRouter.shutdown();
  CCRouter.runInitTasks();
  print(CCRouterHost);
  print(CCHostAssembly);
}
""");
        final rejected = await Process.run('fvm', [
          'dart',
          'analyze',
          '--format=machine',
          probe.path,
        ], workingDirectory: root.path);
        expect(rejected.exitCode, isNot(0));
        final errors = '${rejected.stdout}\n${rejected.stderr}';
        for (final name in [
          'initialize',
          'shutdown',
          'runInitTasks',
          'CCRouterHost',
          'CCHostAssembly',
        ]) {
          expect(errors, contains(name));
        }
        probe.writeAsStringSync("""
import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
Future<void> probe() async {
  CCRouterHost.initialize(hostAssembly: CCHostAssembly.fromComponents(components: const []));
  await CCRouterHost.runInitTasks(gate: CCInitTaskGate.appStarted);
  await CCRouterHost.shutdown();
}
""");
        final accepted = await Process.run('fvm', [
          'dart',
          'analyze',
          '--format=machine',
          probe.path,
        ], workingDirectory: root.path);
        expect(
          accepted.exitCode,
          0,
          reason: '${accepted.stdout}\n${accepted.stderr}',
        );
      } finally {
        fixture.deleteSync(recursive: true);
      }
    },
  );

  test('test Runtime binding has a dedicated entry point', () {
    final root = _workspaceRoot();
    final testBarrel = File(
      '${root.path}/packages/ccrouter/lib/ccrouter_test.dart',
    ).readAsStringSync();

    expect(testBarrel, contains("show CCRouterTestBinding"));
    expect(testBarrel, isNot(contains('CCRouterHostBinding')));
    expect(testBarrel, isNot(contains('CCRouterGeneratedServiceBinding')));
    expect(testBarrel, isNot(contains('CCRouterGeneratedCommandBinding')));
  });

  test('Host barrel restores the Adapter SPI snapshot', () {
    final root = _workspaceRoot();
    final hostBarrel = File(
      '${root.path}/packages/ccrouter/lib/ccrouter_host.dart',
    ).readAsStringSync();

    expect(_contractCombinatorNames(hostBarrel, 'show'), _hostContractNames);
    expect(_hostSpiTypes, hasLength(30));
  });
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(
      '${current.path}/packages/ccrouter/lib/ccrouter.dart',
    ).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('CCRouter workspace root was not found.');
    }
    current = parent;
  }
}

Set<String> _contractCombinatorNames(String source, String combinator) {
  final directive = RegExp(
    "export 'package:ccrouter_contracts/ccrouter_contracts.dart'([\\s\\S]*?);",
  ).firstMatch(source)?.group(1);
  if (directive == null) {
    throw StateError('The contracts export directive was not found.');
  }
  final names = RegExp(
    '\\b$combinator\\b([\\s\\S]*)',
  ).firstMatch(directive)?.group(1);
  if (names == null) {
    throw StateError('The $combinator combinator was not found.');
  }
  return names
      .split(',')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toSet();
}
