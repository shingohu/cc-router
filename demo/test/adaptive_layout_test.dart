import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_demo/adaptive_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Host layout metrics classify compact, medium, and expanded', () {
    final compact = DemoHostLayoutMetrics(
      hostId: 'phone',
      width: 599,
      height: 800,
    );
    final medium = DemoHostLayoutMetrics(
      hostId: 'tablet',
      width: 600,
      height: 900,
    );
    final expanded = DemoHostLayoutMetrics(
      hostId: 'desktop',
      width: 1200,
      height: 900,
    );

    expect(compact.sizeClass, DemoHostSizeClass.compact);
    expect(medium.sizeClass, DemoHostSizeClass.medium);
    expect(expanded.sizeClass, DemoHostSizeClass.expanded);
    expect(
      const DemoAdaptiveLayoutPolicy().select(compact),
      DemoAdaptiveLayoutKind.singlePane,
    );
    expect(
      const DemoAdaptiveLayoutPolicy().select(expanded),
      DemoAdaptiveLayoutKind.splitPane,
    );
  });

  test('display features and route placement retain Host isolation', () {
    const hinge = DemoDisplayFeature(
      type: DemoDisplayFeatureType.hinge,
      bounds: DemoLayoutRect(left: 500, top: 0, width: 20, height: 800),
      separating: true,
    );
    final metrics = DemoHostLayoutMetrics(
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
    final outlets = DemoAdaptiveOutletPolicy(
      primaryOutlet: 'list',
      secondaryOutlet: 'detail',
      multiPaneOutlets: const ['inspector'],
    );

    expect(outlets.activeOutletsFor(DemoAdaptiveLayoutKind.singlePane), [
      'list',
    ]);
    expect(outlets.activeOutletsFor(DemoAdaptiveLayoutKind.splitPane), [
      'list',
      'detail',
    ]);
    expect(outlets.activeOutletsFor(DemoAdaptiveLayoutKind.multiPane), [
      'list',
      'detail',
      'inspector',
    ]);
    expect(
      () => DemoAdaptiveOutletPolicy(
        primaryOutlet: 'list',
        secondaryOutlet: 'list',
      ),
      throwsArgumentError,
    );
  });
}
