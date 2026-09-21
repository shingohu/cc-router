import 'dart:io';

import 'package:ccrouter/ccrouter_host.dart' as host;
import 'package:test/test.dart';

const _adapterSpiNames = <String>{
  'CCNavigationAdapter',
  'CCNavigationAdapterCapabilities',
  'CCNavigationAdapterCapabilitySource',
  'CCNavigationAdapterHostBinding',
  'CCNavigationBackendEntrySnapshot',
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
};

const _hostSpiTypes = <Type>[
  host.CCNavigationAdapter,
  host.CCNavigationAdapterCapabilities,
  host.CCNavigationAdapterCapabilitySource,
  host.CCNavigationAdapterHostBinding,
  host.CCNavigationBackendEntrySnapshot,
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
  host.CCGeneratedHostAssembly,
  host.CCGeneratedPackageBundleError,
  host.CCGeneratedPackageBundleErrorType,
  host.CCFlutterRouteFactory,
  host.CCFlutterPage,
  host.CCFlutterBottomSheetPage,
  host.CCFlutterDialogPage,
];

void main() {
  test('business barrel hides the complete Adapter SPI snapshot', () {
    final root = _workspaceRoot();
    final businessBarrel = File(
      '${root.path}/packages/ccrouter/lib/ccrouter.dart',
    ).readAsStringSync();

    expect(_contractCombinatorNames(businessBarrel, 'hide'), _adapterSpiNames);
  });

  test('Host barrel restores the Adapter SPI snapshot', () {
    final root = _workspaceRoot();
    final hostBarrel = File(
      '${root.path}/packages/ccrouter/lib/ccrouter_host.dart',
    ).readAsStringSync();

    expect(_contractCombinatorNames(hostBarrel, 'show'), _hostContractNames);
    expect(_hostSpiTypes, hasLength(29));
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
