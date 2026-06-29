import 'package:flutter/material.dart';

import '../../app.dart';

/// دستیارِ هوشمندِ شناورِ سراسری (سند ۸). به dilix-ai-service از طریقِ Core وصل می‌شود.
class AssistantSheet extends StatefulWidget {
  const AssistantSheet({super.key});

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

class _Turn {
  _Turn(this.role, this.text);
  final String role; // user | assistant
  final String text;
}

class _AssistantSheetState extends State<AssistantSheet> {
  final _ctrl = TextEditingController();
  final _conversationId = DateTime.now().microsecondsSinceEpoch.toString();
  final List<_Turn> _turns = [];
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _busy) return;
    _ctrl.clear();
    setState(() {
      _turns.add(_Turn('user', text));
      _busy = true;
    });
    try {
      final reply = await ApiScope.of(context).aiInvoke(_conversationId, text);
      setState(() => _turns.add(_Turn('assistant', reply)));
    } catch (_) {
      setState(() => _turns.add(_Turn('assistant', 'اتصال به دستیار برقرار نشد.')));
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('دستیار هوشمند Dilix'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _turns.isEmpty
                  ? const Center(child: Text('سوالت را بپرس؛ به متخصصِ مناسب هدایت می‌شوی.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _turns.length,
                      itemBuilder: (context, i) {
                        final t = _turns[i];
                        final isUser = t.role == 'user';
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                            decoration: BoxDecoration(
                              color: isUser ? scheme.surfaceContainerHighest : scheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              t.text,
                              style: TextStyle(color: isUser ? scheme.onSurface : scheme.onPrimary),
                            ),
                          ),
                        );
                      },
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
                      decoration: const InputDecoration(hintText: 'پیامت را بنویس…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
}
