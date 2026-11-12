import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/widgets.dart';

import 'generated_route_types.dart';
import 'multiple_extra_contract_fixture.dart';

/// Nested data whose identity must survive the process-local Extra boundary.
final class GeneratedExtraSnapshot {
  /// Retains the caller's frozen snapshot without copying nested DTOs.
  const GeneratedExtraSnapshot(this.sections);

  /// Nested DTO collections kept out of URI encoding.
  final Map<String, List<GeneratedSnapshot>> sections;
}

/// Required and defaulted Extras sharing one generated transport envelope.
@CCRoute<void>(
  id: 'generated_route_fixture.multi-extra',
  pattern: CCPathPattern('/generated/multi-extra/:id'),
)
final class GeneratedMultiExtraPage {
  /// Creates a destination with both URI and process-local parameters.
  const GeneratedMultiExtraPage({
    required this.id,
    @CCQueryParam() this.tab = 'summary',
    @CCExtraParam() required this.snapshot,
    @CCExtraParam() this.revision = 3,
    @CCExtraParam() this.enabled = true,
  });

  /// Identity encoded in the URI rather than in the envelope.
  final String id;

  /// Shareable tab selection.
  final String tab;

  /// Required process-local snapshot retained by identity.
  final GeneratedExtraSnapshot snapshot;

  /// Nullable default used to distinguish explicit null from absence.
  final int? revision;

  /// Non-nullable Extra supported through its constructor default.
  final bool enabled;
}

/// Optional Extras whose absence remains reconstructible as a parent route.
@CCRoute<void>(
  id: 'generated_route_fixture.optional-extras',
  pattern: CCPathPattern('/generated/optional-extras'),
  deepLink: CCDeepLinkPolicy.enabled,
)
final class GeneratedOptionalExtrasPage extends StatelessWidget {
  /// Leaves both process-local fields absent unless the caller supplies them.
  const GeneratedOptionalExtrasPage({
    @CCExtraParam() this.snapshot,
    @CCExtraParam() this.revision = null,
    super.key,
  });

  /// Optional snapshot retained by identity when present.
  final GeneratedExtraSnapshot? snapshot;

  /// Explicit null default equivalent to omitting the envelope.
  final int? revision;

  /// Stable marker for Managed parent-stack widget tests.
  @override
  Widget build(BuildContext context) => const Text('optional-extras');
}

/// Leaf used to exercise real Managed parent reconstruction.
@CCRoute<void>(
  id: 'generated_route_fixture.extras-child',
  pattern: CCPathPattern('/generated/optional-extras/child'),
  placement: CCRoutePlacement(
    parentRouteId: 'generated_route_fixture.optional-extras',
  ),
)
final class GeneratedExtrasChildPage extends StatelessWidget {
  /// Creates the leaf without inferring Extra from its parent.
  const GeneratedExtrasChildPage({super.key});

  /// Stable marker for the reconstructed leaf.
  @override
  Widget build(BuildContext context) => const Text('extras-child');
}

/// Optional Extras with non-null defaults cannot erase explicit null values.
@CCRoute<void>(
  id: 'generated_route_fixture.default-extras',
  pattern: CCPathPattern('/generated/default-extras'),
  deepLink: CCDeepLinkPolicy.enabled,
)
final class GeneratedDefaultExtrasPage {
  /// Uses defaults only when the entire process-local envelope is absent.
  const GeneratedDefaultExtrasPage({
    @CCExtraParam() this.label = 'fallback',
    @CCExtraParam() this.revision = 3,
  });

  /// Nullable default that may also be explicitly cleared.
  final String? label;

  /// Nullable default that may also be explicitly cleared.
  final int? revision;
}

/// Owner page bound to the independently generated Pure Dart Extra contract.
@CCRouteImplementation(GeneratedMultiExtrasRouteContract)
final class GeneratedContractExtrasPage {
  /// Retains the contract's typed values without decoding a second envelope.
  const GeneratedContractExtrasPage({required this.items, this.label});

  /// Collection supplied through the public Route Intent.
  final List<String> items;

  /// Optional label supplied through the public Route Intent.
  final String? label;
}
