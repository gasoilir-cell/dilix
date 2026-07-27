import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import 'mini_markdown.dart';

import '../../core/l10n.dart';
/// دستیارِ هوشمندِ سراسری (سند ۸). به dilix-api `/api/v1/ai/chat` وصل می‌شود؛
/// یک نخِ گفتگوی واحد (بدونِ مفهومِ conversation). کاربر می‌تواند تخصص را انتخاب
/// کند تا به‌صورتِ سرنخ به ابتدای پیام افزوده شود.
class AssistantSheet extends StatefulWidget {
  const AssistantSheet({super.key});

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

/// agentهای در دسترس — مطابقِ pattern بک‌اند (ai/schemas.py: ConversationCreate).
Map<String, String> get _agents =>
    _agentsSrc.map((k, v) => MapEntry(k, tr(v)));

/// چهار پرسشِ آمادهٔ شروع — همان‌هایی که وب زیرِ دستیار می‌گذارد. صفحهٔ خالیِ
/// چت بزرگ‌ترین مانعِ استفاده از دستیار است.
const List<String> _suggestionsSrc = [
  'قیمت باربری تهران به مشهد؟',
  'نرخ بیمه بار الکترونیک',
  'چطور بار ثبت کنم؟',
  'دیلیکس چیه؟',
];

const Map<String, String> _agentsSrc = {
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
  final List<AiMessage> _messages = [];
  bool _busy = false;
  bool _loadingHistory = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await ApiScope.of(context).aiHistory();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loadingHistory = false;
      });
      _scrollToEnd();
    } catch (_) {
      // تاریخچهٔ خالی/در دسترس‌نبودن مانعِ گفتگوی جدید نیست.
      if (mounted) setState(() => _loadingHistory = false);
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

  Future<void> _send() => _sendText(_ctrl.text.trim());

  Future<void> _sendText(String text) async {
    if (text.isEmpty || _busy) return;

    // تخصصِ انتخاب‌شده به‌صورتِ سرنخ به پیام افزوده می‌شود (dilix-api routing ندارد).
    final payload = _agentType == 'personal'
        ? text
        : tr('[تخصص: {0}] {1}', [_agents[_agentType], text]);

    _ctrl.clear();
    setState(() {
      _messages.add(AiMessage(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        conversationId: '',
        role: 'user',
        content: text,
        sentAt: DateTime.now(),
      ));
      _busy = true;
      _error = null;
    });
    _scrollToEnd();
    try {
      final reply = await ApiScope.of(context).aiChat(payload);
      if (!mounted) return;
      setState(() => _messages.add(reply));
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = tr('اتصال به دستیار برقرار نشد؛ دوباره تلاش کن.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onAgentChanged(String? value) {
    if (value == null || value == _agentType) return;
    setState(() => _agentType = value);
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
              title: Text(tr('دستیار هوشمند Dilix')),
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
                  Text(tr('تخصص:')),
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
            // وقتی گفتگو شروع شده، پیشنهادها به یک نوارِ باریکِ افقی جمع می‌شوند
            // (مثلِ وب) تا جای پیام‌ها را نگیرند.
            if (!_loadingHistory && _messages.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  children: [
                    for (final s in _suggestionsSrc)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ActionChip(
                          label: Text(tr(s), style: const TextStyle(fontSize: 12)),
                          onPressed: _busy ? null : () => _sendText(tr(s)),
                        ),
                      ),
                  ],
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
                      decoration: InputDecoration(hintText: tr('پیامت را بنویس…')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(tr('ارسال')),
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
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            tr('سوالت را بپرس؛ بر اساسِ تخصصِ انتخاب‌شده به متخصصِ مناسب هدایت می‌شوی.'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          for (final s in _suggestionsSrc)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: OutlinedButton(
                onPressed: _busy ? null : () => _sendText(tr(s)),
                child: Text(tr(s), textAlign: TextAlign.center),
              ),
            ),
        ],
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
            // پاسخِ دستیار `**…**` دارد؛ بدونِ رندرِ پررنگ، ستاره‌ها وسطِ جمله
            // دیده می‌شدند.
            child: MiniMarkdownText(
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
