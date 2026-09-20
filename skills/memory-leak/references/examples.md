# Review examples

Use these patterns to calibrate high-confidence reporting.

## True positives

### CurvedAnimation recreated in build

```dart
Widget build(BuildContext context) {
  final curved = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
  return FadeTransition(opacity: curved, child: child);
}
```

Report: `not-disposed`. Each rebuild creates a new `CurvedAnimation` that is never disposed.

### Anonymous listener in rebuild path

```dart
Widget build(BuildContext context) {
  _notifier.addListener(() => setState(() {}));
  return child;
}
```

Report: `not-disposed` or `not-GCed`. Rebuilds accumulate listeners that cannot be removed symmetrically.

### Timer after async without lifecycle guard

```dart
Future<void> load() async {
  await api.fetch();
  _timer = Timer.periodic(const Duration(seconds: 1), (_) => poll());
}
```

Report: `not-disposed` when the owning page can be destroyed before `load()` completes and there is no `mounted` / `isClosed` / dispose guard.

### BuildContext retained across async gap

```dart
Future<void> _open() async {
  await Future.delayed(const Duration(seconds: 1));
  Navigator.of(_context).pop();
}
```

Report: `not-GCed` when `_context` is stored in a field or used after async work without checking `mounted`.

### Inline scroll controller

```dart
CupertinoPicker(
  scrollController: FixedExtentScrollController(),
  itemExtent: 32,
  onSelectedItemChanged: (_) {},
  children: const [],
)
```

Report: `not-disposed`. The picker does not dispose an externally created controller.

## False positives

### Field-owned controller disposed in State.dispose

```dart
class _PageState extends State<Page> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

Do not report.

### Timer canceled in dispose with callback guard

```dart
Timer? _timer;

@override
void dispose() {
  _timer?.cancel();
  _timer = null;
  super.dispose();
}

void _start() {
  _timer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (!mounted) {
      _timer?.cancel();
      return;
    }
    _tick();
  });
}
```

Do not report when both field cleanup and callback guard are present.

### Riverpod AutoDispose provider

```dart
@riverpod
class Counter extends _$Counter {
  StreamSubscription? _sub;

  @override
  int build() {
    ref.onDispose(() => _sub?.cancel());
    _sub = repo.watch().listen((_) => state++);
    return 0;
  }
}
```

Do not report when `ref.onDispose` covers the subscription.

### Business resource owned by page Logic

```dart
class PageLogic {
  Timer? _timer;

  void onDispose() {
    _timer?.cancel();
    _timer = null;
  }
}
```

Do not report when the widget/state file does not duplicate that responsibility and the Logic cleanup path is reachable on page teardown.
