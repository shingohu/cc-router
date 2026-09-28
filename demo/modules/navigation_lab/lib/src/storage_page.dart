import 'dart:convert';

import 'package:ccrouter/ccrouter.dart';
import 'package:demo_kv_storage/demo_kv_storage.dart';
import 'package:flutter/material.dart';

import 'ccrouter_generated/demo_navigation_lab_component.api.g.dart';

/// Demonstrates typed key-value storage and namespace isolation.
@CCRoute<void>(
  id: 'demo_navigation_lab.storage',
  pattern: CCPathPattern('/lab/storage'),
  description: '基本类型、JSON Map 和受控存储命名空间示例。',
)
final class DemoStoragePage extends StatefulWidget {
  /// Creates the storage integration page.
  const DemoStoragePage({super.key});

  @override
  State<DemoStoragePage> createState() => _DemoStoragePageState();
}

final class _DemoStoragePageState extends State<DemoStoragePage> {
  DemoKeyValueStorageService get _service =>
      DemoNavigationLabServices.demoKeyValueStorage;

  late final DemoScopedStorage _storage;

  static const _namespaceLabels = <String>[
    '全局',
    '游客',
    '用户:demo-account',
    'API:development',
    '硬件:demo-device',
  ];

  final _keyController = TextEditingController(text: 'onboarding.completed');
  final _valueController = TextEditingController(text: 'true');
  int _namespaceIndex = 0;
  String _status = '尚未操作';
  List<String> _keys = const [];

  DemoStorageScope get _scope => switch (_namespaceIndex) {
    0 => _storage.global,
    1 => _storage.guest,
    2 => _storage.currentUser,
    3 => _storage.currentEnvironment,
    _ => _storage.hardware,
  };

  @override
  void initState() {
    super.initState();
    _storage = DemoScopedStorage(
      service: _service,
      contextProvider: DemoMutableStorageContextProvider(
        const DemoStorageContextSnapshot(
          accountId: 'demo-account',
          environmentId: 'development',
          deviceId: 'demo-device',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _saveString() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return _setStatus('Key 不能为空');
    await _scope.setString(key, _valueController.text);
    await _refreshKeys();
    _setStatus('已保存 String · ${_namespaceLabels[_namespaceIndex]}/$key');
  }

  Future<void> _saveInt() async {
    final key = _keyController.text.trim();
    final value = int.tryParse(_valueController.text.trim());
    if (key.isEmpty || value == null) return _setStatus('Key 或 Int 值无效');
    await _scope.setInt(key, value);
    await _refreshKeys();
    _setStatus('已保存 Int · $value');
  }

  Future<void> _saveJson() async {
    final key = _keyController.text.trim();
    try {
      final decoded = jsonDecode(_valueController.text);
      if (decoded is! Map) throw const FormatException('JSON 必须是 object');
      final value = decoded.map<String, Object?>(
        (key, value) => MapEntry(key, value),
      );
      await _scope.setJson(key, value);
      await _refreshKeys();
      _setStatus('已保存 JSON Map');
    } on Object catch (error) {
      _setStatus('JSON 无效 · ${error.runtimeType}');
    }
  }

  Future<void> _saveDouble() async {
    final key = _keyController.text.trim();
    final value = double.tryParse(_valueController.text.trim());
    if (key.isEmpty || value == null) return _setStatus('Key 或 Double 值无效');
    await _scope.setDouble(key, value);
    await _refreshKeys();
    _setStatus('已保存 Double · $value');
  }

  Future<void> _saveBool() async {
    final key = _keyController.text.trim();
    final value = switch (_valueController.text.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    if (key.isEmpty || value == null) return _setStatus('Key 或 Bool 值无效');
    await _scope.setBool(key, value);
    await _refreshKeys();
    _setStatus('已保存 Bool · $value');
  }

  Future<void> _read() async {
    final key = _keyController.text.trim();
    try {
      final string = await _scope.getString(key);
      if (string != null) {
        _valueController.text = string;
        _setStatus('读取 String · $string');
        return;
      }
    } on CCStorageTypeError {
      // Try the remaining typed readers for a type-neutral Demo read action.
    }
    try {
      final integer = await _scope.getInt(key);
      if (integer != null) {
        _valueController.text = '$integer';
        _setStatus('读取 Int · $integer');
        return;
      }
    } on CCStorageTypeError {
      // Continue with the next supported value kind.
    }
    try {
      final doubleValue = await _scope.getDouble(key);
      if (doubleValue != null) {
        _valueController.text = '$doubleValue';
        _setStatus('读取 Double · $doubleValue');
        return;
      }
    } on CCStorageTypeError {
      // Continue with the next supported value kind.
    }
    try {
      final boolValue = await _scope.getBool(key);
      if (boolValue != null) {
        _valueController.text = '$boolValue';
        _setStatus('读取 Bool · $boolValue');
        return;
      }
    } on CCStorageTypeError {
      // Continue with JSON.
    }
    final json = await _scope.getJson(key);
    if (json != null) {
      _valueController.text = jsonEncode(json);
      _setStatus('读取 JSON Map');
      return;
    }
    _setStatus('未找到 $key');
  }

  Future<void> _remove() async {
    final key = _keyController.text.trim();
    await _scope.remove(key);
    await _refreshKeys();
    _setStatus('已删除 $key');
  }

  Future<void> _clear() async {
    await _scope.clear();
    await _refreshKeys();
    _setStatus('已清空 ${_namespaceLabels[_namespaceIndex]}');
  }

  Future<void> _refreshKeys() async {
    _keys = await _scope.keys();
    if (mounted) setState(() {});
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('KV Storage')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      children: [
        const Text(
          '共享 KV Storage Service',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '业务通过 Scoped Facade 选择受控范围，不再为每次读写传入账号或环境 ID。当前 Demo 使用内存 Backend，后续可以替换为文件、数据库或安全存储实现。',
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          initialValue: _namespaceIndex,
          decoration: const InputDecoration(
            labelText: '存储命名空间',
            border: OutlineInputBorder(),
          ),
          items: [
            for (var index = 0; index < _namespaceLabels.length; index++)
              DropdownMenuItem(
                value: index,
                child: Text(_namespaceLabels[index]),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _namespaceIndex = value);
            _refreshKeys();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          decoration: const InputDecoration(
            labelText: 'Key',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _valueController,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Value / JSON object',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _saveString,
              icon: const Icon(Icons.text_fields),
              label: const Text('保存 String'),
            ),
            OutlinedButton.icon(
              onPressed: _saveInt,
              icon: const Icon(Icons.numbers),
              label: const Text('保存 Int'),
            ),
            OutlinedButton.icon(
              onPressed: _saveDouble,
              icon: const Icon(Icons.looks_one_outlined),
              label: const Text('保存 Double'),
            ),
            OutlinedButton.icon(
              onPressed: _saveBool,
              icon: const Icon(Icons.toggle_on_outlined),
              label: const Text('保存 Bool'),
            ),
            OutlinedButton.icon(
              onPressed: _saveJson,
              icon: const Icon(Icons.data_object),
              label: const Text('保存 JSON'),
            ),
            OutlinedButton.icon(
              onPressed: _read,
              icon: const Icon(Icons.download_outlined),
              label: const Text('读取'),
            ),
            OutlinedButton.icon(
              onPressed: _remove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除'),
            ),
            OutlinedButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.clear_all),
              label: const Text('清空命名空间'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SelectableText(_status),
        const Divider(height: 32),
        Text('当前命名空间 Key', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_keys.isEmpty) const Text('暂无数据'),
        for (final key in _keys) ListTile(dense: true, title: Text(key)),
      ],
    ),
  );
}
