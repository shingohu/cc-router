# Changelog

## 0.1.0 (unreleased)

- Add optional typed static UI composition, required dependency validation and
  Host-owned lifecycle generations. Remount explicitly after Runtime restart.
- Preserve Flutter Key/State ownership and reject late Actions after shutdown.
- Reject enhanced enums, fingerprint effective DTO field defaults, and reject
  initializer-list assignments or redirects whose semantics are not modeled.
