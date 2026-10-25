# Changelog

## 0.1.0 - Unreleased

- Add the explicit `ccrouter_ui_test.dart` entry with `CCUIFragmentTestHost` for
  real generated Assembly/Renderer tests, owned unmount/shutdown, failure cleanup
  and sequential default Host isolation.
- Add independent idempotent UI test Host disposal for registered teardown after
  a body timeout; share cleanup outcomes across error Zones and fake schedulers
  without repeating unmount or shutting down a replacement Host.
- Release completed unmount callbacks from suspended UI test runs, even while
  an external body Future remains pending; cover both pending/completed body GC.

- Preparing the first public release of CCRouter integration test support.
