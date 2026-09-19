import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'lab_configuration.dart';
import 'navigation_lab_component.dart';

part 'ccrouter_generated/detail_page.route.g.dart';

@CCRoute<String>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.detail',
  patterns: [
    CCPathPattern(
      '/lab/detail/:id',
      primary: true,
      constraints: {'id': r'\d+'},
    ),
    CCPathPattern('/lab/item/:id'),
    CCUriPattern('ccrouter://lab/detail/:id'),
    CCUriPattern('https://ccrouter.example/lab/detail/:id'),
  ],
  deepLink: CCDeepLinkPolicy.enabled,
  presentation: CCPagePresentation(
    routeType: CCPageRouteType.material,
    transition: CCPageTransitionType.slideFromRight,
  ),
  description: '验证类型安全参数、Query 集合、多 Path、完整 URL、Scheme 与返回值。',
)
final class DemoDetailPage extends StatefulWidget {
  const DemoDetailPage({
    required this.id,
    @CCQueryParam() this.title = '类型安全详情',
    @CCQueryParam() this.tags = const <String>[],
    super.key,
  });

  final int id;
  final String title;
  final List<String> tags;

  @override
  State<DemoDetailPage> createState() => _DemoDetailPageState();
}

final class _DemoDetailPageState extends State<DemoDetailPage>
    with CCPageLifecycleMixin<DemoDetailPage> {
  @override
  void initState() {
    super.initState();
    demoNavigationLabStore.record('Detail initState · id=${widget.id}');
  }

  @override
  void onPageShow() => demoNavigationLabStore.record('Detail onPageShow');

  @override
  void onPageHide() => demoNavigationLabStore.record('Detail onPageHide');

  @override
  void onForeground() => demoNavigationLabStore.record('Detail onForeground');

  @override
  void onBackground() => demoNavigationLabStore.record('Detail onBackground');

  @override
  void dispose() {
    demoNavigationLabStore.record('Detail dispose');
    super.dispose();
  }

  void _complete() {
    if (CCRouter.navigator.canPop()) {
      CCRouter.navigator.pop(result: 'detail:${widget.id}:confirmed');
      return;
    }
    unawaited(CCRouter.navigator.open(Uri.parse('/')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'ID ${widget.id}',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 12),
            const Text('参数由生成 Codec 解码，页面不读取 GoRouterState。'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.tags
                  .map((tag) => Chip(label: Text(tag)))
                  .toList(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _complete,
              icon: const Icon(Icons.check),
              label: const Text('确认并返回类型安全结果'),
            ),
          ],
        ),
      ),
    ),
  );
}

CCRouteIntent<String> demoDetailIntent({
  required int id,
  String title = '类型安全详情',
  List<String> tags = const <String>[],
}) => _DemoDetailPageRoute.intent(id: id, title: title, tags: tags);
