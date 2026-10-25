import 'package:ccrouter/ccrouter.dart';
import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';
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
    this.onOpenSource,
  });

  /// Optional immutable diagnostics source, primarily useful for tests.
  final CCDevToolsSnapshotProvider? provider;

  /// Heading shown above the read-only tabs.
  final String title;

  /// Optional Host callback for opening a source location in an IDE.
  ///
  /// DevTools itself cannot assume an editor or filesystem mapping. When this
  /// callback is omitted, the panel still renders a copyable `package:` URI.
  final ValueChanged<CCDevToolsSourceLocation>? onOpenSource;

  @override
  State<CCRouterDevToolsPanel> createState() => _CCRouterDevToolsPanelState();
}

/// Stateful shell that owns listener removers for the diagnostics panel.
final class _CCRouterDevToolsPanelState extends State<CCRouterDevToolsPanel> {
  late CCDevToolsSnapshotProvider _provider;
  late CCRouterDevToolsSnapshot _snapshot;
  VoidCallback? _removeListener;

  /// Hidden retained routes suspend observation until their ticker is enabled.
  bool _observing = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.provider ?? const CCRouterDevToolsSnapshotProvider();
    _snapshot = _provider.snapshot();
  }

  @override
  /// Suspends the subscription for retained hidden pages and refreshes on return.
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_observing == enabled) return;
    _observing = enabled;
    _removeListener?.call();
    _removeListener = null;
    if (enabled) {
      _snapshot = _provider.snapshot();
      _removeListener = _provider.addListener(_refresh);
    }
  }

  @override
  void didUpdateWidget(covariant CCRouterDevToolsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.provider, widget.provider)) return;
    _removeListener?.call();
    _provider = widget.provider ?? const CCRouterDevToolsSnapshotProvider();
    _snapshot = _provider.snapshot();
    _removeListener = _observing ? _provider.addListener(_refresh) : null;
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
      length: 8,
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
              Tab(text: 'Catalog'),
              Tab(text: 'Components'),
              Tab(text: 'Entries'),
              Tab(text: 'Timeline'),
              Tab(text: 'Failures'),
              Tab(text: 'InitTask DAG'),
              Tab(text: 'Call Graph'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewView(snapshot: _snapshot),
                _CatalogView(
                  snapshot: _snapshot,
                  onOpenSource: widget.onOpenSource,
                ),
                _ComponentGraphView(snapshot: _snapshot),
                _EntriesView(snapshot: _snapshot),
                _TimelineView(snapshot: _snapshot),
                _FailuresView(snapshot: _snapshot),
                _InitTaskView(snapshot: _snapshot),
                _CallGraphView(snapshot: _snapshot),
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
        Flexible(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
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
  final CCRouterDevToolsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final cards = <({String label, int value})>[
      (label: 'Components', value: snapshot.components.length),
      (label: 'Managed Routes', value: snapshot.routeEntries.length),
      (label: 'Backend Entries', value: snapshot.backendEntries.length),
      (label: 'Pending', value: snapshot.pendingNavigations.length),
      (label: 'Failures', value: snapshot.navigationFailures.length),
      (label: 'InitTasks', value: snapshot.initTasks.length),
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
        if (snapshot.runtimeState == CCDevToolsRuntimeState.initialized)
          _DiagnosticHealthView(snapshot.diagnosticHealth),
      ],
    );
  }
}

/// Shows delivery and bounded-history completeness without business payloads.
final class _DiagnosticHealthView extends StatelessWidget {
  /// Creates the optional health section for one captured Runtime.
  const _DiagnosticHealthView(this.health);

  /// Null means unsupported by the producer, not zero loss.
  final CCDiagnosticSnapshot? health;

  @override
  Widget build(BuildContext context) {
    final health = this.health;
    if (health == null) {
      return const ListTile(
        title: Text('Diagnostic health unavailable from producer'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle('Diagnostic health', health.histories.length),
        ListTile(
          title: Text(
            health.sinkConfigured
                ? 'External Sink configured'
                : 'External Sink not configured',
          ),
          subtitle: Text(
            'queued=${health.delivery.queuedEventCount}/${health.delivery.queueCapacity} · '
            'inFlight=${health.delivery.inFlightWriteCount} · peak=${health.delivery.peakQueueDepth}\n'
            'delivered=${health.delivery.deliveredEventCount} · failed=${health.delivery.failedEventCount} · '
            'dropped=${health.delivery.droppedEventCount} · closed=${health.delivery.isClosed}',
          ),
        ),
        if (health.runtimeHealth case final runtimeHealth?)
          ListTile(
            title: const Text('Runtime navigation health'),
            subtitle: Text(
              'routes=${runtimeHealth.activeRouteEntryCount} active / '
              '${runtimeHealth.exitingRouteEntryCount} exiting · '
              'pending=${runtimeHealth.pendingNavigationCount} · '
              'inFlight=${runtimeHealth.inFlightNavigationCount}\n'
              'backend=${runtimeHealth.activeBackendEntryCount} active / '
              '${runtimeHealth.backendEntryCount} retained · '
              'trackedHosts=${runtimeHealth.trackedNavigationHostCount} · '
              'desync=${runtimeHealth.desynchronizedBackendHostCount}\n'
              'observerQueue=${runtimeHealth.observerQueueDepth}/'
              '${runtimeHealth.observerQueueCapacity} · '
              'routeTransitions=${runtimeHealth.routeEntryTransitionCount} · '
              'unattributedBackend=${runtimeHealth.unattributedBackendEventCount}',
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '历史未保留数与外部 Sink 过滤、采样无关；队列丢弃另计。空历史不代表从未失败。delivered 仅表示 Sink 调用完成。',
          ),
        ),
        for (final history in health.histories)
          ListTile(
            dense: true,
            title: Text(
              '${history.name}${history.capacity == 0 ? ' · retention disabled' : ''}',
            ),
            subtitle: Text(
              'retained=${history.retainedCount}/${history.capacity} · omitted=${history.omittedCount}',
            ),
          ),
      ],
    );
  }
}

/// Displays a searchable static Catalog and its live Runtime linkage.
final class _CatalogView extends StatefulWidget {
  /// Creates a Catalog view for [snapshot].
  const _CatalogView({required this.snapshot, this.onOpenSource});

  /// Immutable diagnostics data.
  final CCRouterDevToolsSnapshot snapshot;

  /// Optional source-opening callback owned by the Host.
  final ValueChanged<CCDevToolsSourceLocation>? onOpenSource;

  @override
  State<_CatalogView> createState() => _CatalogViewState();
}

final class _CatalogViewState extends State<_CatalogView> {
  final _query = TextEditingController();
  String? _selectedId;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.snapshot.catalog;
    if (catalog == null) {
      return const _EmptyState('没有静态 Catalog。请在 Host 注册生成的源码索引后刷新。');
    }
    final query = _query.text.trim().toLowerCase();
    final records = catalog.records
        .where((record) {
          if (query.isEmpty) return true;
          return '${record.kind} ${record.id} ${record.ownerComponentId} '
                  '${record.packageName}'
              .toLowerCase()
              .contains(query);
        })
        .toList(growable: false);
    final liveIds = {
      for (final entry in widget.snapshot.routeEntries) entry.routeId,
      for (final entry in widget.snapshot.traces) entry.target,
    };
    final selected = records.where((record) => record.id == _selectedId);
    final record = selected.isEmpty ? null : selected.first;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Filter capability, component, or package',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        _SectionTitle('Static Catalog', records.length),
        if (record != null)
          _CatalogRecordDetail(
            record: record,
            live: liveIds.contains(record.id),
            onOpenSource: widget.onOpenSource,
          ),
        Expanded(
          child: records.isEmpty
              ? const _EmptyState('没有匹配的静态能力。')
              : ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final item = records[index];
                    final live = liveIds.contains(item.id);
                    return ListTile(
                      dense: true,
                      selected: item.id == _selectedId,
                      leading: Icon(
                        live ? Icons.radio_button_checked : Icons.circle,
                        size: 16,
                        color: live ? Colors.green : null,
                      ),
                      title: Text('${item.kind} · ${item.id}'),
                      subtitle: Text(
                        '${item.ownerComponentId} · ${item.packageName}',
                      ),
                      trailing: item.source == null
                          ? null
                          : const Icon(Icons.code, size: 18),
                      onTap: () => setState(() => _selectedId = item.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Shows a selected Catalog record and its source navigation target.
final class _CatalogRecordDetail extends StatelessWidget {
  /// Creates a detail row for [record].
  const _CatalogRecordDetail({
    required this.record,
    required this.live,
    this.onOpenSource,
  });

  /// Selected static record.
  final CCDevToolsCatalogRecord record;

  /// Whether the capability currently appears in the Runtime snapshot.
  final bool live;

  /// Optional Host-owned source opener.
  final ValueChanged<CCDevToolsSourceLocation>? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final source = record.source;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${record.kind} · ${record.id}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(live ? 'Runtime: active' : 'Runtime: not observed'),
          if (record.description case final description?) Text(description),
          if (source != null)
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    '${source.packageUri}:${source.line}:${source.column}',
                  ),
                ),
                if (onOpenSource != null)
                  IconButton(
                    tooltip: 'Open source',
                    onPressed: () => onOpenSource!(source),
                    icon: const Icon(Icons.open_in_new),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Displays component dependencies with search, focus, and reverse edges.
final class _ComponentGraphView extends StatefulWidget {
  /// Creates the component graph for [snapshot].
  const _ComponentGraphView({required this.snapshot});

  /// Immutable diagnostics data.
  final CCRouterDevToolsSnapshot snapshot;

  @override
  State<_ComponentGraphView> createState() => _ComponentGraphViewState();
}

final class _ComponentGraphViewState extends State<_ComponentGraphView> {
  final _query = TextEditingController();
  String? _focusedId;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final components = widget.snapshot.catalog?.components ?? const [];
    final fallback = widget.snapshot.components
        .map(
          (component) => CCDevToolsCatalogComponent(
            id: component.id,
            version: component.version,
            dependencies: component.dependencies,
            optionalDependencies: component.optionalDependencies,
          ),
        )
        .toList(growable: false);
    final nodes = components.isEmpty ? fallback : components;
    if (nodes.isEmpty) return const _EmptyState('没有已注册组件。');
    final query = _query.text.trim().toLowerCase();
    final visible = nodes
        .where((node) {
          if (query.isEmpty) return true;
          return node.id.toLowerCase().contains(query) ||
              node.version.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final focused = nodes.where((node) => node.id == _focusedId);
    final focusedNode = focused.isEmpty ? null : focused.first;
    final reverse = focusedNode == null
        ? const <String>[]
        : [
            for (final node in nodes)
              if (node.dependencies.contains(focusedNode.id) ||
                  node.optionalDependencies.contains(focusedNode.id))
                node.id,
          ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Filter components',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (focusedNode != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.center_focus_strong),
            title: Text('Focused: ${focusedNode.id}'),
            subtitle: Text(
              'depends on ${_joinOrNone(focusedNode.dependencies)} · '
              'reverse dependants ${_joinOrNone(reverse)}',
            ),
            trailing: IconButton(
              tooltip: 'Clear focus',
              onPressed: () => setState(() => _focusedId = null),
              icon: const Icon(Icons.clear),
            ),
          ),
        _SectionTitle('Component Graph', visible.length),
        Expanded(
          child: ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final component = visible[index];
              final isFocused = component.id == _focusedId;
              return ListTile(
                dense: true,
                selected: isFocused,
                leading: Icon(
                  isFocused ? Icons.center_focus_strong : Icons.hub_outlined,
                ),
                title: Text(component.id),
                subtitle: Text(
                  'v${component.version} · required: '
                  '${_joinOrNone(component.dependencies)}',
                ),
                trailing: component.optionalDependencies.isEmpty
                    ? null
                    : Tooltip(
                        message: component.optionalDependencies.join(', '),
                        child: const Icon(Icons.link, size: 18),
                      ),
                onTap: () => setState(() => _focusedId = component.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Displays managed Route Entries beside the hybrid backend ledger.
final class _EntriesView extends StatelessWidget {
  /// Creates the entry view for [snapshot].
  const _EntriesView({required this.snapshot});

  /// Immutable diagnostics data.
  final CCRouterDevToolsSnapshot snapshot;

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
  final CCRouterDevToolsSnapshot snapshot;

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
  final CCRouterDevToolsSnapshot snapshot;

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
            leading: Icon(
              event.recovered
                  ? Icons.replay
                  : event.context.reason == CCNavigationFailureReason.cancelled
                  ? Icons.cancel_outlined
                  : Icons.error_outline,
            ),
            title: Text(
              '${event.context.routeId ?? 'unknown'} · '
              '${event.context.stage.name}',
            ),
            subtitle: Text(
              '${event.context.reason.name} · '
              '${event.context.errorType} · '
              '${event.recovered
                  ? 'recovery selected'
                  : event.context.reason == CCNavigationFailureReason.cancelled
                  ? 'cancelled'
                  : 'failed'}\n'
              '${event.context.navigationId} · ${event.context.hostId ?? 'unknown'}/${event.context.outlet ?? 'unknown'}\n'
              'attempt=${event.context.attempt.name} · depth=${event.context.recoveryDepth} · initial=${event.context.initialRouteId ?? 'unknown'}',
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
            subtitle: Text(
              '${event.operation.name} → ${event.behavior.name}\n${event.navigationId} · ${event.hostId}/${event.navigatorOutlet}',
            ),
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
              '${pending.operation.name} · ${pending.navigationId}\n'
              '${pending.hostId ?? 'unknown'}/${pending.outlet ?? 'unknown'}',
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
  final CCRouterDevToolsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.initTasks.isEmpty) {
      return const _EmptyState('没有注册 InitTask。');
    }
    final tasks = {for (final task in snapshot.initTasks) task.id: task};
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SectionTitle('InitTask DAG', snapshot.initTasks.length),
        for (final task in snapshot.initTasks)
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

/// Displays static capability relations beside bounded runtime trace edges.
final class _CallGraphView extends StatelessWidget {
  /// Creates a call graph for [snapshot].
  const _CallGraphView({required this.snapshot});

  /// Immutable diagnostics data.
  final CCRouterDevToolsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final staticEdges =
        snapshot.catalog?.relations
            .where((relation) => relation.kind != 'dependsOn')
            .toList(growable: false) ??
        const <CCDevToolsCatalogRelation>[];
    final runtimeEdges = snapshot.toProtocolRuntimeSnapshot().traceEdges.toList(
      growable: false,
    );
    if (staticEdges.isEmpty && runtimeEdges.isEmpty) {
      return const _EmptyState('没有静态关系或运行时调用链。');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SectionTitle('Static capability relations', staticEdges.length),
        for (final edge in staticEdges)
          ListTile(
            dense: true,
            leading: const Icon(Icons.account_tree_outlined),
            title: Text('${edge.sourceId} → ${edge.targetId}'),
            subtitle: Text(edge.kind),
          ),
        _SectionTitle('Runtime call chain', runtimeEdges.length),
        for (final edge in runtimeEdges)
          ListTile(
            dense: true,
            leading: Icon(_traceStatusIcon(edge.status)),
            title: Text('${edge.sourceId} → ${edge.targetId}'),
            subtitle: Text(
              '${edge.kind} · ${edge.status} · trace ${edge.traceId}',
            ),
            trailing: Text('${edge.durationMicros} μs'),
          ),
      ],
    );
  }
}

/// Formats a bounded duration without exposing arbitrary payloads.
String _duration(Duration duration) => '${duration.inMilliseconds} ms';

/// Formats a diagnostic timestamp for a compact list row.
String _time(DateTime timestamp) => timestamp.toLocal().toIso8601String();

/// Joins a bounded list for compact graph labels.
String _joinOrNone(Iterable<String> values) {
  final items = values.toList(growable: false);
  return items.isEmpty ? 'none' : items.join(', ');
}

/// Selects an icon for one trace outcome.
IconData _traceStatusIcon(String status) => switch (status) {
  'succeeded' || 'completed' => Icons.check_circle_outline,
  'failed' || 'cancelled' => Icons.error_outline,
  _ => Icons.timeline,
};

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
IconData _taskStateIcon(CCInitTaskState state) => switch (state) {
  CCInitTaskState.succeeded => Icons.check_circle_outline,
  CCInitTaskState.failed => Icons.error_outline,
  CCInitTaskState.skipped => Icons.skip_next,
  CCInitTaskState.running => Icons.timelapse,
  CCInitTaskState.pending => Icons.schedule,
};
