import 'package:ccrouter_generator/src/generated_client_naming.dart';
import 'package:test/test.dart';

void main() {
  test('default Client names preserve the established suffix rule', () {
    expect(defaultServiceClientMember('OrderSummaryService'), 'orderSummary');
    expect(defaultCommandClientMember('SubmitOrderCommand'), 'submitOrder');
    expect(defaultServiceClientMember('Service'), 'service');
    expect(defaultCommandClientMember('Command'), 'command');
  });

  test('default Client names do not guess acronym boundaries', () {
    expect(defaultServiceClientMember('HTTPService'), 'hTTP');
    expect(defaultCommandClientMember('URLCommand'), 'uRL');
  });

  test('generated Client aliases reject keywords and invalid casing', () {
    expect(isGeneratedClientMemberName('network'), isTrue);
    expect(isGeneratedClientMemberName('networkClient2'), isTrue);
    expect(isGeneratedClientMemberName('class'), isFalse);
    expect(isGeneratedClientMemberName('Network'), isFalse);
    expect(isGeneratedClientMemberName('network.client'), isFalse);
  });
}
