import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter/ccrouter_host.dart';
import 'package:ccrouter_demo/ccrouter_demo.dart';
import 'package:ccrouter_demo/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    CCRouterHost.initialize(hostAssembly: ccrouterGeneratedHostAssembly);
  });

  tearDown(CCRouterHost.shutdown);

  testWidgets('native Managed Backend materializes Demo page families', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CCRouterDemoApp(
        listenForPlatformLinks: false,
        useManagedBackend: true,
      ),
    );
    await tester.pumpAndSettle();

    final cases = <({String uri, Finder content})>[
      (uri: '/lab/presentation/fade', content: find.text('Fade Page')),
      (uri: '/lab/presentation/scale', content: find.text('Scale Page')),
      (
        uri: '/lab/presentation/cupertino',
        content: find.text('显式 Cupertino 页面与返回手势语义'),
      ),
      (uri: '/lab/presentation/bottom-page', content: find.text('全屏页面从底部滑入')),
      (uri: '/lab/presentation/transparent', content: find.text('透明全屏海报预览')),
      (
        uri: '/lab/presentation/dialog',
        content: find.text('Managed Dialog Route'),
      ),
      (
        uri: '/lab/presentation/sheet',
        content: find.text('Managed BottomSheet'),
      ),
      (uri: '/shell/feed', content: find.text('Shell Feed')),
      (uri: '/shell/settings', content: find.text('Shell Settings')),
      (uri: '/shell/feed/7', content: find.text('Shell Detail #7')),
      (uri: '/workspace/home', content: find.text('Workspace Home')),
      (uri: '/workspace/home/42', content: find.text('Workspace Detail #42')),
      (uri: '/workspace/activity', content: find.text('Workspace Activity')),
      (uri: '/workspace/profile', content: find.text('Workspace Profile')),
    ];

    for (final testCase in cases) {
      await CCRouter.navigator.open(Uri.parse(testCase.uri));
      await tester.pumpAndSettle();
      expect(testCase.content, findsWidgets, reason: testCase.uri);
      expect(tester.takeException(), isNull, reason: testCase.uri);
      await CCRouter.navigator.maybePop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'pop ${testCase.uri}');
    }
  });
}
