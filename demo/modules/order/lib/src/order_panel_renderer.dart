import 'package:ccrouter_ui/ccrouter_ui.dart';
import 'package:demo_order_contracts/demo_order_contracts.dart';
import 'package:flutter/material.dart';

/// A stateless fixture: the consumer decides navigation and asynchronous work.
@CCUIFragmentRenderer(OrderPanelFragmentContract)
Widget renderOrderPanel(
  CCUIFragmentRenderInput<OrderPanelProps, OrderPanelAction> input,
) => Wrap(
  children: [
    TextButton(
      onPressed: input.active
          ? () => input.onAction(const OrderPanelSettingsRequested())
          : null,
      child: const Text('打开设置'),
    ),
    for (final (label, target) in const <(String, OrderPanelTarget)>[
      ('选择用户', OrderPanelUser('demo-user')),
      ('选择曲谱', OrderPanelScore('demo-score')),
      ('选择作品', OrderPanelVideo('demo-video')),
      ('选择艺术家', OrderPanelArtist('demo-artist')),
    ])
      TextButton(
        onPressed: input.active
            ? () => input.onAction(OrderPanelTargetSelected(target))
            : null,
        child: Text(label),
      ),
  ],
);
