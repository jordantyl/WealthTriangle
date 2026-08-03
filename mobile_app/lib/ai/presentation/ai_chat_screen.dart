import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ai_assistant_service.dart';
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
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty) return;
    final userMsg = _controller.text;
    setState(() {
      _messages.add({'role': 'user', 'content': userMsg});
      _controller.clear();
      _isLoading = true;
    });

    final wealthState = Provider.of<WealthState>(context, listen: false);
    final portfolioState = Provider.of<PortfolioState>(context, listen: false);
    final academyState = Provider.of<AcademyState>(context, listen: false);

    final service = AIAssistantService(
      wealthState: wealthState,
      portfolioState: portfolioState,
      academyState: academyState,
    );

    final result = await service.processQuery(userMsg);
    final action = result['action'] ?? 'chat';
    final rawParams = Map<String, dynamic>.from(result['parameters'] ?? {});

    setState(() => _isLoading = false);

    // Mutating actions always require confirmation, regardless of what the
    // model itself claims via confirmation_needed — that field is
    // model-controlled and a bad/hallucinated response could set it false
    // for a real write. mutatingAiActions is the enforced source of truth.
    if (mutatingAiActions.contains(action)) {
      final prepared = await service.prepareAction(action, rawParams);
      if (prepared['error'] != null) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': prepared['error']});
        });
        return;
      }

      final confirmed = await _showConfirmationDialog(
        service.describeAction(action, prepared),
      );
      if (confirmed) {
        final response = await service.executeTool(action, prepared);
        setState(() {
          _messages.add({'role': 'assistant', 'content': response});
        });
      } else {
        setState(() {
          _messages.add({'role': 'assistant', 'content': 'Action cancelled.'});
        });
      }
    } else if (action != 'chat') {
      // A real tool call that doesn't need confirmation (get_stock_data,
      // run_backtest, get_user_triangle_health, get_portfolio_summary) —
      // must still actually run executeTool() to fetch real data. Previously
      // this branch only showed Gemini's own guessed `message` text and
      // never called executeTool() at all, so every non-confirmation tool
      // silently degraded into the AI making up an answer instead of
      // fetching anything real.
      final response = await service.executeTool(action, rawParams);
      setState(() {
        _messages.add({'role': 'assistant', 'content': response});
      });
    } else {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': result['message'] ?? 'I understand. How can I help?',
        });
      });
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
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('🤖 AI Assistant'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
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
                      hintText: 'Ask about stocks, backtesting, or your portfolio...',
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
                const SizedBox(width: 8),
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
}