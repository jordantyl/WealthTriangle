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

## Second bug: dragging the panel teleports it instead of following the finger

`OverlayService.onTouch()` only records `lastX`/`lastY` (the touch's last
known position, used to compute the drag delta) while `WindowSetup.enableDrag`
is already `true` — the whole method was gated by
`if (windowManager != null && WindowSetup.enableDrag) { ... }`.

The app (`overlay_main.dart`'s `OverlayBubble`) only wants dragging live while
a finger is actually pressing the panel's header drag-handle, not anywhere
else on the panel (otherwise scrolling a long AI reply would drag the whole
window). So it calls `resizeOverlay(..., enableDrag: true)` on
`onPanDown`/`GestureDetector.onPanDown` for that header, and `false` again on
`onPanEnd`/`onPanCancel`. That's an async platform-channel call — by the time
it lands and `WindowSetup.enableDrag` actually flips to `true`, the physical
`ACTION_DOWN` for that same touch has already been delivered to `onTouch()`
and silently skipped (since `enableDrag` was still `false` at that instant),
so `lastX`/`lastY` never got set for this gesture. The first `ACTION_MOVE`
that *does* get processed then computes its delta against a stale value
(either 0,0 or wherever the panel was left after a previous drag) instead of
where the finger actually started — producing one huge single-frame jump
instead of a smooth drag.

Fixed by tracking `lastX`/`lastY` on every `ACTION_DOWN`/`ACTION_MOVE`
unconditionally, and only gating the actual `params.x`/`params.y` mutation
(the part that visibly moves the window) behind `WindowSetup.enableDrag`. This
way, whenever `enableDrag` does flip true mid-gesture, the next move event's
delta is computed from the real last touch point, not a stale one.

## Upstream (second bug)

Also unreported upstream as of this writing — same caveat as above applies if
switching back to a future published version.
