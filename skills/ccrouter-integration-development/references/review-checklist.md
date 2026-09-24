# Review Checklist

## Architecture

- Is the package correctly acting as Host, implementation, or contracts package?
- Does every cross-component dependency point to a contract instead of a page implementation?
- Is a new public contract justified by an actual external consumer?
- Are unsupported framework capabilities avoided rather than locally reimplemented?

## Navigation

- Does every managed navigation call use `CCRouter.navigator`?
- Does every statically known destination use a generated typed Intent?
- Are dynamic internal URIs and external untrusted URIs using different entry points?
- Is `BuildContext` passed only for explicit Outlet resolution?
- Are `push`, `replace`, `go`, and `reset` used according to their real stack semantics?
- Is the Pop result type correct and tested?
- Are local overlays intentionally foreign rather than accidentally registered as routes?

## Policies

- Is Interceptor limited to pre-navigation policy?
- Does it avoid nested navigation, UI work, and analytics side effects?
- Is async policy bounded by timeout/cancellation?
- Is PopGuard synchronous and in-memory?
- Is confirmation UI implemented with `PopScope` instead?
- Is Aspect observational, sanitized, and non-reentrant?

## Lifecycle

- Does Service use the narrowest valid Scope?
- Are disposable resources released by the owning Scope?
- Is Session opened/closed only by authentication lifecycle?
- Does Route Service resolve from an exact managed page Context?
- Are PageShow/PageHide not mistaken for Widget lifetime or physical visibility?
- Are listener removers, streams, controllers, and Overlay entries cleaned up?

## Messaging and Initialization

- Does Command have exactly one owner and the correct result type?
- Is Event used only for an already completed fact whose subscribers are optional?
- Does handler code cooperate with cancellation before irreversible side effects where possible?
- Is InitTask truly once-per-Runtime startup work?
- Are DAG dependency, Gate, timeout, and failure policy explicit?

## Generated Code and Tests

- Were generated files left untouched?
- Was generation run after annotation or component graph changes?
- Does `generate --check` pass?
- Does analyze pass without internal API warnings?
- Do tests cover failure, cancellation, typed result, and lifecycle cleanup as applicable?
- Does the change avoid retaining Context, Route, Scope, listener, subscription, or Service past its owner?

## Documentation Synchronization

If the change alters a developer-observable public API, lifecycle, error, generated path/command, supported capability, API isolation boundary, or recommended Demo pattern, review and update:

- root `README.md`;
- `skills/ccrouter-integration-development/SKILL.md`;
- the relevant file in `skills/ccrouter-integration-development/references/`.

Do not churn these files for internal refactors with no observable integration change.
