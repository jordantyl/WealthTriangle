import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

import '../firebase_options.dart';
import 'floating_assistant_service.dart';

const int bubbleSize = 60;
const int panelWidth = 300;
const int panelHeight = 400;

/// Runs the floating overlay bubble's widget tree in its own Flutter
/// engine. flutter_overlay_window hosts this in its own Service/
/// WindowManager window rather than an Activity, so it needs its own
/// Firebase/dotenv init — it doesn't share the main isolate's state, only
/// the same app's persisted Firebase Auth session and bundled assets.
///
/// The actual `@pragma('vm:entry-point')` entry point the plugin calls by
/// name lives in main.dart, not here — the native plugin's
/// `DartEntrypoint("overlayMain")` lookup resolves the name only within
/// main.dart's own library, so a same-named function in this file is never
/// found (silently fails with "Could not resolve main entrypoint
/// function", leaving the overlay window blank). main.dart's entry point
/// just forwards to this function.
Future<void> runOverlayIsolate() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await dotenv.load(fileName: "lib/.env");
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: OverlayBubble(),
      ),
    );
  }
}

// choosePhotoSource is the Camera-vs-Gallery picker shown before a photo
// request goes out. confirmText/confirmPhoto let the user check what was
// captured/picked before it's actually sent to the assistant; error covers
// both "didn't catch that" (no speech heard) and any other failure, always
// leaving Speak/Photo tappable again rather than getting stuck.
enum _Mode { idle, listening, choosePhotoSource, confirmText, confirmPhoto, loading, result, error }

class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});

  @override
  State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  final _service = FloatingAssistantService();
  final _speech = SpeechToText();

  bool _expanded = false;
  _Mode _mode = _Mode.idle;
  String _resultText = '';
  String _pendingText = '';
  String? _pendingImageBase64;
  StreamSubscription? _sub;
  Timer? _photoTimeout;

  @override
  void initState() {
    super.initState();
    _sub = FlutterOverlayWindow.overlayListener.listen(_onMainAppMessage);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _photoTimeout?.cancel();
    _speech.stop();
    super.dispose();
  }

  // Messages coming back from the main app in response to a 'capture_photo:*'
  // request — the overlay's own engine has no Activity to get a camera/
  // gallery result back from, so the main app services the actual pick and
  // hands the bytes back here. See FloatingAssistantBridge.
  //
  // flutter_overlay_window's message channel echoes shareData() calls back
  // to their own sender, so the command we just sent out arrives right back
  // here too — without this guard it was falling through to
  // base64Decode('capture_photo:...'), which crashes (not valid base64).
  void _onMainAppMessage(dynamic event) {
    if (event == 'capture_photo:camera' || event == 'capture_photo:gallery') return;
    _photoTimeout?.cancel();
    if (event == 'capture_cancelled') {
      setState(() => _mode = _Mode.idle);
      return;
    }
    if (event is String && event.isNotEmpty) {
      setState(() {
        _pendingImageBase64 = event;
        _mode = _Mode.confirmPhoto;
      });
    }
  }

  Future<void> _expand() async {
    setState(() => _expanded = true);
    await FlutterOverlayWindow.resizeOverlay(panelWidth, panelHeight, true);
  }

  Future<void> _collapse() async {
    await _speech.stop();
    _photoTimeout?.cancel();
    setState(() {
      _expanded = false;
      _mode = _Mode.idle;
      _resultText = '';
    });
    await FlutterOverlayWindow.resizeOverlay(bubbleSize, bubbleSize, true);
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: _onSpeechError,
    );
    if (!available) {
      setState(() {
        _mode = _Mode.error;
        _resultText = "Voice input isn't available. Check microphone permission in Settings.";
      });
      return;
    }
    setState(() => _mode = _Mode.listening);
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _finishListening(result.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  // Fires on every status change, including when listening stops on its own
  // (timeout/silence) without ever producing a result — that case never
  // reaches onResult at all, so without this the panel would just sit on
  // "Listening..." forever with no way to tell the user nothing was heard.
  void _onSpeechStatus(String status) {
    if (status == SpeechToText.doneStatus && _mode == _Mode.listening) {
      _finishListening('');
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted || _mode != _Mode.listening) return;
    setState(() {
      _mode = _Mode.error;
      _resultText = "Couldn't hear you — check the microphone and try again.";
    });
  }

  void _finishListening(String text) {
    if (!mounted || _mode != _Mode.listening) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _mode = _Mode.error;
        _resultText = "Didn't catch that. Tap Speak to try again.";
      });
      return;
    }
    setState(() {
      _mode = _Mode.confirmText;
      _pendingText = trimmed;
    });
  }

  Future<void> _requestPhoto(bool fromGallery) async {
    setState(() => _mode = _Mode.loading);
    // Fire-and-forget: the native side of this plugin's message channel
    // never sends a reply back for overlay->main messages, so awaiting
    // shareData() here would hang forever and the timeout below would never
    // even get scheduled.
    unawaited(FlutterOverlayWindow.shareData(fromGallery ? 'capture_photo:gallery' : 'capture_photo:camera'));
    _photoTimeout?.cancel();
    // The main app's process has to be alive to service this (see
    // FloatingAssistantBridge) — if it's been killed, no reply ever comes.
    _photoTimeout = Timer(const Duration(seconds: 30), () {
      if (mounted && _mode == _Mode.loading) {
        setState(() {
          _mode = _Mode.error;
          _resultText = "Photo didn't come through. Make sure WealthTriangle is open, then try again.";
        });
      }
    });
  }

  Future<void> _sendText(String text) async {
    setState(() => _mode = _Mode.loading);
    final response = await _service.askText(text);
    if (!mounted) return;
    setState(() {
      _mode = _Mode.result;
      _resultText = response;
    });
  }

  Future<void> _sendImage(String base64Image) async {
    setState(() => _mode = _Mode.loading);
    final response = await _service.askImage(base64Decode(base64Image));
    if (!mounted) return;
    setState(() {
      _mode = _Mode.result;
      _resultText = response;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return GestureDetector(
        onTap: _expand,
        child: Container(
          width: bubbleSize.toDouble(),
          height: bubbleSize.toDouble(),
          decoration: const BoxDecoration(
            color: Colors.deepPurple,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
      );
    }

    return Container(
      width: panelWidth.toDouble(),
      height: panelHeight.toDouble(),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurpleAccent, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.deepPurpleAccent, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Quick Ask', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: _collapse,
              ),
            ],
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: SingleChildScrollView(
              child: _buildBody(),
            ),
          ),
          const SizedBox(height: 8),
          _buildActionRow(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case _Mode.idle:
        return const Text(
          'Ask by voice or snap a photo for a quick answer.',
          style: TextStyle(color: Colors.white70),
        );
      case _Mode.listening:
        return const Text('Listening... speak now.', style: TextStyle(color: Colors.white70));
      case _Mode.choosePhotoSource:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add a photo from:', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            _sourceOption(Icons.camera_alt, 'Camera', () => _requestPhoto(false)),
            const SizedBox(height: 6),
            _sourceOption(Icons.photo_library, 'Gallery', () => _requestPhoto(true)),
          ],
        );
      case _Mode.confirmText:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send this question?', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            Text('"$_pendingText"',
                style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic)),
          ],
        );
      case _Mode.confirmPhoto:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send this photo?', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            if (_pendingImageBase64 != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(base64Decode(_pendingImageBase64!), height: 140, fit: BoxFit.cover),
              ),
          ],
        );
      case _Mode.loading:
        return const Center(child: CircularProgressIndicator());
      case _Mode.result:
        return Text(_resultText, style: const TextStyle(color: Colors.white));
      case _Mode.error:
        return Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.amber, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(_resultText, style: const TextStyle(color: Colors.white70))),
          ],
        );
    }
  }

  Widget _buildActionRow() {
    if (_mode == _Mode.choosePhotoSource) {
      return Center(
        child: _actionButton(
          icon: Icons.close,
          label: 'Cancel',
          onTap: () => setState(() => _mode = _Mode.idle),
        ),
      );
    }
    if (_mode == _Mode.confirmText) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionButton(
            icon: Icons.refresh,
            label: 'Retry',
            onTap: () => setState(() => _mode = _Mode.idle),
          ),
          _actionButton(
            icon: Icons.send,
            label: 'Send',
            onTap: () => _sendText(_pendingText),
          ),
        ],
      );
    }
    if (_mode == _Mode.confirmPhoto) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionButton(
            icon: Icons.refresh,
            label: 'Retake',
            onTap: () => setState(() => _mode = _Mode.idle),
          ),
          _actionButton(
            icon: Icons.send,
            label: 'Send',
            onTap: () => _sendImage(_pendingImageBase64!),
          ),
        ],
      );
    }

    final busy = _mode == _Mode.listening || _mode == _Mode.loading;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _actionButton(
          icon: _mode == _Mode.listening ? Icons.mic : Icons.mic_none,
          label: _mode == _Mode.listening ? 'Listening...' : 'Speak',
          onTap: busy ? null : _startListening,
          active: _mode == _Mode.listening,
        ),
        _actionButton(
          icon: Icons.camera_alt,
          label: 'Photo',
          onTap: busy ? null : () => setState(() => _mode = _Mode.choosePhotoSource),
        ),
      ],
    );
  }

  Widget _sourceOption(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.deepPurpleAccent, size: 20),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: active ? Colors.redAccent : Colors.deepPurpleAccent),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
