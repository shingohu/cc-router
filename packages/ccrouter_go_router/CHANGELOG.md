# Changelog

## 0.1.0 - Unreleased

- Added default-off `enablePredictiveBack` wiring for managed Android Material
  pages and explicit handler wiring for attached/custom/Shell Pages. Flutter
  drives animation and the sole Pop; the bridge confirms exact Entry removal.
- Preserve local gates and fallback paths; invalidate previews after navigation,
  ancestor Popup coverage, Theme changes, or Adapter disposal. Surviving attached
  Routes recover Flutter handling on new gestures, including a lost old terminal.
- Added bounded sanitized `predictiveBackFallbacks` diagnostics and atomic
  rollback of failed observer/listener registration. Disabled Hosts allocate no
  fallback history.
- Preparing the first public release of the GoRouter backend integration.
