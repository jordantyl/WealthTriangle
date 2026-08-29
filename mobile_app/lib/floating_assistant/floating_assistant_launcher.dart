import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

import 'overlay_main.dart';

/// Starts/stops the floating assistant bubble from the main app (e.g. a
/// Settings toggle). Permissions are requested here, in the main app, and
/// never from inside the overlay itself — asking for camera/mic/overlay
/// permission from a window that isn't a normal Activity is unreliable and
/// can silently misfire on some Android versions.
class FloatingAssistantLauncher {
  static Future<bool> isRunning() => FlutterOverlayWindow.isActive();

  /// Requests every permission the bubble will need, then starts it.
  /// Returns false (without starting) if the user declines any of them.
  static Future<bool> requestPermissionsAndStart() async {
    final overlayGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (!overlayGranted) {
      final granted = await FlutterOverlayWindow.requestPermission();
      if (granted != true) return false;
    }

    final micStatus = await Permission.microphone.request();
    final cameraStatus = await Permission.camera.request();
    if (!micStatus.isGranted || !cameraStatus.isGranted) return false;

    await FlutterOverlayWindow.showOverlay(
      height: bubbleSize,
      width: bubbleSize,
      alignment: OverlayAlignment.centerRight,
      // defaultFlag makes the overlay window never accept key input focus
      // at all — the bubble's TextField could never bring up the soft
      // keyboard. focusPointer is what the package docs recommend for any
      // overlay that has a field needing a keyboard.
      flag: OverlayFlag.focusPointer,
      visibility: NotificationVisibility.visibilitySecret,
      enableDrag: true,
      overlayTitle: 'WealthTriangle Assistant',
      overlayContent: 'Tap to ask a quick question',
    );
    return true;
  }

  static Future<void> stop() => FlutterOverlayWindow.closeOverlay();
}
