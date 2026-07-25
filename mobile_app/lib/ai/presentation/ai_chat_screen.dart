import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ai_assistant_service.dart';
import '../../user/application/wealth_state.dart';
import '../../investment/application/portfolio_state.dart';
import '../../academy/application/academy_state.dart';
import '../../shared/app_theme_colors.dart';

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

    setState(() => _isLoading = false);

    if (result['confirmation_needed'] == true) {
      // Show confirmation dialog
      final confirmed = await _showConfirmationDialog(
        result['message'] ?? 'Are you sure?',
      );
      if (confirmed) {
        final response = await service.executeTool(
          result['action'] ?? 'chat',
          result['parameters'] ?? {},
        );
        setState(() {
          _messages.add({'role': 'assistant', 'content': response});
        });
      } else {
        setState(() {
          _messages.add({'role': 'assistant', 'content': 'Action cancelled.'});
        });
      }
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
                    child: Text(
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
                    onSubmitted: (_) => _sendMessage(),
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