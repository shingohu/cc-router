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
      if (json == null)
        throw StateError('CCRouter snapshot response is empty.');
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
    final runtime = envelope.runtime;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CCRouter'),
        actions: [
          IconButton(
            tooltip: 'Refresh snapshot',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
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
          _MetricRow(
            label: 'Trace edges',
            value: '${runtime.traceEdges.length}',
          ),
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
          const SizedBox(height: 16),
          const Text(
            'Trace edges',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final edge in runtime.traceEdges)
            ListTile(
              dense: true,
              title: Text('${edge.kind}: ${edge.targetId}'),
              subtitle: Text('${edge.sourceId} -> ${edge.status}'),
              trailing: Text('${edge.durationMicros} us'),
            ),
        ],
      ),
    );
  }
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
