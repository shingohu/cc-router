import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'prerelease identifiers use decimal SemVer ordering without int conversion',
    () {
      final identifiers = [
        '0',
        '2',
        '16',
        '999999999999999999999',
        '1000000000000000000000',
        '-0',
        '-1',
        '0x10',
        'alpha',
      ];
      final versions = [
        for (final id in identifiers) CCSemVer.parse('1.0.0-$id'),
      ];
      for (var i = 0; i < versions.length; i++) {
        expect(versions[i], CCSemVer.parse('1.0.0-${identifiers[i]}+build'));
        expect(
          versions[i].hashCode,
          CCSemVer.parse('1.0.0-${identifiers[i]}+build').hashCode,
        );
        for (var j = i + 1; j < versions.length; j++) {
          expect(
            versions[i] < versions[j],
            isTrue,
            reason: '${identifiers[i]} < ${identifiers[j]}',
          );
          expect(versions[j] > versions[i], isTrue);
          expect(versions[i] == versions[j], isFalse);
        }
      }
      expect(versions.toSet(), hasLength(identifiers.length));
    },
  );

  test(
    'ordinary caret and tilde ranges match their explicit comparator bounds',
    () {
      final candidates = [
        for (var major = 0; major <= 3; major++)
          for (var minor = 0; minor <= 3; minor++)
            for (var patch = 0; patch <= 3; patch++)
              for (final suffix in ['', '-rc', '-2'])
                CCSemVer.parse('$major.$minor.$patch$suffix'),
      ];
      for (var major = 0; major <= 2; major++) {
        for (var minor = 0; minor <= 2; minor++) {
          for (var patch = 0; patch <= 2; patch++) {
            final minimum = '$major.$minor.$patch';
            final caretMaximum = major > 0
                ? '${major + 1}.0.0'
                : minor > 0
                ? '0.${minor + 1}.0'
                : '0.0.${patch + 1}';
            for (final (prefix, upper) in [
              ('^', caretMaximum),
              ('~', '$major.${minor + 1}.0'),
            ]) {
              final parsed = CCContractVersionRange.parse('$prefix$minimum');
              final explicit = CCContractVersionRange.parse(
                '>=$minimum <$upper',
              );
              for (final candidate in candidates) {
                expect(
                  parsed.allows(candidate),
                  explicit.allows(candidate),
                  reason: '$prefix$minimum compared with $candidate',
                );
              }
            }
          }
        }
      }
    },
  );

  const maximum = '9223372036854775807';
  for (final (range, allowed, denied) in [
    ('^$maximum.0.0', '$maximum.1.0', '1.0.0'),
    ('^0.$maximum.0', '0.$maximum.1', '1.0.0-rc'),
    ('^0.0.$maximum', '0.0.$maximum', '0.1.0-rc'),
    ('~1.$maximum.0', '1.$maximum.1', '2.0.0-rc'),
  ]) {
    test('$range includes its lower bound without successor overflow', () {
      final parsed = CCContractVersionRange.parse(range);
      expect(parsed.allowsText(range.substring(1)), isTrue);
      expect(parsed.allowsText(allowed), isTrue);
      expect(parsed.allowsText(denied), isFalse);
    });
  }

  test(
    'ordinary range upper boundaries retain literal comparator semantics',
    () {
      for (final (range, prerelease, stable) in [
        ('^1.2.3', '2.0.0-rc', '2.0.0'),
        ('^0.2.3', '0.3.0-rc', '0.3.0'),
        ('^0.0.3', '0.0.4-rc', '0.0.4'),
        ('~1.2.3', '1.3.0-rc', '1.3.0'),
      ]) {
        final parsed = CCContractVersionRange.parse(range);
        expect(parsed.allowsText(prerelease), isTrue);
        expect(parsed.allowsText(stable), isFalse);
      }
    },
  );

  test(
    'bundle compatibility distinguishes numeric and alphanumeric prereleases',
    () {
      const fingerprint =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      for (final (range, compatible) in [
        ('<1.0.0-0x10', true),
        ('1.0.0-0x10', false),
      ]) {
        final issues = CCContractBundleDescriptor.validate([
          CCContractBundleDescriptor(
            packageName: 'owner',
            packageVersion: '1.0.0',
            contracts: const [
              CCContractDescriptor(
                kind: CCContractKind.service,
                id: 'owner.service',
                ownerComponentId: 'owner',
                version: '1.0.0-16',
                shapeFingerprint: fingerprint,
              ),
            ],
          ),
          CCContractBundleDescriptor(
            packageName: 'consumer',
            packageVersion: '1.0.0',
            requirements: [
              CCContractRequirement(
                kind: CCContractKind.service,
                contractId: 'owner.service',
                consumerPackage: 'consumer',
                ownerComponentId: 'owner',
                requiredVersionRange: range,
                requiredShapeFingerprint: fingerprint,
              ),
            ],
          ),
        ]);
        expect(
          issues.any(
            (issue) =>
                issue.code == CCContractCompatibilityCode.versionOutOfRange,
          ),
          !compatible,
        );
      }
    },
  );
}
