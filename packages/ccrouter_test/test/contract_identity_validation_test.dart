import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_core/ccrouter_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

CCContractBundleDescriptor _installed(
  CCContractKind kind,
  String id,
  String owner,
) => CCContractBundleDescriptor(
  packageName: 'owner_package',
  packageVersion: '1.0.0',
  contracts: [
    CCContractDescriptor(
      kind: kind,
      id: id,
      ownerComponentId: owner,
      version: '1.0.0',
      shapeFingerprint: _fingerprint,
    ),
  ],
);

CCContractBundleDescriptor _consumer(
  CCContractKind kind,
  String id,
  String owner, {
  String fingerprint = _fingerprint,
}) => CCContractBundleDescriptor(
  packageName: 'consumer_package',
  packageVersion: '1.0.0',
  requirements: [
    CCContractRequirement(
      kind: kind,
      contractId: id,
      consumerPackage: 'consumer_package',
      ownerComponentId: owner,
      requiredVersionRange: '1.0.0',
      requiredShapeFingerprint: fingerprint,
    ),
  ],
);

void main() {
  final invalid = [
    ('', 'owner'),
    ('Bad ID', 'owner'),
    ('a' * 129, 'owner'),
    ('owner.service', ''),
    ('owner.service', 'Owner'),
    ('owner.service', 'owner.Team'),
    ('owner.service', 'a' * 129),
  ];
  for (final kind in CCContractKind.values) {
    test(
      '${kind.name} installed identities reject malformed generated inputs',
      () {
        for (final (id, owner) in invalid) {
          final issues = CCContractBundleDescriptor.validate([
            _installed(kind, id, owner),
          ]);
          expect(issues, hasLength(1), reason: '$id / $owner');
          expect(
            issues.single.code,
            CCContractCompatibilityCode.staleGeneratedOutput,
          );
          expect(issues.single.packageName, 'owner_package');
        }
      },
    );
    test(
      '${kind.name} malformed requirements are stale rather than missing',
      () {
        for (final (id, owner) in invalid) {
          final issues = CCContractBundleDescriptor.validate([
            _consumer(kind, id, owner),
          ]);
          expect(issues, hasLength(1), reason: '$id / $owner');
          expect(
            issues.single.code,
            CCContractCompatibilityCode.staleGeneratedOutput,
          );
          expect(issues.single.packageName, 'consumer_package');
        }
      },
    );
    test(
      '${kind.name} distinguishes malformed consumer fingerprint from valid drift',
      () {
        for (final (fingerprint, code) in [
          ('bad', CCContractCompatibilityCode.staleGeneratedOutput),
          ('b' * 64, CCContractCompatibilityCode.fingerprintChanged),
        ]) {
          final issues = CCContractBundleDescriptor.validate([
            _installed(kind, 'owner.service', 'owner'),
            _consumer(kind, 'owner.service', 'owner', fingerprint: fingerprint),
          ]);
          expect(issues, hasLength(1));
          expect(issues.single.code, code);
        }
      },
    );
    test(
      '${kind.name} preserves exact identity length boundary and capitalized segments',
      () {
        for (final (id, owner) in [
          ('a' * 128, 'a' * 128),
          ('owner.MyService', 'owner_component'),
        ]) {
          expect(
            CCContractBundleDescriptor.validate([
              _installed(kind, id, owner),
              _consumer(kind, id, owner),
            ]),
            isEmpty,
          );
        }
      },
    );
  }
  test(
    'Host and Runtime reject malformed Contract identity before startup',
    () {
      final bundle = _installed(CCContractKind.service, '', 'owner');
      expect(
        () => CCHostAssembly.fromComponents(
          components: [],
          contractBundle: bundle,
        ),
        throwsA(
          isA<CCHostAssemblyError>().having(
            (error) => error.type,
            'type',
            CCHostAssemblyErrorCode.contractCompatibility,
          ),
        ),
      );
      expect(
        () => CCRouterRuntime.forTesting(contractBundle: bundle),
        throwsA(isA<CCContractCompatibilityError>()),
      );
    },
  );
}
