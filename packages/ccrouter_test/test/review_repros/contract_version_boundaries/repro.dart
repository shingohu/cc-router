import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fragment_lifecycle/repro.dart' as ui;

void main() {
  for (final sample in <(String, String, bool)>[
    ('1.2.3', '1.2.3', true),
    ('=1.2.3', '1.2.3', true),
    ('^1.2.3', '1.9.0', true),
    ('~1.2.3', '1.3.0', false),
    ('>=1.2.3 <2.0.0', '1.5.0', true),
    ('>=1.2.3', '1.5.0', true),
    ('>1.2.3', '1.2.3', false),
    ('<=1.2.3', '1.2.3', true),
    ('<1.2.3', '1.0.0', true),
    ('>=1.2.3\t<2.0.0', '1.5.0', true),
  ]) {
    test('documented version range ${sample.$1}', () {
      final range = CCContractVersionRange.parse(sample.$1);
      expect(range.allowsText(sample.$2), sample.$3);
    });
  }

  test('parsed SemVer retains immutable prerelease identifiers', () {
    final version = CCSemVer.parse('1.2.3-rc.1');
    expect(version.isStable, isFalse);
    expect(() => version.preRelease.clear(), throwsUnsupportedError);
    expect(version.toString(), '1.2.3-rc.1');
  });

  for (final range in ['^1.0.0', '>=1.0.0']) {
    test('UI Host assembly accepts documented version range $range', () {
      expect(() => ui.assembly(versionRange: range), returnsNormally);
    });
  }
}
