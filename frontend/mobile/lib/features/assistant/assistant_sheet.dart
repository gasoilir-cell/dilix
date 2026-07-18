import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';

/// دستیارِ هوشمندِ سراسری (سند ۸). مکالمهٔ پایدار در Core ساخته می‌شود و به
/// dilix-ai-service (LangGraph) وصل می‌شود. کاربر می‌تواند agent متخصص را انتخاب کند.
class AssistantSheet extends StatefulWidget {
  const AssistantSheet({super.key});

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

/// agentهای در دسترس — مطابقِ pattern بک‌اند (ai/schemas.py: ConversationCreate).
const Map<String, String> _agents = {
  'personal': 'دستیارِ شخصی',
  'freight': 'باربری',
  'insurance': 'بیمه',
  'financial': 'مالی',
  'matchmaking': 'همتاسازی',
  'travel': 'سفر',
  'business': 'کسب‌وکار',
};

class _AssistantSheetState extends State<AssistantSheet> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  String _agentType = 'personal';
  AiConversation? _conversation;
  final List<AiMessage> _messages = [];
  bool _busy = false;
  bool _starting = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ensureConversation() async {
    if (_conversation != null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final conv =
          await ApiScope.of(context).createAiConversation(agentType: _agentType);
      if (!mounted) return;
      setState(() => _conversation = conv);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'ساختِ مکالمه با دستیار ناموفق بود.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _busy || _starting) return;
    await _ensureConversation();
    final conv = _conversation;
    if (conv == null) return; // خطای ساختِ مکالمه در _error نمایش داده می‌شود.

    _ctrl.clear();
    setState(() {
      _messages.add(AiMessage(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        conversationId: conv.id,
        role: 'user',
        content: text,
        sentAt: DateTime.now(),
      ));
      _busy = true;
      _error = null;
    });
    _scrollToEnd();
    try {
      final reply = await ApiScope.of(context).aiChat(conv.id, text);
      if (!mounted) return;
      setState(() => _messages.add(reply));
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'اتصال به دستیار برقرار نشد؛ دوباره تلاش کن.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onAgentChanged(String? value) {
    if (value == null || value == _agentType) return;
    // تغییرِ agent → مکالمهٔ تازه (مکالمهٔ فعلی به agent قبلی گره خورده).
    setState(() {
      _agentType = value;
      _conversation = null;
      _messages.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('دستیار هوشمند Dilix'),
              subtitle: Text(_agents[_agentType] ?? _agentType),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('تخصص:'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _agentType,
                      onChanged: _busy ? null : _onAgentChanged,
                      items: [
                        for (final e in _agents.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _body(scheme)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(hintText: 'پیامت را بنویس…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_busy || _starting) ? null : _send,
                    child: (_busy || _starting)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('ارسال'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'سوالت را بپرس؛ بر اساسِ تخصصِ انتخاب‌شده به متخصصِ مناسب هدایت می‌شوی.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final isUser = m.role == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            decoration: BoxDecoration(
              color: isUser ? scheme.surfaceContainerHighest : scheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              m.content,
              style: TextStyle(
                color: isUser ? scheme.onSurface : scheme.onPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}
