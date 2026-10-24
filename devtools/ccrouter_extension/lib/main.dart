import 'package:ccrouter_devtools_protocol/ccrouter_devtools_protocol.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

void main() => runApp(const CCRouterDevToolsExtensionApp());

/// Root widget for the official read-only CCRouter DevTools Extension.
final class CCRouterDevToolsExtensionApp extends StatelessWidget {
  /// Creates the extension root.
  const CCRouterDevToolsExtensionApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const DevToolsExtension(child: _ConnectionView());
}

final class _ConnectionView extends StatefulWidget {
  const _ConnectionView();

  @override
  State<_ConnectionView> createState() => _ConnectionViewState();
}

final class _ConnectionViewState extends State<_ConnectionView> {
  CCDevToolsSnapshotEnvelope? _envelope;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    serviceManager.registerLifecycleCallback(
      ServiceManagerLifecycle.afterCloseVmService,
      (_) {
        if (!mounted) return;
        setState(() {
          _envelope = null;
          _loading = false;
          _error = null;
        });
      },
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = serviceManager.service;
      if (service == null) {
        throw StateError('VM Service is not connected.');
      }
      final response = await service.callServiceExtension(
        'ext.ccrouter.snapshot',
      );
      final json = response.json;
      if (json == null) {
        throw StateError('CCRouter snapshot response is empty.');
      }
      final payload = json['json'];
      if (payload is! String) {
        throw StateError('CCRouter snapshot is malformed.');
      }
      final source = payload;
      final envelope = CCDevToolsSnapshotEnvelope.decode(source);
      if (!mounted) return;
      setState(() {
        _envelope = envelope;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final envelope = _envelope;
    if (_error != null || envelope == null) {
      return _MessageView(
        message: _error?.toString() ?? 'CCRouter Runtime is not connected.',
        onRefresh: _load,
      );
    }
    return _SnapshotView(envelope: envelope, onRefresh: _load);
  }
}

final class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.onRefresh});

  final String message;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
    ),
  );
}

final class _SnapshotView extends StatelessWidget {
  const _SnapshotView({required this.envelope, required this.onRefresh});

  final CCDevToolsSnapshotEnvelope envelope;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('CCRouter'),
          actions: [
            IconButton(
              tooltip: 'Refresh snapshot',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Catalog'),
              Tab(text: 'Components'),
              Tab(text: 'Call Graph'),
              Tab(text: 'Diagnostics'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(envelope: envelope),
            _CatalogTab(envelope: envelope),
            _ComponentsTab(envelope: envelope),
            _CallGraphTab(envelope: envelope),
            _DiagnosticsTab(runtime: envelope.runtime),
          ],
        ),
      ),
    );
  }
}

final class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.envelope});

  final CCDevToolsSnapshotEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final runtime = envelope.runtime;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricRow(label: 'Runtime', value: runtime.runtimeState),
        _MetricRow(
          label: 'Installed components',
          value: '${runtime.installedComponentIds.length}',
        ),
        _MetricRow(
          label: 'Runtime entries',
          value: '${runtime.entries.length}',
        ),
        _MetricRow(label: 'Trace edges', value: '${runtime.traceEdges.length}'),
        _MetricRow(
          label: 'Static catalog',
          value: envelope.catalog == null
              ? 'not provided'
              : '${envelope.catalog!.records.length} records',
        ),
        const SizedBox(height: 16),
        const Text(
          'Runtime entries',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final entry in runtime.entries)
          ListTile(
            dense: true,
            title: Text(entry.routeId ?? entry.id),
            subtitle: Text('${entry.kind} · ${entry.hostId}/${entry.outlet}'),
            trailing: Text(entry.state),
          ),
      ],
    );
  }
}

/// Renders optional protocol diagnostics with explicit old-producer states.
final class _DiagnosticsTab extends StatelessWidget {
  const _DiagnosticsTab({required this.runtime});

  final CCDevToolsRuntimeSnapshot runtime;

  @override
  Widget build(BuildContext context) {
    final health = runtime.diagnosticHealth;
    final diagnostics = runtime.diagnostics;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (health == null)
          const ListTile(
            title: Text('Diagnostic health not provided by producer'),
          )
        else ...[
          ListTile(
            title: Text(
              health.sinkConfigured
                  ? 'External Sink configured'
                  : 'External Sink not configured',
            ),
            subtitle: Text(
              'queued=${health.queued}/${health.queueCapacity} · inFlight=${health.inFlight} · peak=${health.peakQueued}\n'
              'delivered=${health.delivered} · failed=${health.failed} · dropped=${health.dropped} · closed=${health.closed}',
            ),
          ),
          const Text(
            'History omissions and external Sink losses are independent. Empty history does not prove absence of failures. Delivered means Sink completion only.',
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
        if (diagnostics == null)
          const ListTile(
            title: Text(
              'Failure / Fallback / Pending / InitTask diagnostics not provided by producer',
            ),
          )
        else if (diagnostics.isEmpty)
          const ListTile(
            title: Text('No retained diagnostics or live task/pending state'),
          )
        else
          for (final record in diagnostics)
            ListTile(
              dense: true,
              title: Text(
                '${record.kind} · ${record.routeId ?? record.id} · ${record.status}',
              ),
              subtitle: Text(
                [
                  'id=${record.id}',
                  if (record.kind != 'initTask')
                    '${record.hostId ?? 'unknown'}/${record.outlet ?? 'unknown'}',
                  if (record.operation != null) 'operation=${record.operation}',
                  if (record.reason != null) 'reason=${record.reason}',
                  if (record.stage != null) 'stage=${record.stage}',
                  if (record.attempt != null)
                    'attempt=${record.attempt} · depth=${record.recoveryDepth}',
                  if (record.initialRouteId != null)
                    'initial=${record.initialRouteId}',
                  if (record.errorType != null) 'error=${record.errorType}',
                  if (record.capability != null)
                    '${record.capability} → ${record.behavior}',
                  if (record.origin != null) 'origin=${record.origin}',
                  if (record.expiresAt != null) 'expires=${record.expiresAt}',
                  if (record.ownerComponentId != null)
                    'owner=${record.ownerComponentId}',
                  if (record.gateId != null)
                    'gate=${record.gateId} · policy=${record.failurePolicy}',
                  if (record.dependsOn.isNotEmpty)
                    'dependsOn=${record.dependsOn.join(', ')}',
                  if (record.blockedByTaskId != null)
                    'blockedBy=${record.blockedByTaskId}',
                  if (record.durationMicros != null)
                    'duration=${record.durationMicros}µs',
                ].join('\n'),
              ),
            ),
      ],
    );
  }
}

final class _CatalogTab extends StatelessWidget {
  const _CatalogTab({required this.envelope});

  final CCDevToolsSnapshotEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final catalog = envelope.catalog;
    if (catalog == null) {
      return const Center(child: Text('Static Catalog not provided by Host.'));
    }
    final liveIds = {
      for (final entry in envelope.runtime.entries) entry.routeId,
      for (final edge in envelope.runtime.traceEdges) edge.targetId,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Catalog ${catalog.catalogFingerprint ?? ''}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (final record in catalog.records)
          ExpansionTile(
            leading: Icon(
              liveIds.contains(record.id)
                  ? Icons.radio_button_checked
                  : Icons.circle,
              size: 16,
              color: liveIds.contains(record.id) ? Colors.green : null,
            ),
            title: Text('${record.kind} · ${record.id}'),
            subtitle: Text(
              '${record.ownerComponentId} · ${record.packageName}',
            ),
            children: [
              if (record.description case final description?)
                ListTile(title: Text(description)),
              if (record.source case final source?)
                ListTile(
                  leading: const Icon(Icons.code),
                  title: SelectableText(
                    '${source.packageUri}:${source.line}:${source.column}',
                  ),
                  subtitle: const Text(
                    'Source location; open in IDE from the Host mapping.',
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

final class _ComponentsTab extends StatelessWidget {
  const _ComponentsTab({required this.envelope});

  final CCDevToolsSnapshotEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final catalog = envelope.catalog;
    final components =
        catalog?.components ?? const <CCDevToolsCatalogComponent>[];
    if (components.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('No static component graph.'),
          for (final id in envelope.runtime.installedComponentIds)
            ListTile(
              title: Text(id),
              subtitle: const Text('Runtime installed'),
            ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: components.length,
      itemBuilder: (context, index) {
        final component = components[index];
        final reverse = [
          for (final candidate in components)
            if (candidate.dependencies.contains(component.id) ||
                candidate.optionalDependencies.contains(component.id))
              candidate.id,
        ];
        return ExpansionTile(
          leading: const Icon(Icons.hub_outlined),
          title: Text(component.id),
          subtitle: Text('v${component.version}'),
          children: [
            ListTile(
              title: Text('Depends on: ${_join(component.dependencies)}'),
            ),
            ListTile(
              title: Text('Optional: ${_join(component.optionalDependencies)}'),
            ),
            ListTile(title: Text('Used by: ${_join(reverse)}')),
          ],
        );
      },
    );
  }
}

final class _CallGraphTab extends StatelessWidget {
  const _CallGraphTab({required this.envelope});

  final CCDevToolsSnapshotEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final catalogEdges =
        envelope.catalog?.relations
            .where((relation) => relation.kind != 'dependsOn')
            .toList(growable: false) ??
        const <CCDevToolsCatalogRelation>[];
    final runtimeEdges = envelope.runtime.traceEdges;
    if (catalogEdges.isEmpty && runtimeEdges.isEmpty) {
      return const Center(child: Text('No capability call-chain data.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Static relations',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final edge in catalogEdges)
          ListTile(
            dense: true,
            leading: const Icon(Icons.account_tree_outlined),
            title: Text('${edge.sourceId} → ${edge.targetId}'),
            subtitle: Text(edge.kind),
          ),
        const Text(
          'Runtime call chain',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final edge in runtimeEdges)
          ListTile(
            dense: true,
            leading: const Icon(Icons.timeline),
            title: Text('${edge.sourceId} → ${edge.targetId}'),
            subtitle: Text('${edge.kind} · ${edge.status} · ${edge.traceId}'),
            trailing: Text('${edge.durationMicros} us'),
          ),
      ],
    );
  }
}

String _join(Iterable<String> values) {
  final list = values.toList(growable: false);
  return list.isEmpty ? 'none' : list.join(', ');
}

final class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text(value)],
    ),
  );
}
