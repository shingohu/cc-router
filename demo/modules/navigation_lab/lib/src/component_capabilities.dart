import 'package:ccrouter/ccrouter.dart';

const demoPrivacyGrantedGate = CCInitializationGate('demo.privacy-granted');

const demoBackupChannelKey = CCServiceKey<DemoChannelService>('backup');

final class DemoCreateReceiptCommand implements CCCommand<String> {
  const DemoCreateReceiptCommand(this.amount);

  final int amount;
}

final class DemoRefreshCacheCommand implements CCCommand<void> {
  const DemoRefreshCacheCommand();
}

final class DemoWaitCommand implements CCCommand<void> {
  const DemoWaitCommand();
}

final class DemoFailCommand implements CCCommand<void> {
  const DemoFailCommand();
}

final class DemoOrderCompletedEvent implements CCEvent {
  const DemoOrderCompletedEvent(this.orderId);

  final int orderId;
}

final class DemoUnobservedEvent implements CCEvent {
  const DemoUnobservedEvent();
}

final class DemoSlowEvent implements CCEvent {
  const DemoSlowEvent();
}

final class DemoAppService implements CCDisposable {
  DemoAppService(this.instanceId, this.onDispose);

  final int instanceId;
  final void Function(String) onDispose;

  @override
  void dispose() => onDispose('App Service #$instanceId disposed');
}

final class DemoSessionService implements CCDisposable {
  DemoSessionService(this.instanceId, this.onDispose);

  final int instanceId;
  final void Function(String) onDispose;

  @override
  void dispose() => onDispose('Session Service #$instanceId disposed');
}

final class DemoRouteService implements CCDisposable {
  DemoRouteService(this.instanceId, this.onDispose);

  final int instanceId;
  final void Function(String) onDispose;

  @override
  void dispose() => onDispose('Route Service #$instanceId disposed');
}

final class DemoFactoryService {
  const DemoFactoryService(this.instanceId);

  final int instanceId;
}

final class DemoLazyService {
  DemoLazyService(this.instanceId);

  final int instanceId;
  bool ready = false;
}

abstract interface class DemoChannelService {
  String get name;
}

final class DemoPrimaryChannelService implements DemoChannelService {
  const DemoPrimaryChannelService();

  @override
  String get name => 'primary';
}

final class DemoBackupChannelService implements DemoChannelService {
  const DemoBackupChannelService();

  @override
  String get name => 'backup';
}

abstract interface class DemoMissingService {}

final class DemoCapabilityInstanceIds {
  DemoCapabilityInstanceIds._();

  static int _nextValue = 0;

  static int next() => ++_nextValue;
}
