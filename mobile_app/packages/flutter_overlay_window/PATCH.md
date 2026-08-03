# Vendored copy — local patch

This is a vendored copy of `flutter_overlay_window` 0.5.0 (from pub.dev),
referenced via a `path:` dependency in the app's `pubspec.yaml` instead of
the published version, because of one bug that has no workaround from the
Dart side alone.

## The bug

`FlutterOverlayWindowPlugin.onAttachedToEngine()` unconditionally sets the
static field `WindowSetup.messenger` to the engine it's attaching to:

```java
WindowSetup.messenger = messenger;
```

This plugin attaches to **two** engines: the main app's engine, and the
overlay's own separately-created engine (`OverlayService.onCreate()`'s
`FlutterEngineGroup`). Since `WindowSetup.messenger` is static, whichever
engine attaches *last* wins — and that's always the overlay engine, since it
doesn't exist until the app is already running and the user opens the
overlay.

`OverlayService` relays every message the overlay sends via `shareData()` by
calling `WindowSetup.messenger.send(message)`, intending to deliver it to the
main app. With the static field clobbered, this instead delivers the message
right back to the overlay's own `overlayListener` — a same-process,
milliseconds-fast self-echo — and the main app's `overlayListener` never
receives anything the overlay sends. There's also no way to detect this from
the Dart side except that the main app's listener callback simply never
fires.

## The fix

`FlutterOverlayWindowPlugin.java` now only assigns `WindowSetup.messenger`
once, guarded by `WindowSetup.mainMessengerSet` — the first engine to attach
(always the main app's, since the overlay engine can't exist yet) wins, and
the overlay engine's own attachment no longer overwrites it.

## Upstream

This hasn't been reported/fixed upstream as of this writing. If a newer
published version fixes it, prefer switching back to the pub.dev dependency
and deleting this vendored copy.
