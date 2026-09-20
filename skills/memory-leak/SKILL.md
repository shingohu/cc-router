---
name: memory-leak
description: Find high-confidence Flutter and Dart memory leaks and lifecycle cleanup bugs during code review. Use when auditing pull requests, widget code, controllers, notifiers, timers, subscriptions, overlays, RouteObserver, VideoPlayerController, image streams, leak_tracker results, or other disposable objects for not-disposed or not-GCed leaks.
---

# Memory Leak

You are a Flutter memory leak reviewer. Report only high-confidence issues that are verifiable, reproducible, and capable of causing real memory leaks or lifecycle violations. Do not give broad optimization advice or speculative suggestions.

## Review Principles

The Flutter framework has converged on two fundamental leak patterns through its staged leak cleanup work. Application code must follow the same model:

- `not-disposed`: An object is created but `dispose()` is never called, so its resources are never released.
- `not-GCed`: An object has been disposed, but it is still strongly referenced by closures, callbacks, statics, or other retained references, so it cannot be garbage-collected.

Delayed GC after disposal (`GCed-late` in `leak_tracker`) is also a `not-GCed` retaining-path problem. Treat it the same way.

Classes already recognized by the Flutter framework as requiring `dispose()` include:
`AnimationController`, `CurvedAnimation`, `TrainHoppingAnimation`, `ChangeNotifier`, `GestureRecognizer`, `OverlayEntry`, `TextPainter`, `ImageInfo`, `ImageStreamCompleterHandle`, `BoxPainter`, `ScrollDragController`, `SelectionOverlay`, `TextSelectionOverlay`, `RestorationBucket`, `Ticker`, and `DisposableBuildContext`.

When ownership is unclear, prefer verifying with `leak_tracker_flutter_testing` in widget tests rather than guessing.

## Review Scope

Ignore the following:

- Anything under `example/`
- Anything under `test/`
- Anything under `gen/`
- Formatting-only changes
- Deletion-only changes

## Review Workflow

1. Determine the diff scope and apply the ignore rules above.
2. Quick-scan changed files for high-risk patterns:
   - `addListener(`, `removeListener(`
   - `.listen(`, `StreamSubscription`
   - `Timer(`, `Timer.periodic`
   - `GestureRecognizer(`, `TapGestureRecognizer(`, `LongPressGestureRecognizer(`
   - `OverlayEntry`, `resolve(`, `ImageStream`
   - `WidgetsBindingObserver`, `RouteObserver`, `RouteAware`
   - `VideoPlayerController`, `WebViewController`, `CameraController`
   - `CurvedAnimation(`, `TrainHoppingAnimation(`
3. For each hit, trace ownership: who creates it, who disposes/cancels/removes it, and whether the cleanup path is reachable on widget/page teardown.
4. Report only issues with a complete lifecycle proof. See [references/examples.md](references/examples.md) for true-positive and false-positive patterns.

## False Positive Guardrails

Do not report when all of the following are true:

- A field-owned controller/listener/subscription/timer is created once outside rebuild paths and cleaned up in the matching `dispose()`, `onClose()`, `onDispose()`, or `ref.onDispose()` callback.
- A parent layer (Bloc, GetX controller, Riverpod provider, page Logic) clearly outlives the widget and owns disposal of business resources such as timers and subscriptions.
- Riverpod `@riverpod` with `AutoDispose` or explicit `ref.onDispose` already covers the resource.
- `TextField(controller: _controller)` still requires `_controller.dispose()` in `State.dispose()` because the widget does not dispose an externally supplied controller. This is a valid finding, not a false positive.

## Review Order

Review findings in the following order, from highest to lowest priority.

### Rule 1: Undisposed controllers or disposable objects

- Check objects such as `TextEditingController`, `ScrollController`, `FocusNode`, `AnimationController`, `FixedExtentScrollController`, `PageController`, `TabController`, `DraggableScrollableController`, `TransformationController`, and `TrainHoppingAnimation`. Verify that each one is disposed in `State.dispose()` or the owning layer's cleanup callback.
- Check platform or plugin controllers such as `VideoPlayerController`, `WebViewController`, and `CameraController` for matching `dispose()` calls.
- Flag inline controller creation such as `CupertinoPicker(scrollController: FixedExtentScrollController())`. It must be stored in a field and manually disposed, because the widget does not dispose it automatically.
- Flag manual `GestureRecognizer` creation, including `TapGestureRecognizer` and `LongPressGestureRecognizer`, especially inside `build` or `_buildXxx()` methods.
- If code manually calls `BoxDecoration.createBoxPainter()`, verify that the returned `BoxPainter` is later disposed with `boxPainter.dispose()`.

### Rule 2: Recreated `CurvedAnimation` leaks

- Flag `CurvedAnimation` instances created directly inside `build` or `_buildXxx()`.
- Require `CurvedAnimation` to be stored as a `State` field.
- Recreate it only when the `parent` changes, for example `if (_curved == null || _curved?.parent != animation)`.
- Verify `_curved?.dispose()` is called in `dispose()`.
- Apply the same rule to `TrainHoppingAnimation`.

### Rule 3: Retained `ChangeNotifier`, `ValueNotifier`, or `Animation` listeners

- When code calls `someNotifier.addListener(callback)`, verify that `someNotifier.removeListener(callback)` is called symmetrically in `dispose()`.
- Apply the same rule to `Animation.addListener`, `Animation.addStatusListener`, and `AnimationController` listener APIs.
- If a `ValueNotifier` is locally created, verify that it is eventually disposed.
- Flag anonymous listener registration such as `addListener(() { ... })` inside `build` or `_buildXxx()`, because rebuilds can accumulate listeners that cannot be removed correctly.

### Rule 4: Undisposed `TextPainter`

- Any manually created `TextPainter` must be disposed after use.
- Pay special attention to repeated creation inside `CustomPainter.paint()` or custom measurement code paths.
- Valid patterns are limited to: keep it as a field and dispose it later, or create -> layout -> use -> dispose within the same call stack.

### Rule 5: `Timer` or async lifecycle violations

- If a `Timer` or `Timer.periodic` is started after an async operation, verify that the owner is still alive before creating the timer. Use the lifecycle guard appropriate to the owner, such as `mounted`, `isClosed`, an explicit `bool _disposed`, or an equivalent check.
- Verify that the timer callback also checks the same lifecycle guard and cancels itself when the owner is gone.
- Verify that every `Timer` is canceled and nulled out in the matching cleanup method.
- Pay special attention to patterns like `await someAsyncOp()` followed by unconditional timer creation.
- Flag `CancelToken` (dio) or similar request tokens that are not canceled when the owning page or logic is destroyed.

### Rule 6: Uncanceled `StreamSubscription`

- Any `StreamSubscription` returned by `stream.listen(...)` must be stored and canceled during disposal.
- If a `StreamController` is used, verify that `close()` is also called during disposal.
- For Riverpod, verify `ref.listen` cleanups are registered through `ref.onDispose`.
- For plugin-level streams, verify that internal subscriptions are properly managed before accepting the implementation as safe.

### Rule 7: Unremoved observers, routes, or overlays

- If a class mixes in `WidgetsBindingObserver` or uses `AppLifecycleListener`, verify symmetric removal in `dispose()`.
- If a widget implements `RouteAware`, verify `routeObserver.unsubscribe(this)` in `dispose()`.
- If a page owns an `OverlayEntry`, verify that `entry.remove()` is called in `State.dispose()`, and that the field is cleared afterward.
- When a third-party overlay/snackbar package stores its own `OverlayEntry`, verify manual removal if the page can be destroyed before the overlay dismisses itself.

### Rule 8: `not-GCed` — disposed objects still retained

- Check whether `Timer`, `Future`, or `StreamSubscription` callbacks capture `this` or another stateful owner.
- Check whether callbacks registered in static maps, global event buses, or singletons are explicitly removed in `dispose()`.
- Flag any pattern that stores `BuildContext` in a field or retains it across async gaps without `mounted` checks.
- If `ChangeNotifier.addListener` uses `this.someMethod`, verify that `removeListener` receives the exact same method reference.

### Rule 9: Unreleased `ImageStream` or `ImageStreamCompleterHandle`

- If code manually calls `imageProvider.resolve(configuration)` and obtains an `ImageStream`, verify that `stream.removeListener(listener)` is called in `dispose()`.
- If code holds an `ImageStreamCompleterHandle`, verify that `handle.dispose()` is called in `dispose()`.
- Flag any pattern that calls `imageProvider.resolve(...)` directly in `build` and ignores the returned stream.

### Rule 10: Third-party disposable objects

- When a new third-party package introduces controller-like objects, verify that its `dispose`, `close`, or `cancel` semantics are complete before treating it as safe.

## Output Requirements

- Report only high-confidence issues.
- Label every issue as either `not-disposed` or `not-GCed`.
- Every issue must include:
  - `Issue`: A short phrase, no more than 15 words, describing only the problem itself.
  - `Leak Type`: `not-disposed` or `not-GCed`.
  - `Impact`: Why this is a real memory leak or lifecycle risk.
  - `Location`: File path and line number.
  - `Violated Rule`: Format as `memory-leak / Rule X ...`.
  - `Minimal Fix`: The smallest concrete change that would fix the issue.
- If no clear issue is found, output exactly:

`No high-confidence memory leak violations found in this review.`

## Output Template

Use the following structure:

```markdown
1. Issue: Timer not canceled
Leak Type: not-disposed
Impact: The timer callback retains the page logic after navigation, preventing cleanup.
Location: lib/foo/bar_logic.dart:42
Violated Rule: memory-leak / Rule 5 Timer or async lifecycle violations
Minimal Fix: Store the `Timer` in a field, cancel it in the owning layer's dispose callback, then clear the field.
```

## Additional Resources

- True-positive and false-positive examples: [references/examples.md](references/examples.md)
