import 'dart:async';
import 'dart:convert';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:image_picker/image_picker.dart';

/// Services 'capture_photo:camera' / 'capture_photo:gallery' requests sent
/// from the overlay bubble.
///
/// The overlay runs in its own Flutter engine hosted by a Service/
/// WindowManager window, not an Activity — image_picker needs a live
/// Activity to get a result back from the camera/gallery intent, so it
/// can't be called directly from the overlay. The main app (which does have
/// one) picks the photo on the overlay's behalf and hands the bytes back
/// via shareData.
class FloatingAssistantBridge {
  static StreamSubscription? _sub;

  static void init() {
    _sub ??= FlutterOverlayWindow.overlayListener.listen(_onOverlayMessage);
  }

  static Future<void> _onOverlayMessage(dynamic event) async {
    ImageSource source;
    if (event == 'capture_photo:camera') {
      source = ImageSource.camera;
    } else if (event == 'capture_photo:gallery') {
      source = ImageSource.gallery;
    } else {
      return;
    }

    final picker = ImagePicker();
    try {
      // Keep the payload well under the ~1MB platform-channel/Binder
      // transaction limit that shareData rides on — a full-resolution
      // photo's base64 string can easily blow past that.
      final photo = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 60,
      );
      if (photo == null) {
        await FlutterOverlayWindow.shareData('capture_cancelled');
        return;
      }
      final bytes = await photo.readAsBytes();
      await FlutterOverlayWindow.shareData(base64Encode(bytes));
    } catch (_) {
      await FlutterOverlayWindow.shareData('capture_cancelled');
    }
  }
}
