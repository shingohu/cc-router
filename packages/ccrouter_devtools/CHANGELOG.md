# Changelog

## 0.1.0 - Unreleased

- Display read-only Runtime navigation health for Entries, captured Host
  lifetimes, concurrency gates, Backend desync and observer queue depth.
  Preserve unavailable state for older producers and exclude business payloads.

- Show history completeness and Sink delivery health; export safe Failure,
  Fallback, Pending and InitTask records to the tooling protocol. Refresh on
  non-navigation work, Sink completion and Runtime replacement using subscribed
  lightweight checks; stop observation on TickerMode disable or disposal.

- Preparing the first public release of the read-only Flutter diagnostics UI.
