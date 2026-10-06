@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../ccrouter_generator/bin/src/canonical_directory_identity.dart';
import '../../ccrouter_generator/bin/src/coordination_home.dart';

void main() {
  test('CCROUTER_HOME overrides platform defaults', () {
    final root = Directory.systemTemp.createTempSync('ccrouter_home_override_');
    addTearDown(() => root.deleteSync(recursive: true));

    final resolved = resolveCCRouterHome(
      environment: {ccrouterHomeEnvironment: root.path},
      operatingSystem: 'linux',
    );

    expect(resolved.path, root.absolute.path);
  });

  test('platform defaults follow CLI tool conventions', () {
    expect(
      resolveCCRouterHome(
        environment: {'HOME': path.join('tmp', 'developer')},
        operatingSystem: 'macos',
      ).path,
      Directory(path.join('tmp', 'developer', '.ccrouter')).absolute.path,
    );
    expect(
      resolveCCRouterHome(
        environment: {'LOCALAPPDATA': path.join('tmp', 'local')},
        operatingSystem: 'windows',
      ).path,
      Directory(path.join('tmp', 'local', 'CCRouter')).absolute.path,
    );
  });

  test('build roots and Hosts receive two-level identities', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ccrouter_coordination_paths_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final home = Directory(path.join(temporary.path, 'home'));
    final firstRoot = Directory(path.join(temporary.path, 'workspace'))
      ..createSync();
    final secondRoot = Directory(path.join(temporary.path, 'other'))
      ..createSync();
    final firstHost = Directory(path.join(firstRoot.path, 'apps', 'first'))
      ..createSync(recursive: true);
    final secondHost = Directory(path.join(firstRoot.path, 'apps', 'second'))
      ..createSync(recursive: true);

    final first = CCRouterCoordinationPaths.forBuildRoot(
      firstRoot,
      environment: {ccrouterHomeEnvironment: home.path},
    );
    final sameProject = CCRouterCoordinationPaths.forBuildRoot(
      firstRoot,
      environment: {ccrouterHomeEnvironment: home.path},
    );
    final other = CCRouterCoordinationPaths.forBuildRoot(
      secondRoot,
      environment: {ccrouterHomeEnvironment: home.path},
    );

    expect(first.projectIdentity, hasLength(64));
    expect(first.projectDirectory.path, sameProject.projectDirectory.path);
    expect(first.projectDirectory.path, isNot(other.projectDirectory.path));
    expect(first.hostIdentity(firstHost), hasLength(64));
    expect(
      first.registrationLock(firstHost).path,
      isNot(first.registrationLock(secondHost).path),
    );
    expect(
      first.sessionDocument(firstHost).parent.path,
      path.join(first.projectDirectory.path, 'sessions'),
    );
    final firstLease = first.newFlutterRunLease(
      firstHost,
      ownerPid: 42,
      nonce: 7,
    );
    final secondLease = first.newFlutterRunLease(
      secondHost,
      ownerPid: 42,
      nonce: 7,
    );
    expect(
      firstLease.parent.path,
      path.join(
        first.projectDirectory.path,
        'leases',
        first.hostIdentity(firstHost),
      ),
    );
    expect(firstLease.path, isNot(secondLease.path));
    expect(
      path.isWithin(firstRoot.path, firstLease.path),
      isFalse,
      reason: 'a project clean must not delete a live Flutter-run lease',
    );

    await first.prepare();
    final document =
        jsonDecode(first.projectDocument.readAsStringSync())
            as Map<String, dynamic>;
    expect(document['schemaVersion'], 2);
    expect(document['buildRoot'], canonicalDirectoryIdentity(firstRoot.path));
    expect(document['projectIdentity'], first.projectIdentity);
    await sameProject.prepare();
  });

  test('symlink aliases share one project identity', () async {
    if (Platform.isWindows) return;
    final temporary = await Directory.systemTemp.createTemp(
      'ccrouter_coordination_symlink_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final root = Directory(path.join(temporary.path, 'workspace'))
      ..createSync();
    final alias = Link(path.join(temporary.path, 'workspace-link'))
      ..createSync(root.path);
    final environment = {
      ccrouterHomeEnvironment: path.join(temporary.path, 'home'),
    };

    final direct = CCRouterCoordinationPaths.forBuildRoot(
      root,
      environment: environment,
    );
    final linked = CCRouterCoordinationPaths.forBuildRoot(
      Directory(alias.path),
      environment: environment,
    );

    expect(linked.canonicalBuildRoot, direct.canonicalBuildRoot);
    expect(linked.projectIdentity, direct.projectIdentity);
  });

  test('stable Host and Builder sessions validate exact identities', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ccrouter_coordination_sessions_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final buildRoot = Directory(path.join(temporary.path, 'workspace'))
      ..createSync();
    final hostRoot = Directory(path.join(buildRoot.path, 'app'))..createSync();
    final otherHost = Directory(path.join(buildRoot.path, 'other'))
      ..createSync();
    final environment = {
      ccrouterHomeEnvironment: path.join(temporary.path, 'home'),
    };
    final hostStatus = <String, Object?>{
      'schemaVersion': 1,
      'active': true,
      'sessionId': 'host-session',
    };
    final builderStatus = <String, Object?>{
      'schemaVersion': 1,
      'active': true,
      'sessionId': 'builder-session',
    };

    await publishCCRouterHostSession(
      hostRoot: hostRoot,
      buildRoot: buildRoot,
      status: hostStatus,
      environment: environment,
    );
    await publishCCRouterBuilderSession(
      buildRoot: buildRoot,
      status: builderStatus,
      environment: environment,
    );

    expect(
      await readCCRouterHostSession(
        hostRoot: hostRoot,
        buildRoot: buildRoot,
        environment: environment,
      ),
      hostStatus,
    );
    expect(
      await readCCRouterHostSession(
        hostRoot: otherHost,
        buildRoot: buildRoot,
        environment: environment,
      ),
      isNull,
    );
    expect(
      await readCCRouterBuilderSession(
        buildRoot: buildRoot,
        environment: environment,
      ),
      builderStatus,
    );
  });
}
