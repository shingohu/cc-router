import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Service Keys compare exact generic types symmetrically', () {
    final broad = CCServiceKey<Object>('cache');
    final narrow = CCServiceKey<String>('cache');
    expect(broad == narrow, isFalse);
    expect(narrow == broad, isFalse);
    final iterable = CCServiceKey<Iterable<String>>('cache');
    final list = CCServiceKey<List<String>>('cache');
    expect(iterable == list, isFalse);
    expect(list == iterable, isFalse);
  });

  test('equal Service Keys support hash collections without merging types', () {
    final first = CCServiceKey<String>('cache');
    final equal = CCServiceKey<String>('cache');
    final otherType = CCServiceKey<Object>('cache');
    expect(first, equal);
    expect(first.hashCode, equal.hashCode);
    expect({first, equal, otherType}, hasLength(2));
    final values = <CCServiceKey<Object>, String>{
      first: 'string',
      otherType: 'object',
    };
    expect(values[equal], 'string');
    expect(values[CCServiceKey<Object>('cache')], 'object');
    expect(first == CCServiceKey<String>('other'), isFalse);
  });
}
