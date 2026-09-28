import 'package:ccrouter/ccrouter.dart';
import 'package:flutter/material.dart';

import 'snapshot.dart';
import 'snapshot_provider.dart';

/// Embeddable read-only CCRouter diagnostics panel.
///
/// The panel is intended for a development-only route or a debug drawer. It
/// renders Component Graph, Route/Backend Entries, traces, failures, and the
/// InitTask dependency graph. It has no navigation, retry, dispose, activate,
/// or other mutating controls. A production build should omit the package or
/// keep the panel behind the application's own debug gate.
final class CCRouterDevToolsPanel extends StatefulWidget {
  /// Creates a panel backed by the active Runtime by default.
  const CCRouterDevToolsPanel({
    super.key,
    this.provider,
    this.title = 'CCRouter DevTools',
  });

  /// Optional immutable diagnostics source, primarily useful for tests.
  final CCDevToolsSnapshotProvider? provider;

  /// Heading shown above the read-only tabs.
  final String title;

  @override
  State<CCRouterDevToolsPanel> createState() => _CCRouterDevToolsPanelState();
}

/// Stateful shell that owns listener removers for the diagnostics panel.
final class _CCRouterDevToolsPanelState extends State<CCRouterDevToolsPanel> {
  late CCDevToolsSnapshotProvider _provider;
  late CCDevToolsSnapshot _snapshot;
  VoidCallback? _removeListener;

  @override
  void initState() {
    super.initState();
    _provider = widget.provider ?? const CCRouterDevToolsSnapshotProvider();
    _snapshot = _provider.snapshot();
    _removeListener = _provider.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant CCRouterDevToolsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider == widget.provider) return;
    _removeListener?.call();
    _provider = widget.provider ?? const CCRouterDevToolsSnapshotProvider();
    _snapshot = _provider.snapshot();
    _removeListener = _provider.addListener(_refresh);
  }

  @override
  void dispose() {
    _removeListener?.call();
    super.dispose();
  }

  /// Refreshes the immutable view after an observational source event.
  void _refresh() {
    if (!mounted) return;
    setState(() => _snapshot = _provider.snapshot());
  }

  @override
  Widget build(BuildContext context) => Material(
    child: DefaultTabController(
      length: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            title: Text(widget.title),
            subtitle: Text(
              _snapshot.runtimeState == CCDevToolsRuntimeState.initialized
                  ? 'Runtime initialized · captured ${_snapshot.capturedAt}'
                  : 'Runtime is not initialized',
            ),
            trailing: IconButton(
              tooltip: 'Refresh diagnostics',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Components'),
              Tab(text: 'Entries'),
              Tab(text: 'Timeline'),
              Tab(text: 'Failures'),
              Tab(text: 'InitTask DAG'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewView(snapshot: _snapshot),
                _ComponentGraphView(snapshot: _snapshot),
                _EntriesView(snapshot: _snapshot),
                _TimelineView(snapshot: _snapshot),
                _FailuresView(snapshot: _snapshot),
                _InitTaskView(snapshot: _snapshot),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shared read-only section heading.
final class _SectionTitle extends StatelessWidget {
  /// Creates a heading with a count badge.
  const _SectionTitle(this.title, this.count);

  /// Section label.
  final String title;

  /// Number of items represented by the section.
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Chip(label: Text('$count')),
      ],
    ),
  );
}

/// Displays one neutral empty state without implying a Runtime error.
final class _EmptyState extends StatelessWidget {
  /// Creates an empty state with [message].
  const _EmptyState(this.message);

  /// Explanation for an empty or unavailable diagnostic section.
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

/// Displays bounded high-level counters and runtime state.
final class _OverviewView extends StatelessWidget {
  /// Creates an overview for [snapshot].
  const _OverviewView({required this.snapshot});

  /// Immutable diagnostics data.
  final CCDevToolsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final cards = <({String label, int value})>[
      (label: 'Components', value: snapshot.components.length),
      (label: 'Managed Routes', value: snapshot.routeEntries.length),
      (label: 'Backend Entries', value: snapshot.backendEntries.length),
      (label: 'Pending', value: snapshot.pendingNavigations.length),
      (label: 'Failures', value: snapshot.navigationFailures.length),
      (label: 'InitTasks', value: snapshot.initializationTasks.length),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (snapshot.runtimeState == CCDevToolsRuntimeState.uninitialized)
          const _EmptyState('没有活动 Runtime。面板保持只读，不会自动初始化框架。')
        else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: 150,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card.label),
                            const SizedBox(height: 8),
                            Text(
                              '${card.value}',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        _SectionTitle(
          'Restoration demand',
          snapshot.restorationOpportunities.length,
        ),
        if (snapshot.restorationOpportunities.isEmpty)
          const _EmptyState('没有记录到状态恢复机会。')
        else
          for (final event in snapshot.restorationOpportunities)
            ListTile(
              dense: true,
              title: Text(event.reason.name),
              subtitle: Text('outcome=${event.outcome.name}'),
              trailing: Text(_time(event.recordedAt)),
            ),
      ],
    );
  }
}

/// Displays component ownership and dependency edges as a compact graph.
final class _ComponentGraphView extends StatelessWidget {
  /// Creates the component graph for [snapshot].
  const _ComponentGraphView({required this.snapshot});

  /// Immutable diagnostics data.
  final CCDevToolsSnapshot snapshot;

  @override
  Widget build(BuildContext context) => snapshot.components.isEmpty
      ? const _EmptyState('没有已注册组件。')
      : ListView(
          children: [
            _SectionTitle('Component Graph', snapshot.components.length),
            for (final component in snapshot.components)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: ListTile(
                  title: Text(component.id),
                  subtitle: Text(
                    component.dependencies.isEmpty
                        ? 'version ${component.version} · no required dependencies'
                        : 'version ${component.version} · depends on '
                              '${component.dependencies.join(', ')}',
                  ),
                  trailing: component.optionalDependencies.isEmpty
                      ? null
                      : Tooltip(
                          message: component.optionalDependencies.join(', '),
                          child: const Icon(Icons.link, size: 18),
                        ),
                ),
              ),
          ],
        );
}

/// Displays managed Route Entries beside the hybrid backend ledger.
final class _EntriesView extends StatelessWidget {
  /// Creates the entry view for [snapshot].
  const _EntriesView({required this.snapshot});

  /// Immutable diagnostics data.
  final CCDevToolsSnapshot snapshot;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _SectionTitle('Managed Route Entries', snapshot.routeEntries.length),
      if (snapshot.routeEntries.isEmpty)
        const _EmptyState('当前没有 CCRouter 管理的 Route Entry。')
      else
        for (final entry in snapshot.routeEntries)
          ListTile(
            dense: true,
            leading: Icon(_routeStateIcon(entry.lifecycleState)),
            title: Text(entry.routeId),
            subtitle: Text(
              '${entry.lifecycleState.name} · ${entry.hostId}/'
              '${entry.placement.navigatorOutlet} · owner '
              '${entry.ownerComponentId}',
            ),
            trailing: Text(entry.routeEntryId),
          ),
      _SectionTitle('Backend Entries', snapshot.backendEntries.length),
      if (snapshot.backendEntries.isEmpty)
        const _EmptyState('没有 Adapter 观测到的 Backend Entry。')
      else
        for (final entry in snapshot.backendEntries)
          ListTile(
            dense: true,
            leading: Icon(_backendOwnerIcon(entry.owner)),
            title: Text(entry.routeId ?? entry.backendEntryId),
            subtitle: Text(
              '${entry.owner.name} · ${entry.lifecycleState.name} · '
              '${entry.hostId ?? 'unknown'}/${entry.navigatorOutlet} · '
              '${entry.visibilityState.name}',
            ),
            trailing: Text(entry.backendEntryId),
          ),
    ],
  );
}

/// Displays trace, navigation, backend, and visibility timelines.
final class _TimelineView extends StatelessWidget {
  /// Creates the timeline for [snapshot].
  const _TimelineView({required this.snapshot});

  /// Immutable diagnostics data.
  final CCDevToolsSnapshot snapshot;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _SectionTitle('Invocation traces', snapshot.traces.length),
      if (snapshot.traces.isEmpty)
        const _EmptyState('没有保留 Trace。')
      else
        for (final trace in snapshot.traces)
          ListTile(
            dense: true,
            title: Text('${trace.operation} · ${trace.target}'),
            subtitle: Text(
              '${trace.status} · ${trace.context.traceId} · '
              '${trace.context.scopeId ?? 'no scope'}',
            ),
            trailing: Text(_duration(trace.duration)),
          ),
      _SectionTitle('Navigation events', snapshot.navigationEvents.length),
      for (final event in snapshot.navigationEvents.reversed)
        ListTile(
          dense: true,
          title: Text('${event.phase.name} · ${event.routeId}'),
          subtitle: Text(
            '${event.operation.name} · ${event.placement.hostId}/'
            '${event.placement.navigatorOutlet}',
          ),
          trailing: Text(_time(event.timestamp)),
        ),
      _SectionTitle('Backend events', snapshot.backendEvents.length),
      for (final event in snapshot.backendEvents.reversed)
        ListTile(
          dense: true,
          title: Text('${event.kind.name} · ${event.routeId ?? 'foreign'}'),
          subtitle: Text(
            '${event.owner?.name ?? 'unknown'} · '
            '${event.hostId ?? 'unknown'}/${event.navigatorOutlet ?? 'unknown'}',
          ),
          trailing: Text(_time(event.timestamp)),
        ),
    ],
  );
}

/// Displays failures, capability fallbacks, and pending policy decisions.
final class _FailuresView extends StatelessWidget {
  /// Creates the failure view for [snapshot].
  const _FailuresView({required this.snapshot});

  /// Immutable diagnostics data.
  final CCDevToolsSnapshot snapshot;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _SectionTitle('Navigation failures', snapshot.navigationFailures.length),
      if (snapshot.navigationFailures.isEmpty)
        const _EmptyState('没有导航失败记录。')
      else
        for (final event in snapshot.navigationFailures.reversed)
          ListTile(
            dense: true,
            leading: Icon(event.recovered ? Icons.replay : Icons.error_outline),
            title: Text(
              '${event.context.routeId ?? 'unknown'} · '
              '${event.context.stage.name}',
            ),
            subtitle: Text(
              '${event.context.reason.name} · '
              '${event.context.errorType} · '
              'recovered=${event.recovered}',
            ),
            trailing: Text(_time(event.timestamp)),
          ),
      _SectionTitle(
        'Capability fallbacks',
        snapshot.capabilityFallbacks.length,
      ),
      if (snapshot.capabilityFallbacks.isEmpty)
        const _EmptyState('没有能力降级记录。')
      else
        for (final event in snapshot.capabilityFallbacks.reversed)
          ListTile(
            dense: true,
            title: Text('${event.capability.name} · ${event.routeId}'),
            subtitle: Text('${event.operation.name} → ${event.behavior.name}'),
            trailing: Text(_time(event.timestamp)),
          ),
      _SectionTitle('Pending navigation', snapshot.pendingNavigations.length),
      if (snapshot.pendingNavigations.isEmpty)
        const _EmptyState('没有等待策略决策的导航。')
      else
        for (final pending in snapshot.pendingNavigations)
          ListTile(
            dense: true,
            title: Text(pending.routeId),
            subtitle: Text(
              '${pending.operation.name} · ${pending.navigationId}',
            ),
            trailing: Text(_time(pending.createdAt)),
          ),
    ],
  );
}

/// Displays InitTask states and their typed dependency edges.
final class _InitTaskView extends StatelessWidget {
  /// Creates an InitTask DAG view for [snapshot].
  const _InitTaskView({required this.snapshot});

  /// Immutable diagnostics data.
  final CCDevToolsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.initializationTasks.isEmpty) {
      return const _EmptyState('没有注册 InitTask。');
    }
    final tasks = {
      for (final task in snapshot.initializationTasks) task.id: task,
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SectionTitle('InitTask DAG', snapshot.initializationTasks.length),
        for (final task in snapshot.initializationTasks)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: ListTile(
              leading: Icon(_taskStateIcon(task.state)),
              title: Text(task.id),
              subtitle: Text(
                '${task.ownerComponentId} · gate=${task.gateId} · '
                '${task.state.name}${task.errorType == null ? '' : ' · ${task.errorType}'}',
              ),
              trailing: task.dependsOn.isEmpty
                  ? null
                  : Tooltip(
                      message: task.dependsOn
                          .map(
                            (id) =>
                                tasks.containsKey(id) ? id : '$id (missing)',
                          )
                          .join('\n'),
                      child: const Icon(Icons.account_tree, size: 18),
                    ),
            ),
          ),
      ],
    );
  }
}

/// Formats a bounded duration without exposing arbitrary payloads.
String _duration(Duration duration) => '${duration.inMilliseconds} ms';

/// Formats a diagnostic timestamp for a compact list row.
String _time(DateTime timestamp) => timestamp.toLocal().toIso8601String();

/// Selects a neutral icon for one managed Route Entry state.
IconData _routeStateIcon(CCRouteEntryLifecycleState state) => switch (state) {
  CCRouteEntryLifecycleState.visible => Icons.visibility,
  CCRouteEntryLifecycleState.hidden => Icons.visibility_off,
  CCRouteEntryLifecycleState.popping => Icons.output,
  CCRouteEntryLifecycleState.removed => Icons.remove_circle_outline,
  CCRouteEntryLifecycleState.disposed => Icons.delete_outline,
  _ => Icons.circle_outlined,
};

/// Selects an icon for backend ownership without implying control authority.
IconData _backendOwnerIcon(CCBackendEntryOwner owner) => switch (owner) {
  CCBackendEntryOwner.managed => Icons.alt_route,
  CCBackendEntryOwner.foreign => Icons.open_in_new,
  CCBackendEntryOwner.opaque => Icons.help_outline,
};

/// Selects a neutral icon for one InitTask state.
IconData _taskStateIcon(CCInitializationTaskState state) => switch (state) {
  CCInitializationTaskState.succeeded => Icons.check_circle_outline,
  CCInitializationTaskState.failed => Icons.error_outline,
  CCInitializationTaskState.skipped => Icons.skip_next,
  CCInitializationTaskState.running => Icons.timelapse,
  CCInitializationTaskState.pending => Icons.schedule,
};
