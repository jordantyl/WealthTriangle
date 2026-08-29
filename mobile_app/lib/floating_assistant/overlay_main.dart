import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

import '../firebase_options.dart';
import '../ai/ai_assistant_service.dart';
import '../ai/ai_chat_history_service.dart';
import '../user/application/wealth_state.dart';
import '../investment/application/portfolio_state.dart';
import '../academy/application/academy_state.dart';

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
  // lib/.env isn't bundled as an asset (see CODE-01) — BACKEND_BASE_URL/
  // BACKEND_API_KEY come from --dart-define instead (see backend_headers.dart).
  // This just needs dotenv initialized so any dotenv.env[...] read elsewhere
  // in AcademyState/etc. doesn't throw "not initialized" instead of
  // returning null, matching main.dart's and admin_main.dart's fallback.
  try {
    await dotenv.load(fileName: "lib/.env");
  } catch (_) {
    dotenv.loadFromString(isOptional: true);
  }
  // FirebaseAuth's persisted sign-in state is restored asynchronously —
  // currentUser stays null until the first authStateChanges() event fires,
  // even though this engine ends up sharing the main app's signed-in
  // session (same default FirebaseApp, same underlying native persistence).
  // Without waiting here, a Speak/Photo request fired right after the
  // bubble opens can race ahead of that restore: authedBackendHeaders()
  // reads currentUser before it's populated, sends no auth token, and the
  // backend rejects it as unauthorized even though the user really is
  // signed in. Capped at 5s so a genuinely signed-out user isn't stuck
  // waiting forever for an event that will never fire.
  await FirebaseAuth.instance.authStateChanges().first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
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
// request goes out. composeText is a single editable box used for BOTH
// reviewing/correcting a voice transcript and typing a message directly —
// same UI, two entry points (Speak populates it, Type opens it empty).
// confirmPhoto lets the user check a captured/picked photo (with an
// optional caption) before it's sent. confirmAction shows a mutating tool
// call (e.g. record_holding) for explicit approval before it actually runs
// — mirrors the in-app AI Assistant's confirmation dialog, just inline
// since the overlay panel doesn't have room for a separate dialog stack.
// idle and loading both show the running chat transcript (see
// _buildTranscript()) — there's no separate "result" mode; every exchange
// lands in the persisted _messages thread instead of only showing the
// latest reply. error covers both "didn't catch that" (no speech heard)
// and any other input failure, always leaving Speak/Photo/Type tappable
// again rather than getting stuck.
enum _Mode {
  idle,
  listening,
  choosePhotoSource,
  composeText,
  confirmPhoto,
  confirmAction,
  loading,
  error,
}

class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});

  @override
  State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  // These self-initialize against FirebaseAuth/Firestore directly (same as
  // when the main app builds them via Provider) — no BuildContext or
  // Provider tree needed, which the overlay's separate engine doesn't have
  // anyway. Instantiated once and kept for the overlay's lifetime so the
  // AI assistant here can actually read/write the user's real portfolio and
  // profile, the same as the in-app assistant does.
  late final WealthState _wealthState;
  late final PortfolioState _portfolioState;
  late final AcademyState _academyState;
  late final AIAssistantService _aiService;

  final _speech = SpeechToText();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();

  // The bubble keeps one continuous, persisted conversation (unlike the
  // in-app AI Assistant's multiple switchable chats — the 300x400 overlay
  // panel doesn't have room for a chat picker) stored under a fixed id in
  // the same Firestore collection, so "Quick Ask" history survives
  // collapsing/reopening the bubble across app restarts.
  static const String _chatId = 'quick_ask';
  final AIChatHistoryService _historyService = AIChatHistoryService();
  final List<Map<String, String>> _messages = [];
  final ScrollController _scrollController = ScrollController();

  bool _expanded = false;
  _Mode _mode = _Mode.idle;
  String _resultText = '';
  String? _pendingImageBase64;
  StreamSubscription? _sub;
  Timer? _photoTimeout;

  // Set while _mode == confirmAction — the mutating tool call awaiting
  // explicit user approval before executeTool() actually runs it.
  String? _pendingAction;
  Map<String, dynamic>? _pendingActionParams;
  String? _pendingActionDescription;

  @override
  void initState() {
    super.initState();
    _portfolioState = PortfolioState();
    _wealthState = WealthState(_portfolioState);
    _academyState = AcademyState();
    _aiService = AIAssistantService(
      wealthState: _wealthState,
      portfolioState: _portfolioState,
      academyState: _academyState,
    );
    _sub = FlutterOverlayWindow.overlayListener.listen(_onMainAppMessage);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final messages = await _historyService.loadMessages(_chatId);
    if (!mounted || messages.isEmpty) return;
    setState(() => _messages.addAll(messages));
    _scrollToBottom();
  }

  Future<void> _saveHistory() => _historyService.saveMessages(_chatId, _messages);

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _clearHistory() async {
    setState(() => _messages.clear());
    await _historyService.deleteChat(_chatId);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _photoTimeout?.cancel();
    _speech.stop();
    _textController.dispose();
    _captionController.dispose();
    _scrollController.dispose();
    _wealthState.dispose();
    _portfolioState.dispose();
    _academyState.dispose();
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
        _captionController.clear();
        _mode = _Mode.confirmPhoto;
      });
    }
  }

  Future<void> _expand() async {
    setState(() => _expanded = true);
    // Drag starts OFF once expanded — otherwise every touch on the message
    // area (including trying to scroll long replies) gets read as a window
    // drag instead, since the native overlay's touch listener claims
    // ACTION_MOVE before Flutter's own scroll gesture gets a chance to win.
    // Dragging is re-enabled only while the header is actively pressed, see
    // the GestureDetector around the header row in build().
    await FlutterOverlayWindow.resizeOverlay(panelWidth, panelHeight, false);
  }

  void _setDragEnabled(bool enabled) {
    FlutterOverlayWindow.resizeOverlay(panelWidth, panelHeight, enabled);
  }

  Future<void> _collapse() async {
    await _speech.stop();
    _photoTimeout?.cancel();
    setState(() {
      _expanded = false;
      _mode = _Mode.idle;
      _resultText = '';
      _pendingAction = null;
      _pendingActionParams = null;
      _pendingActionDescription = null;
    });
    await FlutterOverlayWindow.resizeOverlay(bubbleSize, bubbleSize, true);
    // Reset back to the default centerRight anchor on every collapse — the
    // native plugin never clamps drag position to the screen, so an
    // enthusiastic drag while expanded (a much bigger panel than the
    // collapsed bubble) can otherwise leave it stranded off-screen with no
    // way to grab it again. Collapsing is the natural "something's wrong,
    // let me close it" move, so it doubles as recovery.
    await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
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
        _resultText = "Didn't catch that. Tap Speak to try again, or use Type instead.";
      });
      return;
    }
    // Speech-to-text can mishear things (e.g. "HP" vs "RHB") — landing in
    // the same editable box as manual typing lets the user fix it before
    // anything is sent, rather than only being able to accept or fully redo it.
    setState(() {
      _textController.text = trimmed;
      _mode = _Mode.composeText;
    });
  }

  void _startTyping() {
    setState(() {
      _textController.clear();
      _mode = _Mode.composeText;
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
    if (text.trim().isEmpty) return;
    final historyBeforeThisTurn = List<Map<String, String>>.from(_messages);
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _mode = _Mode.loading;
    });
    _scrollToBottom();
    _saveHistory();
    final result = await _aiService.processQuery(text, history: historyBeforeThisTurn);
    await _handleAssistantResult(result);
  }

  Future<void> _sendImage(String base64Image) async {
    final caption = _captionController.text;
    final historyBeforeThisTurn = List<Map<String, String>>.from(_messages);
    setState(() {
      _messages.add({'role': 'user', 'content': caption.isEmpty ? '📷 [Photo]' : '📷 [Photo] $caption'});
      _mode = _Mode.loading;
    });
    _scrollToBottom();
    _saveHistory();
    final result = await _aiService.processImageQuery(
      base64Decode(base64Image),
      userCaption: caption,
      history: historyBeforeThisTurn,
    );
    await _handleAssistantResult(result);
  }

  void _appendAssistantMessage(String content) {
    _messages.add({'role': 'assistant', 'content': content});
    _mode = _Mode.idle;
  }

  // Shared by text and image sends — same tool-calling contract either way
  // (see AIAssistantService), so the same action/confirmation/execution
  // handling applies regardless of which input method produced the query.
  Future<void> _handleAssistantResult(Map<String, dynamic> result) async {
    if (!mounted) return;
    final action = (result['action'] ?? 'chat').toString();
    final rawParams = Map<String, dynamic>.from(result['parameters'] ?? {});

    // Mutating actions always require explicit confirmation, regardless of
    // what the model itself claims via confirmation_needed — that field is
    // model-controlled and a bad/hallucinated response could set it false
    // for a real write. mutatingAiActions is the enforced source of truth
    // (same rule the in-app AI Assistant screen follows).
    if (mutatingAiActions.contains(action)) {
      final prepared = await _aiService.prepareAction(action, rawParams);
      if (!mounted) return;
      if (prepared['error'] != null) {
        setState(() => _appendAssistantMessage(prepared['error'].toString()));
        _scrollToBottom();
        _saveHistory();
        return;
      }
      setState(() {
        _mode = _Mode.confirmAction;
        _pendingAction = action;
        _pendingActionParams = prepared;
        _pendingActionDescription = _aiService.describeAction(action, prepared);
      });
      return;
    }

    if (action != 'chat') {
      // A real tool call that doesn't need confirmation (get_stock_data,
      // run_backtest, etc.) — still has to actually run to fetch real data,
      // rather than just showing the model's own guessed message text.
      final response = await _aiService.executeTool(action, rawParams);
      if (!mounted) return;
      setState(() => _appendAssistantMessage(response));
      _scrollToBottom();
      _saveHistory();
      return;
    }

    setState(() => _appendAssistantMessage((result['message'] ?? "I understand. How can I help?").toString()));
    _scrollToBottom();
    _saveHistory();
  }

  Future<void> _confirmPendingAction() async {
    final action = _pendingAction;
    final params = _pendingActionParams;
    if (action == null || params == null) return;
    setState(() => _mode = _Mode.loading);
    final response = await _aiService.executeTool(action, params);
    if (!mounted) return;
    setState(() {
      _appendAssistantMessage(response);
      _pendingAction = null;
      _pendingActionParams = null;
      _pendingActionDescription = null;
    });
    _scrollToBottom();
    _saveHistory();
  }

  void _cancelPendingAction() {
    setState(() {
      _appendAssistantMessage('Action cancelled.');
      _pendingAction = null;
      _pendingActionParams = null;
      _pendingActionDescription = null;
    });
    _scrollToBottom();
    _saveHistory();
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
              Expanded(
                // Drag handle: pressing anywhere in this area re-enables
                // window dragging for the duration of the press, so the
                // panel can still be repositioned without swallowing scroll
                // gestures over the reply text below.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (_) => _setDragEnabled(true),
                  onPanEnd: (_) => _setDragEnabled(false),
                  onPanCancel: () => _setDragEnabled(false),
                  child: const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.deepPurpleAccent, size: 18),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text('Quick Ask', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      Icon(Icons.drag_indicator, color: Colors.white38, size: 16),
                    ],
                  ),
                ),
              ),
              if (_messages.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70, size: 20),
                  tooltip: 'Clear chat',
                  onPressed: _clearHistory,
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: _collapse,
              ),
            ],
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: _mode == _Mode.composeText
                ? _buildComposeText()
                : (_mode == _Mode.idle || _mode == _Mode.loading)
                    ? _buildTranscript()
                    : SingleChildScrollView(child: _buildBody()),
          ),
          const SizedBox(height: 8),
          _buildActionRow(),
        ],
      ),
    );
  }

  // The running "Quick Ask" thread — shown whenever there's nothing more
  // pressing to show (an active mic/photo/confirm flow takes over instead,
  // via _buildBody()). A trailing spinner row appears while a
  // request is in flight, same pattern as the in-app AI Assistant screen.
  Widget _buildTranscript() {
    if (_messages.isEmpty && _mode != _Mode.loading) {
      return const Center(
        child: Text(
          'Ask by voice, photo, or text — or ask me to do something, like "add 100 shares of RHB".',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      itemCount: _messages.length + (_mode == _Mode.loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _messages.length && _mode == _Mode.loading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final msg = _messages[i];
        final isUser = msg['role'] == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: panelWidth - 60),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isUser ? Colors.deepPurple : Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              msg['content'] ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case _Mode.idle:
        return const SizedBox.shrink(); // handled by _buildTranscript() instead, see build()
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
      case _Mode.composeText:
        return const SizedBox.shrink(); // handled by _buildComposeText() instead, see build()
      case _Mode.confirmPhoto:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send this photo?', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            if (_pendingImageBase64 != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(base64Decode(_pendingImageBase64!), height: 120, fit: BoxFit.cover),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _captionController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Add a note (optional) — e.g. "record this trade"',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.deepPurpleAccent)),
              ),
            ),
          ],
        );
      case _Mode.confirmAction:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.amber, size: 16),
                SizedBox(width: 6),
                Text('Confirm action', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Text(_pendingActionDescription ?? '', style: const TextStyle(color: Colors.white)),
          ],
        );
      case _Mode.loading:
        return const SizedBox.shrink(); // handled by _buildTranscript() instead, see build()
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

  // A dedicated (non-scrolling) layout for composeText — an Expanded
  // TextField needs to be a direct flex child, not nested inside the
  // SingleChildScrollView the other modes share, or it has no bounded
  // height to expand into.
  Widget _buildComposeText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ask or tell me to do something:', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Expanded(
          child: TextField(
            controller: _textController,
            autofocus: true,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'e.g. "add 100 shares of RHB at 7.90"',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
        ),
      ],
    );
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
    if (_mode == _Mode.composeText) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionButton(
            icon: Icons.close,
            label: 'Cancel',
            onTap: () => setState(() => _mode = _Mode.idle),
          ),
          _actionButton(
            icon: Icons.send,
            label: 'Send',
            onTap: () => _sendText(_textController.text),
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
    if (_mode == _Mode.confirmAction) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionButton(icon: Icons.close, label: 'Cancel', onTap: _cancelPendingAction),
          _actionButton(icon: Icons.check, label: 'Confirm', onTap: _confirmPendingAction),
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
        _actionButton(
          icon: Icons.keyboard,
          label: 'Type',
          onTap: busy ? null : _startTyping,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
