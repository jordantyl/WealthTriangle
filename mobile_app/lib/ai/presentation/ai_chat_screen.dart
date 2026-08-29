import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../ai_assistant_service.dart';
import '../ai_chat_history_service.dart';
import '../../user/application/wealth_state.dart';
import '../../investment/application/portfolio_state.dart';
import '../../academy/application/academy_state.dart';
import '../../shared/app_theme_colors.dart';
import '../../shared/simple_markdown_text.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final AIChatHistoryService _historyService = AIChatHistoryService();
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  bool _isRestoring = true;

  // Null until either an existing chat is opened or the first message of a
  // new one is sent — kept unset for a brand-new chat so opening the screen
  // and backing out again doesn't litter Firestore with empty chat docs.
  String? _activeChatId;
  List<ChatSummary> _chatSummaries = [];

  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _speech.stop();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    await _refreshChatList();
    if (!mounted) return;
    if (_chatSummaries.isNotEmpty) {
      await _openChat(_chatSummaries.first.id);
    } else {
      setState(() => _isRestoring = false);
    }
  }

  Future<void> _refreshChatList() async {
    final chats = await _historyService.listChats();
    if (mounted) setState(() => _chatSummaries = chats);
  }

  Future<void> _openChat(String chatId) async {
    // Only pop if the drawer is actually open — Navigator.canPop(context)
    // is also true just because this screen can pop back to Home, which
    // made this fire on the auto-restore-last-chat path (no drawer open)
    // and pop the whole AI screen back to Home instead of a drawer.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
    setState(() => _isRestoring = true);
    final messages = await _historyService.loadMessages(chatId);
    if (!mounted) return;
    setState(() {
      _activeChatId = chatId;
      _messages
        ..clear()
        ..addAll(messages);
      _isRestoring = false;
    });
  }

  void _startNewChat() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
    setState(() {
      _activeChatId = null;
      _messages.clear();
    });
  }

  Future<void> _confirmDeleteChat(String chatId) async {
    final colors = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Delete this chat?', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'This can\'t be undone.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: TextStyle(color: colors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _historyService.deleteChat(chatId);
    if (_activeChatId == chatId) {
      setState(() {
        _activeChatId = null;
        _messages.clear();
      });
    }
    await _refreshChatList();
  }

  Future<void> _saveHistory({String? titleHint}) async {
    _activeChatId ??= await _historyService.createChat();
    if (_activeChatId == null) return;
    await _historyService.saveMessages(_activeChatId!, _messages, titleHint: titleHint);
    _refreshChatList(); // keep the drawer's ordering/title fresh
  }

  AIAssistantService _buildService() {
    return AIAssistantService(
      wealthState: Provider.of<WealthState>(context, listen: false),
      portfolioState: Provider.of<PortfolioState>(context, listen: false),
      academyState: Provider.of<AcademyState>(context, listen: false),
    );
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;
    final userMsg = _controller.text;
    final historyBeforeThisTurn = List<Map<String, String>>.from(_messages);
    setState(() {
      _messages.add({'role': 'user', 'content': userMsg});
      _controller.clear();
      _isLoading = true;
    });
    _saveHistory(titleHint: userMsg);

    final service = _buildService();
    final result = await service.processQuery(userMsg, history: historyBeforeThisTurn);
    await _handleAssistantResult(service, result);
  }

  // Camera input — same tool-calling contract as typed text (see
  // AIAssistantService.processImageQuery), so a photo can trigger a real
  // action too (e.g. a trade confirmation screenshot), not just get
  // described. Whatever's currently typed in the compose box (if anything)
  // goes along as a caption.
  Future<void> _pickAndSendImage(ImageSource source) async {
    final picker = ImagePicker();
    XFile? photo;
    try {
      photo = await picker.pickImage(source: source, maxWidth: 1024, imageQuality: 60);
    } catch (e) {
      debugPrint('Image pick failed: $e');
    }
    if (photo == null || !mounted) return;

    final caption = _controller.text;
    final historyBeforeThisTurn = List<Map<String, String>>.from(_messages);
    final userLine = caption.isEmpty ? '📷 [Photo]' : '📷 [Photo] $caption';
    setState(() {
      _messages.add({'role': 'user', 'content': userLine});
      _controller.clear();
      _isLoading = true;
    });
    _saveHistory(titleHint: caption.isEmpty ? 'Photo' : caption);

    final bytes = await photo.readAsBytes();
    final service = _buildService();
    final result = await service.processImageQuery(
      bytes,
      userCaption: caption,
      history: historyBeforeThisTurn,
    );
    await _handleAssistantResult(service, result);
  }

  // Voice input — speech_to_text transcribes into the same compose box
  // typing uses, so a mis-heard word (e.g. "HP" instead of "RHB") can be
  // fixed before anything is sent, rather than only being able to accept
  // the transcript as-is.
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == SpeechToText.doneStatus && mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (SpeechRecognitionError error) {
        if (!mounted) return;
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't hear you — check the microphone and try again.")),
        );
      },
    );
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Voice input isn't available. Check microphone permission in Settings.")),
      );
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        _controller.text = result.recognizedWords;
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  void _showPhotoSourceSheet() {
    final colors = context.appColors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Shared by text and image sends — same action/confirmation/execution
  // handling regardless of which input method produced the query.
  Future<void> _handleAssistantResult(
    AIAssistantService service,
    Map<String, dynamic> result,
  ) async {
    final action = result['action'] ?? 'chat';
    final rawParams = Map<String, dynamic>.from(result['parameters'] ?? {});

    if (mounted) setState(() => _isLoading = false);

    // Mutating actions always require confirmation, regardless of what the
    // model itself claims via confirmation_needed — that field is
    // model-controlled and a bad/hallucinated response could set it false
    // for a real write. mutatingAiActions is the enforced source of truth.
    if (mutatingAiActions.contains(action)) {
      final prepared = await service.prepareAction(action, rawParams);
      if (!mounted) return;
      if (prepared['error'] != null) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': prepared['error']});
        });
        _saveHistory();
        return;
      }

      final confirmed = await _showConfirmationDialog(
        service.describeAction(action, prepared),
      );
      if (!mounted) return;
      if (confirmed) {
        final response = await service.executeTool(action, prepared);
        if (!mounted) return;
        setState(() {
          _messages.add({'role': 'assistant', 'content': response});
        });
      } else {
        setState(() {
          _messages.add({'role': 'assistant', 'content': 'Action cancelled.'});
        });
      }
      _saveHistory();
    } else if (action != 'chat') {
      // A real tool call that doesn't need confirmation (get_stock_data,
      // run_backtest, get_user_triangle_health, get_portfolio_summary) —
      // must still actually run executeTool() to fetch real data. Previously
      // this branch only showed Gemini's own guessed `message` text and
      // never called executeTool() at all, so every non-confirmation tool
      // silently degraded into the AI making up an answer instead of
      // fetching anything real.
      final response = await service.executeTool(action, rawParams);
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'assistant', 'content': response});
      });
      _saveHistory();
    } else {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': result['message'] ?? 'I understand. How can I help?',
        });
      });
      _saveHistory();
    }
  }

  Future<bool> _showConfirmationDialog(String message) async {
    final colors = context.appColors;
    return await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.amber, width: 2)),
        title: Text('🔐 Confirm Action', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          message,
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: TextStyle(color: colors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('CONFIRM', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.background,
      drawer: _buildChatDrawer(colors),
      appBar: AppBar(
        title: const Text('🤖 AI Assistant'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            // Disabled while a reply is in flight — switching chats mid-
            // request used to let the reply land in (and get persisted to)
            // whatever chat was open when it arrived, not the one that
            // asked for it.
            onPressed: _isLoading ? null : _startNewChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isRestoring
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Ask about stocks, backtesting, your portfolio — or tell me to do something,\nlike "add 100 shares of RHB at 7.90".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textTertiary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == _messages.length && _isLoading) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final msg = _messages[i];
                          final isUser = msg['role'] == 'user';
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isUser ? Colors.blueAccent : colors.surfaceAlt,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: SimpleMarkdownText(
                                msg['content']!,
                                style: TextStyle(color: isUser ? Colors.white : colors.textPrimary),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: colors.textPrimary),
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? 'Listening...'
                          : 'Ask, or tell me to do something...',
                      hintStyle: TextStyle(color: colors.textTertiary),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _toggleListening,
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? Colors.redAccent : Colors.blueAccent,
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _showPhotoSourceSheet,
                  icon: const Icon(Icons.camera_alt, color: Colors.blueAccent),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The "left panel" chat picker — a Drawer (swipe from the left edge, or
  // tap the app bar's leading menu icon) is the mobile-appropriate
  // equivalent of a desktop chat app's fixed sidebar; a permanently docked
  // side panel doesn't fit a phone-width screen.
  Widget _buildChatDrawer(AppColors colors) {
    return Drawer(
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _startNewChat,
                icon: const Icon(Icons.add),
                label: const Text('New chat'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _chatSummaries.isEmpty
                  ? Center(
                      child: Text('No past chats yet', style: TextStyle(color: colors.textTertiary)),
                    )
                  : ListView.builder(
                      itemCount: _chatSummaries.length,
                      itemBuilder: (ctx, i) {
                        final chat = _chatSummaries[i];
                        final isActive = chat.id == _activeChatId;
                        return ListTile(
                          // Disabled while a reply is in flight — see the
                          // "New chat" button above for why: switching (or
                          // deleting) the active chat mid-request let the
                          // in-flight reply land in whatever chat was open
                          // when it arrived instead of the one that asked.
                          enabled: !_isLoading,
                          selected: isActive,
                          selectedTileColor: Colors.deepPurple.withOpacity(0.12),
                          leading: Icon(Icons.chat_bubble_outline, color: isActive ? Colors.deepPurple : colors.textTertiary),
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.textPrimary),
                          ),
                          subtitle: chat.updatedAt != null
                              ? Text(DateFormat('MMM d, HH:mm').format(chat.updatedAt!),
                                  style: TextStyle(color: colors.textTertiary, fontSize: 11))
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            color: colors.textTertiary,
                            onPressed: _isLoading ? null : () => _confirmDeleteChat(chat.id),
                          ),
                          onTap: _isLoading ? null : () => _openChat(chat.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
