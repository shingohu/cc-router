# Changelog

## 0.1.0 - Unreleased

- Add optional `diagnosticHealth.runtimeHealth` to protocol v1 without requiring
  older producers to supply it. Encode captured Host lifetimes as
  `trackedNavigationHosts`, accepting the former `registeredHosts` input key.

- Extend protocol v1 with optional fixed-field diagnostic records and health;
  absent producer support stays null, malformed present data fails explicitly.

- Preparing the first public release of the versioned DevTools protocol.
