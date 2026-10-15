import 'dart:async';

import 'package:ccrouter_ui/ccrouter_ui.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:flutter/material.dart';

@CCUIFragmentRenderer(OrderSummaryFragmentContract)
Widget renderOrderSummary(
  CCUIFragmentRenderInput<OrderSummaryProps, OrderSummaryAction> input,
) => _OwnedCard(
  label: '订单摘要',
  query: '${input.props.orderId}',
  active: input.active,
  onAction: () => input.onAction(OrderSummaryAction.openDetails),
);

@CCUIFragmentRenderer(OrderRecommendationsFragmentContract)
Widget renderOrderRecommendations(
  CCUIFragmentRenderInput<OrderRecommendationsProps, OrderRecommendationsAction>
  input,
) => _OwnedCard(
  label: '推荐列表',
  query: input.props.category,
  active: input.active,
  onAction: () =>
      input.onAction(OrderRecommendationsAction.selectRecommendation),
);

/// B owns loading, retry and controller cleanup; A owns placement and decisions.
final class _OwnedCard extends StatefulWidget {
  const _OwnedCard({
    required this.label,
    required this.query,
    required this.active,
    required this.onAction,
  });
  final String label;
  final String query;
  final bool active;
  final VoidCallback onAction;

  @override
  State<_OwnedCard> createState() => _OwnedCardState();
}

final class _OwnedCardState extends State<_OwnedCard> {
  final _note = TextEditingController();
  Timer? _request;
  int _revision = 0;
  String? _result;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_OwnedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _result = null;
      _failed = false;
      _load();
    } else if (oldWidget.active != widget.active) {
      if (!widget.active) {
        _request?.cancel();
        _revision++;
      } else if (_result == null && !_failed) {
        _load();
      }
    }
  }

  void _load() {
    _request?.cancel();
    final revision = ++_revision;
    if (!widget.active) return;
    final query = widget.query;
    // Local cancellable fake backend; no production data or platform SDK.
    _request = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || revision != _revision) return;
      setState(() {
        _failed = query == 'error';
        _result = _failed ? null : '${widget.label} · $query';
      });
    });
  }

  @override
  void dispose() {
    _revision++;
    _request?.cancel();
    _request = null;
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
          if (_failed) ...[
            const Text('暂时无法加载'),
            TextButton(
              onPressed: !widget.active
                  ? null
                  : () {
                      setState(() {
                        _failed = false;
                      });
                      _load();
                    },
              child: const Text('重试'),
            ),
          ] else
            Text(_result ?? '加载中…'),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: '实例备注（切换 Tab 保留）'),
          ),
          TextButton(
            onPressed: widget.active && _result != null
                ? widget.onAction
                : null,
            child: const Text('选择'),
          ),
        ],
      ),
    ),
  );
}
