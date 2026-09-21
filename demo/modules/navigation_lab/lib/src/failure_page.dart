import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'navigation_lab_component.dart';
import 'ccrouter_generated/demo_navigation_lab_component.route_api.g.dart';

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.failure',
  pattern: CCPathPattern('/lab/failure'),
  presentation: CCPagePresentation(transition: CCPageTransitionType.fade),
  description: '展示标准导航失败经 Host Failure Policy 恢复后的安全页面。',
)
final class DemoFailurePage extends StatelessWidget {
  const DemoFailurePage({
    @CCQueryParam() required this.stage,
    @CCQueryParam() required this.reason,
    @CCQueryParam() required this.errorType,
    @CCQueryParam() this.initialRouteId,
    @CCQueryParam() this.routeId,
    super.key,
  });

  final String stage;
  final String reason;
  final String errorType;
  final String? initialRouteId;
  final String? routeId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导航兜底')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route_outlined, size: 56),
              const SizedBox(height: 16),
              Text('原目标不可用', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text('stage: $stage'),
              Text('reason: $reason'),
              Text('error: $errorType'),
              Text('initial route: ${initialRouteId ?? '-'}'),
              Text('failed route: ${routeId ?? '-'}'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  if (CCRouter.navigator.canPop()) {
                    CCRouter.navigator.pop();
                  } else {
                    unawaited(CCRouter.navigator.open(Uri.parse('/')));
                  }
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

CCRouteIntent<void> demoFailureIntent({
  required String stage,
  required String reason,
  required String errorType,
  String? initialRouteId,
  String? routeId,
}) => DemoNavigationLabRoutes.failure(
  stage: stage,
  reason: reason,
  errorType: errorType,
  initialRouteId: initialRouteId,
  routeId: routeId,
);
