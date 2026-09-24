# Memory And Lifecycle Review Examples

Use these examples only to calibrate evidence. Ownership in the actual code is
authoritative.

## True positives

### Disposable animation recreated during build

```dart
Widget build(BuildContext context) {
  final curved = CurvedAnimation(parent: controller, curve: Curves.easeIn);
  return FadeTransition(opacity: curved, child: child);
}
```

Every rebuild creates an owned disposable animation with no cleanup path. Keep
it as owner state, replace it only when its parent changes, and dispose it.

### Anonymous listener registered repeatedly

```dart
Widget build(BuildContext context) {
  notifier.addListener(() => setState(() {}));
  return child;
}
```

Rebuilds accumulate callbacks, and the anonymous callback cannot be removed by
identity. Register once, retain the callback, and remove it at owner disposal.

### Timer created after its owner ended

```dart
Future<void> load() async {
  await source.load();
  timer = Timer.periodic(const Duration(seconds: 1), (_) => poll());
}
```

If the owner can end while awaiting, the continuation creates a Timer that
retains it. Check the lifecycle/cancellation state after the await, guard the
callback, and cancel the Timer at cleanup.

### Subscription retained by a Runtime registry

```dart
subscription = backend.events.listen(handleEvent);
```

If Runtime shutdown clears its local field but never cancels `subscription`, the
stream retains `handleEvent` and the Runtime. Cancel the subscription before
clearing registries and add a shutdown regression test.

## False positives

### Field-owned controller is disposed

```dart
final controller = TextEditingController();

@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

Do not report when creation and cleanup have the same reachable owner.

### Timer has owner and callback guards

```dart
Timer? timer;

void close() {
  timer?.cancel();
  timer = null;
}

void start() {
  timer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (closed) {
      timer?.cancel();
      return;
    }
    tick();
  });
}
```

Do not report when every terminal path reaches `close` and tests prove it.

### Resource is owned by a longer-lived Scope

A page using a Route Service does not dispose the Service itself. Do not report
when the exact Route Scope owns and disposes it after RouteEntry removal. Report
only if that Scope cleanup is missing or the Service remains retained afterward.
