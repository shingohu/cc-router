import 'package:ccrouter_contracts/ccrouter_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('Host layout metrics classify compact, medium, and expanded', () {
    final compact = CCHostLayoutMetrics(
      hostId: 'phone',
      width: 599,
      height: 800,
    );
    final medium = CCHostLayoutMetrics(
      hostId: 'tablet',
      width: 600,
      height: 900,
    );
    final expanded = CCHostLayoutMetrics(
      hostId: 'desktop',
      width: 1200,
      height: 900,
    );

    expect(compact.sizeClass, CCWindowSizeClass.compact);
    expect(medium.sizeClass, CCWindowSizeClass.medium);
    expect(expanded.sizeClass, CCWindowSizeClass.expanded);
    expect(
      const CCAdaptivePresentationPolicy().select(compact),
      CCAdaptiveLayoutKind.singlePane,
    );
    expect(
      const CCAdaptivePresentationPolicy().select(expanded),
      CCAdaptiveLayoutKind.splitPane,
    );
  });

  test('display features and route placement retain Host isolation', () {
    const hinge = CCDisplayFeature(
      type: CCDisplayFeatureType.hinge,
      bounds: CCLayoutRect(left: 500, top: 0, width: 20, height: 800),
      separating: true,
    );
    final metrics = CCHostLayoutMetrics(
      hostId: 'foldable-main',
      width: 1020,
      height: 800,
      displayFeatures: [hinge],
    );
    final placement = CCRoutePlacement(
      hostId: metrics.hostId,
      navigatorOutlet: 'detail',
    );

    expect(metrics.hasSeparatingFeature, isTrue);
    expect(placement.hostId, 'foldable-main');
    expect(placement.navigatorOutlet, 'detail');
  });

  test('adaptive Outlet policy maps one, two, and multiple panes', () {
    final outlets = CCAdaptiveOutletPolicy(
      primaryOutlet: 'list',
      secondaryOutlet: 'detail',
      multiPaneOutlets: const ['inspector'],
    );

    expect(outlets.activeOutletsFor(CCAdaptiveLayoutKind.singlePane), ['list']);
    expect(outlets.activeOutletsFor(CCAdaptiveLayoutKind.splitPane), [
      'list',
      'detail',
    ]);
    expect(outlets.activeOutletsFor(CCAdaptiveLayoutKind.multiPane), [
      'list',
      'detail',
      'inspector',
    ]);
    expect(
      () => CCAdaptiveOutletPolicy(
        primaryOutlet: 'list',
        secondaryOutlet: 'list',
      ),
      throwsArgumentError,
    );
  });
}
