import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'navigation_lab_component.dart';

part 'ccrouter_generated/presentation_pages.route.g.dart';

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.presentation.fade',
  pattern: CCPathPattern('/lab/presentation/fade'),
  presentation: CCPagePresentation(transition: CCPageTransitionType.fade),
)
final class DemoFadePage extends StatelessWidget {
  const DemoFadePage({super.key});

  @override
  Widget build(BuildContext context) => const _PresentationPage(
    title: 'Fade Page',
    icon: Icons.blur_on,
    color: Color(0xFF00695C),
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.presentation.scale',
  pattern: CCPathPattern('/lab/presentation/scale'),
  presentation: CCPagePresentation(transition: CCPageTransitionType.scale),
)
final class DemoScalePage extends StatelessWidget {
  const DemoScalePage({super.key});

  @override
  Widget build(BuildContext context) => const _PresentationPage(
    title: 'Scale Page',
    icon: Icons.zoom_out_map,
    color: Color(0xFF6A1B9A),
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.presentation.cupertino',
  pattern: CCPathPattern('/lab/presentation/cupertino'),
  presentation: CCPagePresentation(routeType: CCPageRouteType.cupertino),
)
final class DemoCupertinoPage extends StatelessWidget {
  const DemoCupertinoPage({super.key});

  @override
  Widget build(BuildContext context) => const CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(middle: Text('Cupertino PageRoute')),
    child: SafeArea(child: Center(child: Text('显式 Cupertino 页面与返回手势语义'))),
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.presentation.bottom_page',
  pattern: CCPathPattern('/lab/presentation/bottom-page'),
  presentation: CCPagePresentation(
    transition: CCPageTransitionType.slideFromBottom,
    fullscreenDialog: true,
  ),
  description: '普通全屏 Page 从底部滑入，不是 BottomSheet。',
)
final class DemoBottomPage extends StatelessWidget {
  const DemoBottomPage({super.key});

  @override
  Widget build(BuildContext context) => const _PresentationPage(
    title: '全屏页面从底部滑入',
    icon: Icons.vertical_align_top,
    color: Color(0xFF1565C0),
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.presentation.transparent',
  pattern: CCPathPattern('/lab/presentation/transparent'),
  presentation: CCPagePresentation(
    transition: CCPageTransitionType.slideFromBottom,
    opaque: false,
    fullscreenDialog: true,
  ),
  description: '用于海报分享预览的透明全屏 Page。',
)
final class DemoTransparentPage extends StatelessWidget {
  const DemoTransparentPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black.withValues(alpha: 0.72),
    body: SafeArea(
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 360,
              height: 460,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 72,
                    color: Color(0xFF00695C),
                  ),
                  SizedBox(height: 20),
                  Text('透明全屏海报预览', style: TextStyle(fontSize: 22)),
                  SizedBox(height: 8),
                  Text('下方页面仍参与绘制，但当前 Route 是主 Route。'),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton.filledTonal(
              tooltip: '关闭',
              onPressed: () => CCRouter.navigator.pop(),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    ),
  );
}

@CCRoute<String>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.presentation.dialog',
  pattern: CCPathPattern('/lab/presentation/dialog'),
  presentation: CCDialogPresentation(
    routeType: CCDialogRouteType.material,
    barrierDismissible: true,
  ),
)
final class DemoDialogPage extends StatelessWidget {
  const DemoDialogPage({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Managed Dialog Route'),
    content: const Text('它具备 typed result、Interceptor、Aspect 和 RouteEntry。'),
    actions: [
      TextButton(
        onPressed: () => CCRouter.navigator.pop(result: 'dialog:cancel'),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => CCRouter.navigator.pop(result: 'dialog:confirmed'),
        child: const Text('确认'),
      ),
    ],
  );
}

@CCRoute<String>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.presentation.sheet',
  pattern: CCPathPattern('/lab/presentation/sheet'),
  presentation: CCModalBottomSheetPresentation(
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
  ),
)
final class DemoBottomSheetPage extends StatelessWidget {
  const DemoBottomSheetPage({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Managed BottomSheet',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text('拖拽、点击 barrier 或按钮均应只关闭这一个 Managed Entry。'),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => CCRouter.navigator.pop(result: 'sheet:selected'),
          child: const Text('选择并返回'),
        ),
      ],
    ),
  );
}

final class _PresentationPage extends StatelessWidget {
  const _PresentationPage({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: color),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => CCRouter.navigator.pop(),
            icon: const Icon(Icons.close),
            label: const Text('关闭'),
          ),
        ],
      ),
    ),
  );
}

CCRouteIntent<void> demoFadeIntent() => _DemoFadePageRoute.intent();
CCRouteIntent<void> demoScaleIntent() => _DemoScalePageRoute.intent();
CCRouteIntent<void> demoCupertinoIntent() => _DemoCupertinoPageRoute.intent();
CCRouteIntent<void> demoBottomPageIntent() => _DemoBottomPageRoute.intent();
CCRouteIntent<void> demoTransparentIntent() =>
    _DemoTransparentPageRoute.intent();
CCRouteIntent<String> demoDialogIntent() => _DemoDialogPageRoute.intent();
CCRouteIntent<String> demoBottomSheetIntent() =>
    _DemoBottomSheetPageRoute.intent();
