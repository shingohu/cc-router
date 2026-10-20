import 'package:ccrouter/ccrouter.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:flutter/material.dart';

import 'ccrouter_generated/demo_navigation_lab_component.ui.api.g.dart';

@CCRoute<void>(
  id: 'demo_navigation_lab.ui_fragments',
  pattern: CCPathPattern('/ui-fragments'),
  description: '跨组件 UI Fragment、保活、输入更新与资源释放验证。',
)
final class UIFragmentLabPage extends StatefulWidget {
  const UIFragmentLabPage({super.key});

  @override
  State<UIFragmentLabPage> createState() => _UIFragmentLabPageState();
}

final class _UIFragmentLabPageState extends State<UIFragmentLabPage> {
  int _tab = 0;
  int _orderId = 1;
  int _session = 0;
  bool _error = false;
  String _status = '等待选择';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('类型化 UI Fragment')),
    body: Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => setState(() => _tab = 1 - _tab),
              child: const Text('切换 Tab'),
            ),
            TextButton(
              onPressed: () => setState(() => _orderId++),
              child: const Text('更新 Props'),
            ),
            TextButton(
              onPressed: () => setState(() => _session++),
              child: const Text('切换模拟账号'),
            ),
            TextButton(
              onPressed: () => setState(() => _error = !_error),
              child: const Text('切换加载错误'),
            ),
          ],
        ),
        Text(_status),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              ListView(
                key: ValueKey('orders-$_session'),
                children: [
                  for (final slot in [0, 1])
                    DemoNavigationLabComponentFragments.orderSummary(
                      key: ValueKey(slot),
                      props: OrderSummaryProps(orderId: _orderId + slot),
                      active: _tab == 0,
                      onAction: (_) => setState(
                        () => _status = 'A 收到订单 ${_orderId + slot} 的选择',
                      ),
                    ),
                ],
              ),
              ListView(
                key: ValueKey('recommendations-$_session'),
                children: [
                  DemoNavigationLabComponentFragments.orderRecommendations(
                    key: const ValueKey('recommendations'),
                    props: OrderRecommendationsProps(
                      category: _error ? 'error' : '精选',
                    ),
                    active: _tab == 1,
                    onAction: (action) => setState(
                      () => _status = 'A 收到推荐 ${action.selectedId} 的选择',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
