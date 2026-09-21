import 'dart:async';

import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lab_configuration.dart';
import 'navigation_lab_component.dart';
import 'ccrouter_generated/demo_navigation_lab_component.route_api.g.dart';

const _proceedInterceptorId = 'demo_navigation_lab.proceed';
const _cancelInterceptorId = 'demo_navigation_lab.cancel';
const _redirectInterceptorId = 'demo_navigation_lab.redirect';
const _deferInterceptorId = 'demo_navigation_lab.defer';
const _timeoutInterceptorId = 'demo_navigation_lab.timeout';
const _dirtyPopGuardId = 'demo_navigation_lab.dirty';

void registerDemoNavigationLabPolicies(CCRegistry registry) {
  registry.registerRouteInterceptor(
    _proceedInterceptorId,
    const _DemoProceedInterceptor(),
  );
  registry.registerRouteInterceptor(
    _cancelInterceptorId,
    const _DemoCancelInterceptor(),
  );
  registry.registerRouteInterceptor(
    _redirectInterceptorId,
    const _DemoRedirectInterceptor(),
  );
  registry.registerRouteInterceptor(
    _deferInterceptorId,
    const _DemoDeferInterceptor(),
  );
  registry.registerRouteInterceptor(
    _timeoutInterceptorId,
    const _DemoTimeoutInterceptor(),
    timeout: const Duration(milliseconds: 180),
  );
  registry.registerRoutePopGuard(_dirtyPopGuardId, const _DemoDirtyPopGuard());
}

final class _DemoProceedInterceptor implements CCNavigationInterceptor {
  const _DemoProceedInterceptor();

  @override
  CCNavigationInterception intercept(CCNavigationInterceptorContext context) {
    demoNavigationLabStore.record('Route interceptor · proceed');
    return const CCNavigationProceed();
  }
}

final class _DemoCancelInterceptor implements CCNavigationInterceptor {
  const _DemoCancelInterceptor();

  @override
  CCNavigationInterception intercept(CCNavigationInterceptorContext context) {
    demoNavigationLabStore.record('Route interceptor · cancel');
    return const CCNavigationCancel(code: 'demo_cancelled');
  }
}

final class _DemoRedirectInterceptor implements CCNavigationInterceptor {
  const _DemoRedirectInterceptor();

  @override
  CCNavigationInterception intercept(CCNavigationInterceptorContext context) {
    demoNavigationLabStore.record('Route interceptor · redirect');
    return CCNavigationRedirect.toIntent(
      DemoNavigationLabRoutes.redirectTarget() as CCRouteIntent<Object?>,
    );
  }
}

final class _DemoDeferInterceptor implements CCNavigationInterceptor {
  const _DemoDeferInterceptor();

  @override
  CCNavigationInterception intercept(CCNavigationInterceptorContext context) {
    if (demoNavigationLabStore.allowDeferredOnce) {
      demoNavigationLabStore.allowDeferredOnce = false;
      demoNavigationLabStore.record('Route interceptor · resumed');
      return const CCNavigationProceed();
    }
    demoNavigationLabStore.record('Route interceptor · defer');
    return const CCNavigationDefer(
      code: 'demo_waiting_for_consent',
      timeout: Duration(minutes: 2),
    );
  }
}

final class _DemoTimeoutInterceptor implements CCNavigationInterceptor {
  const _DemoTimeoutInterceptor();

  @override
  Future<CCNavigationInterception> intercept(
    CCNavigationInterceptorContext context,
  ) async {
    demoNavigationLabStore.record('Route interceptor · timeout started');
    await Future<void>.delayed(const Duration(seconds: 2));
    return const CCNavigationProceed();
  }
}

final class _DemoDirtyPopGuard implements CCPopGuard {
  const _DemoDirtyPopGuard();

  @override
  CCPopGuardDecision evaluate(CCPopGuardContext context) {
    demoNavigationLabStore.record(
      'PopGuard · ${context.trigger.name} · '
      '${demoNavigationLabStore.dirtyForm ? 'deny' : 'allow'}',
    );
    return demoNavigationLabStore.dirtyForm
        ? const CCPopDeny(code: 'demo_unsaved_form')
        : const CCPopAllow();
  }
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.proceed',
  pattern: CCPathPattern('/lab/policy/proceed'),
  interceptors: [_proceedInterceptorId],
  description: '路由级拦截器放行示例。',
)
final class DemoProceedPage extends StatelessWidget {
  const DemoProceedPage({super.key});

  @override
  Widget build(BuildContext context) => const _PolicyResultPage(
    title: '拦截器已放行',
    icon: Icons.verified_user_outlined,
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.cancel',
  pattern: CCPathPattern('/lab/policy/cancel'),
  interceptors: [_cancelInterceptorId],
  description: '路由级拦截器取消示例；页面正常情况下不会创建。',
)
final class DemoCancelledPage extends StatelessWidget {
  const DemoCancelledPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PolicyResultPage(title: '不应到达的页面', icon: Icons.error_outline);
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.redirect.source',
  pattern: CCPathPattern('/lab/policy/redirect-source'),
  interceptors: [_redirectInterceptorId],
  description: '路由级拦截器重定向源页面；页面正常情况下不会创建。',
)
final class DemoRedirectSourcePage extends StatelessWidget {
  const DemoRedirectSourcePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PolicyResultPage(title: '不应到达的重定向源', icon: Icons.error_outline);
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.redirect.target',
  pattern: CCPathPattern('/lab/policy/redirect-target'),
  description: '拦截器重定向后的目标页面。',
)
final class DemoRedirectTargetPage extends StatelessWidget {
  const DemoRedirectTargetPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PolicyResultPage(title: '已重定向到目标页', icon: Icons.alt_route);
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.defer',
  pattern: CCPathPattern('/lab/policy/defer'),
  interceptors: [_deferInterceptorId],
  description: '等待外部同意后恢复的 Deferred Navigation 示例。',
)
final class DemoDeferredPage extends StatelessWidget {
  const DemoDeferredPage({super.key});

  @override
  Widget build(BuildContext context) => const _PolicyResultPage(
    title: 'Deferred Navigation 已恢复',
    icon: Icons.play_circle_outline,
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.timeout',
  pattern: CCPathPattern('/lab/policy/timeout'),
  interceptors: [_timeoutInterceptorId],
  description: '触发标准 Interceptor Timeout Error 的示例。',
)
final class DemoTimeoutPage extends StatelessWidget {
  const DemoTimeoutPage({super.key});

  @override
  Widget build(BuildContext context) => const _PolicyResultPage(
    title: '不应到达的超时页面',
    icon: Icons.timer_off_outlined,
  );
}

@CCRoute<void>(
  component: demoNavigationLabComponent,
  id: 'demo_navigation_lab.guarded',
  pattern: CCPathPattern('/lab/policy/guarded'),
  popGuards: [_dirtyPopGuardId],
  description: '未保存状态下拒绝 CCRouter Pop 的路由。',
)
final class DemoGuardedPage extends StatefulWidget {
  const DemoGuardedPage({super.key});

  @override
  State<DemoGuardedPage> createState() => _DemoGuardedPageState();
}

final class _DemoGuardedPageState extends State<DemoGuardedPage> {
  Future<void> _tryPop() async {
    final outcome = await CCRouter.navigator.maybePopOutcome(
      trigger: CCPopTrigger.business,
    );
    if (!mounted || outcome.handled) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('PopGuard 已拒绝返回，请先保存表单')));
  }

  /// Simulates the Router-level back dispatch used by platform hosts. The
  /// route itself must not call `Navigator.pop` or bypass the Router boundary.
  Future<void> _trySystemBack() async {
    await Router.of(context).routerDelegate.popRoute();
    if (!mounted || !ModalRoute.of(context)!.isCurrent) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('系统返回已交给 PopGuard')));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: demoNavigationLabStore,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '通过 CCRouter 返回',
          onPressed: _tryPop,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('PopGuard'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  demoNavigationLabStore.dirtyForm
                      ? Icons.edit_note
                      : Icons.task_alt,
                  size: 56,
                ),
                const SizedBox(height: 16),
                Text(
                  demoNavigationLabStore.dirtyForm ? '表单尚未保存' : '表单已保存',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: demoNavigationLabStore.dirtyForm,
                  onChanged: demoNavigationLabStore.setDirtyForm,
                  title: const Text('存在未保存修改'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _tryPop,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('尝试返回'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _trySystemBack,
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('模拟系统返回'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _PolicyResultPage extends StatelessWidget {
  const _PolicyResultPage({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => CCRouter.navigator.pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('返回实验台'),
          ),
        ],
      ),
    ),
  );
}
