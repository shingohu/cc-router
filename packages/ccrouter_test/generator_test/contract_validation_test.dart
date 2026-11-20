import 'package:ccrouter_generator/src/contract_validation.dart';
import 'package:test/test.dart';

void main() {
  test('all Contract builders use strict Runtime-compatible SemVer', () {
    for (final version in ['0.1.0', '1.2.3-rc.1+build.2', '2.0.0+001']) {
      expect(isContractSemanticVersion(version), isTrue, reason: version);
    }
    for (final version in [
      ' 1.2.3',
      '1.2.3 ',
      '1.2.3\n',
      '01.2.3',
      '1.2.3-01',
      'latest',
    ]) {
      expect(isContractSemanticVersion(version), isFalse, reason: version);
    }
  });
}
