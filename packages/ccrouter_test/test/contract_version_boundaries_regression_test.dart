import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'review_repros/contract_version_boundaries/repro.dart' as fixture;

void main() {
  fixture.main();
  for (final range in [
    '>=1.2.3\n<2.0.0',
    '>=1.2.3\r\n<2.0.0',
    '\t>=1.2.3\t<2.0.0\n',
  ]) {
    test('whitespace comparator boundaries: $range', () {
      final parsed = CCContractVersionRange.parse(range);
      expect(parsed.allowsText('1.2.3'), isTrue);
      expect(parsed.allowsText('1.9.9'), isTrue);
      expect(parsed.allowsText('1.2.2'), isFalse);
      expect(parsed.allowsText('2.0.0'), isFalse);
    });
  }
  for (final range in [
    '>=',
    '=>1.2.3',
    '>=1.2.3 || <2.0.0',
    '>=1.2.3 bad',
    '1.2',
  ]) {
    test('invalid comparator stays rejected: $range', () {
      expect(() => CCContractVersionRange.parse(range), throwsFormatException);
    });
  }
  test('prerelease mutation cannot change collection identity or ordering', () {
    final version = CCSemVer.parse('1.2.3-rc.1');
    final originalHash = version.hashCode;
    final values = {version};
    expect(() => version.preRelease[0] = 'release', throwsUnsupportedError);
    expect(() => version.preRelease.add('next'), throwsUnsupportedError);
    expect(values.contains(CCSemVer.parse('1.2.3-rc.1')), isTrue);
    expect(version.hashCode, originalHash);
    expect(version < CCSemVer.parse('1.2.3'), isTrue);
  });
}
