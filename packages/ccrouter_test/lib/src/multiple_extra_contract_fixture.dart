import 'package:ccrouter_contracts/ccrouter_contracts.dart';

/// Pure Dart contract exercising multi-Extra generation without Flutter types.
@CCRouteContract<void>(
  componentId: CCComponentId('generated_route_fixture'),
  id: 'generated_route_fixture.contract-extras',
  pattern: CCPathPattern('/generated/contract-extras'),
)
abstract class GeneratedMultiExtrasRouteContract {
  /// Retains the caller's collection and optional label in process memory.
  const GeneratedMultiExtrasRouteContract({
    @CCExtraParam() required this.items,
    @CCExtraParam() this.label,
  });

  /// Typed collection whose identity must survive encoding and decoding.
  final List<String> items;

  /// Optional accompanying process-local label.
  final String? label;
}
