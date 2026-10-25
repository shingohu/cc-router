# ccrouter_test

Test support and regression coverage for CCRouter. The package is intended to
provide stable test hosts, fakes, and assertions without exposing Core Runtime
internals through the business facade.

Use it only from test or dev dependencies. Production components must not use
test Runtime overlays or lifecycle controls.

For real generated Fragment Widget tests, import
`package:ccrouter_test/ccrouter_ui_test.dart` and use `CCUIFragmentTestHost`.
Call its single-use `run(body, unmount: ...)` inside `testWidgets`, passing the
complete generated Host Assembly. Use `CCHostAssembly.extend` when appending
handwritten test components or changing the route Catalog. The helper awaits
the body, caller-provided UI unmount and owned Host shutdown, preserving the
earliest error/stack through cleanup. Existing default Hosts, overlapping runs
and Zone overlays are rejected without disposal. It does not close a replacement
Host. Ordinary `CCRouterTestHost` overlays do not switch the optional UI catalog.
Register `addTearDown(host.dispose)` before `run` to release the owned Host even
if the test body times out. Disposal does not await that body and is idempotent
across normal completion, concurrent callers and teardown. Late calls replay
the cleanup outcome in their own Zone; handle each returned Future, including
already-asserted cleanup failures in teardown. Unmount must complete and cannot
await its own disposal. A late body cannot repeat cleanup or close a replacement.
See the [UI testing guide](../../skills/ccrouter-integration-development/references/ui-fragments.md#testing-with-the-real-host)
for the complete example, fake scheduler and resource ownership rules.

The external test-support surface is still being frozen before publication.
See the
[workspace README](https://github.com/shingohu/cc-router/blob/main/README.md)
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
