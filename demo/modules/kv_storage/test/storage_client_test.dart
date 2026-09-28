import 'package:demo_kv_storage/demo_kv_storage.dart';
import 'package:test/test.dart';

void main() {
  test('stores supported primitive values by namespace', () async {
    final backend = _FakeStorageBackend();
    final client = CCStorageClient(backend: backend);
    const global = DemoStorageNamespace.global();
    const guest = DemoStorageNamespace.guest();

    await client.setString(global, 'language', 'zh-CN');
    await client.setInt(global, 'launchCount', 3);
    await client.setDouble(global, 'ratio', 0.75);
    await client.setBool(global, 'onboarding.completed', true);
    await client.setString(guest, 'language', 'en-US');

    expect(await client.getString(global, 'language'), 'zh-CN');
    expect(await client.getInt(global, 'launchCount'), 3);
    expect(await client.getDouble(global, 'ratio'), 0.75);
    expect(await client.getBool(global, 'onboarding.completed'), isTrue);
    expect(await client.getString(guest, 'language'), 'en-US');
    expect(
      await client.keys(global),
      containsAll(<String>[
        'language',
        'launchCount',
        'ratio',
        'onboarding.completed',
      ]),
    );
  });

  test('copies JSON values on write and read', () async {
    final client = CCStorageClient(backend: _FakeStorageBackend());
    const namespace = DemoStorageNamespace.global();
    final source = <String, Object?>{
      'profile': <String, Object?>{
        'name': 'Demo',
        'roles': <Object?>['reader', 'tester'],
      },
    };

    await client.setJson(namespace, 'profile', source);
    (source['profile']! as Map<String, Object?>)['name'] = 'changed';

    final result = await client.getJson(namespace, 'profile');
    expect(result, {
      'profile': {
        'name': 'Demo',
        'roles': ['reader', 'tester'],
      },
    });
    (result!['profile']! as Map<String, Object?>)['name'] = 'changed again';
    expect((await client.getJson(namespace, 'profile'))!['profile'], {
      'name': 'Demo',
      'roles': ['reader', 'tester'],
    });
  });

  test('rejects a typed read when the stored kind differs', () async {
    final client = CCStorageClient(backend: _FakeStorageBackend());
    const namespace = DemoStorageNamespace.global();
    await client.setInt(namespace, 'count', 1);

    expect(
      () => client.getString(namespace, 'count'),
      throwsA(isA<CCStorageTypeError>()),
    );
  });

  test('clear and remove do not cross namespace boundaries', () async {
    final client = CCStorageClient(backend: _FakeStorageBackend());
    final user = DemoStorageNamespace.user('account-1');
    final otherUser = DemoStorageNamespace.user('account-2');

    await client.setString(user, 'theme', 'dark');
    await client.setString(otherUser, 'theme', 'light');
    await client.remove(user, 'missing');
    await client.clear(user);

    expect(await client.getString(user, 'theme'), isNull);
    expect(await client.getString(otherUser, 'theme'), 'light');
  });

  test('dispose is idempotent and rejects later access', () async {
    final backend = _FakeStorageBackend();
    final client = CCStorageClient(backend: backend);

    await client.dispose();
    await client.dispose();

    expect(backend.closeCount, 1);
    expect(
      () => client.getString(const DemoStorageNamespace.global(), 'key'),
      throwsStateError,
    );
  });
}

final class _FakeStorageBackend implements CCStorageBackend {
  final values = <String, CCStorageValue>{};
  int closeCount = 0;

  @override
  Future<void> write(String qualifiedKey, CCStorageValue value) async {
    values[qualifiedKey] = value;
  }

  @override
  Future<CCStorageValue?> read(String qualifiedKey) async =>
      values[qualifiedKey];

  @override
  Future<void> remove(String qualifiedKey) async {
    values.remove(qualifiedKey);
  }

  @override
  Future<void> clear(String namespacePrefix) async {
    values.removeWhere((key, _) => key.startsWith(namespacePrefix));
  }

  @override
  Future<List<String>> keys(String namespacePrefix) async => values.keys
      .where((key) => key.startsWith(namespacePrefix))
      .toList(growable: false);

  @override
  Future<void> close() async {
    closeCount++;
  }
}
