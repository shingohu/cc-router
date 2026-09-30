# ccrouter_test

Test support and regression coverage for CCRouter. The package is intended to
provide stable test hosts, fakes, and assertions without exposing Core Runtime
internals through the business facade.

Use it only from test or dev dependencies. Production components must not use
test Runtime overlays or lifecycle controls.

The external test-support surface is still being frozen before publication.
See the
[workspace README](https://github.com/shingohu/cc-router/blob/main/README.md)
and
[release checklist](https://github.com/shingohu/cc-router/blob/main/docs/CCRouter-release-readiness.md).
