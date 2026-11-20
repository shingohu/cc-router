import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fingerprint =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  for (final (version, range, ownerError, consumerError, outOfRange) in [
    ('bad', '1.0.0', true, false, false),
    ('1.0.0', 'bad', false, true, false),
    ('bad', 'bad', true, true, false),
    ('1.0.0', '^2.0.0', false, false, true),
    ('1.0.0', '^1.0.0', false, false, false),
  ]) {
    test('Contract errors belong to their actual input: $version / $range', () {
      final issues = CCContractBundleDescriptor.validate([
        CCContractBundleDescriptor(
          packageName: 'owner_package',
          packageVersion: '1.0.0',
          contracts: [
            CCContractDescriptor(
              kind: CCContractKind.service,
              id: 'owner.service',
              ownerComponentId: 'owner',
              version: version,
              shapeFingerprint: fingerprint,
            ),
          ],
        ),
        CCContractBundleDescriptor(
          packageName: 'consumer_package',
          packageVersion: '1.0.0',
          requirements: [
            CCContractRequirement(
              kind: CCContractKind.service,
              contractId: 'owner.service',
              consumerPackage: 'consumer_package',
              ownerComponentId: 'owner',
              requiredVersionRange: range,
              requiredShapeFingerprint: fingerprint,
            ),
          ],
        ),
      ]);
      expect(
        issues.any((issue) => issue.packageName == 'owner_package'),
        ownerError,
      );
      expect(
        issues.any(
          (issue) =>
              issue.packageName == 'consumer_package' &&
              issue.code == CCContractCompatibilityCode.staleGeneratedOutput,
        ),
        consumerError,
      );
      expect(
        issues.any(
          (issue) =>
              issue.code == CCContractCompatibilityCode.versionOutOfRange,
        ),
        outOfRange,
      );
      expect(
        issues,
        hasLength(
          (ownerError ? 1 : 0) + (consumerError ? 1 : 0) + (outOfRange ? 1 : 0),
        ),
      );
    });
  }
}
