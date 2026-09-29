import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supports exact, caret, tilde, and comparator Contract ranges', () {
    expect(CCContractVersionRange.parse('1.2.3').allowsText('1.2.3'), isTrue);
    expect(CCContractVersionRange.parse('1.2.3').allowsText('1.2.4'), isFalse);
    expect(CCContractVersionRange.parse('^1.2.3').allowsText('1.9.0'), isTrue);
    expect(CCContractVersionRange.parse('^1.2.3').allowsText('2.0.0'), isFalse);
    expect(CCContractVersionRange.parse('~1.2.3').allowsText('1.2.9'), isTrue);
    expect(CCContractVersionRange.parse('~1.2.3').allowsText('1.3.0'), isFalse);
    expect(
      CCContractVersionRange.parse('>=1.2.0 <2.0.0').allowsText('1.8.1'),
      isTrue,
    );
  });

  test('reports missing, owner, version, and fingerprint incompatibility', () {
    const descriptor = CCContractDescriptor(
      kind: CCContractKind.service,
      id: 'orders.summary',
      ownerComponentId: 'orders_component',
      version: '1.2.0',
      shapeFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final issues = CCContractBundleDescriptor.validate([
      CCContractBundleDescriptor(
        packageName: 'orders_contracts',
        packageVersion: '1.0.0',
        contracts: const [descriptor],
      ),
      CCContractBundleDescriptor(
        packageName: 'payment',
        packageVersion: '1.0.0',
        requirements: const [
          CCContractRequirement(
            kind: CCContractKind.service,
            contractId: 'missing.service',
            consumerPackage: 'payment',
            ownerComponentId: 'orders_component',
            requiredVersionRange: '1.0.0',
            requiredShapeFingerprint:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
          CCContractRequirement(
            kind: CCContractKind.service,
            contractId: 'orders.summary',
            consumerPackage: 'payment',
            ownerComponentId: 'other_component',
            requiredVersionRange: '1.2.0',
            requiredShapeFingerprint:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
          CCContractRequirement(
            kind: CCContractKind.service,
            contractId: 'orders.summary',
            consumerPackage: 'payment',
            ownerComponentId: 'orders_component',
            requiredVersionRange: '^2.0.0',
            requiredShapeFingerprint:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ),
        ],
      ),
    ]);

    expect(
      issues.map((issue) => issue.code),
      containsAllInOrder([
        CCContractCompatibilityCode.missing,
        CCContractCompatibilityCode.ownerMismatch,
        CCContractCompatibilityCode.versionOutOfRange,
      ]),
    );
    expect(
      issues.map((issue) => issue.code),
      contains(CCContractCompatibilityCode.fingerprintChanged),
    );
  });

  test('Host assembly carries a merged Contract bundle', () {
    final bundle = CCGeneratedPackageBundle(
      packageName: 'orders',
      packageVersion: '1.0.0',
      contentFingerprint: 'orders',
      contractBundle: CCContractBundleDescriptor(
        packageName: 'orders',
        packageVersion: '1.0.0',
        contracts: const [
          CCContractDescriptor(
            kind: CCContractKind.command,
            id: 'orders.create',
            ownerComponentId: 'orders_component',
            version: '1.0.0',
            shapeFingerprint:
                'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          ),
        ],
      ),
    );

    final assembly = CCGeneratedHostAssembly.fromPackageBundles([bundle]);

    expect(assembly.contractBundle?.contracts.single.id, 'orders.create');
  });

  test('Runtime rejects an incompatible generated Contract bundle', () {
    final bundle = CCContractBundleDescriptor(
      packageName: 'payment',
      packageVersion: '1.0.0',
      requirements: const [
        CCContractRequirement(
          kind: CCContractKind.service,
          contractId: 'orders.summary',
          consumerPackage: 'payment',
          ownerComponentId: 'orders_component',
          requiredVersionRange: '1.0.0',
          requiredShapeFingerprint:
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        ),
      ],
    );

    expect(
      () => CCRouterRuntime.forTesting(contractBundle: bundle),
      throwsA(isA<CCContractCompatibilityError>()),
    );
  });
}
