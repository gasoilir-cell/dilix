import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../models/models.dart';

import '../../core/l10n.dart';
/// حبابِ یک پیامِ چت با پوششِ کاملِ `MessageOut` دیلیکس‌اِی‌پی‌آی:
/// متن، عکس/ویدیو/صوت/فایل، استیکر، موقعیتِ ثابت و زنده، نظرسنجی، مخاطب،
/// رویداد، هدیهٔ نقدی، پاسخ (reply)، بازارسال، سنجاق، واکنش‌ها و رسیدِ خواندن.
///
/// این ویجت خودش هیچ فراخوانیِ شبکه ندارد؛ همهٔ کنش‌ها را با callback به
/// [ChatScreen] می‌سپارد تا منطقِ API یک‌جا بماند.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onLongPress,
    required this.onVote,
    required this.onOpenRedPacket,
    required this.onSettleMoney,
    required this.onTapContact,
    required this.onTapMedia,
    required this.onTapReply,
    required this.onToggleReaction,
    this.translation,
    this.showSender = false,
  });

  final ChatMessage message;
  final VoidCallback onLongPress;
  final void Function(PollInfo poll, int optionIndex) onVote;
  final void Function(RedPacketInfo packet) onOpenRedPacket;

  /// پرداخت (`pay`) یا رد/لغوِ (`decline`) یک درخواستِ پول.
  final void Function(ChatMessage message, String action) onSettleMoney;
  final void Function(ContactInfo contact) onTapContact;
  final void Function(ChatMessage message) onTapMedia;
  final void Function(ReplyPreview reply) onTapReply;
  final void Function(String emoji) onToggleReaction;

  /// ترجمهٔ نمایش‌داده‌شده زیرِ متن (اگر کاربر ترجمه را خواسته باشد).
  final String? translation;

  /// در گروه‌ها نامِ فرستنده بالای حباب نشان داده می‌شود.
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.isMine;
    final bg = mine
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final fg = mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final muted = fg.withValues(alpha: 0.6);

    if (message.deleted) {
      return _shell(
        context,
        mine: mine,
        bg: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Text(tr('این پیام حذف شد'),
            style: TextStyle(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
      );
    }

    return _shell(
      context,
      mine: mine,
      bg: bg,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          if (showSender && !mine && message.senderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(message.senderName!,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary)),
            ),
          if (message.isForwarded) _forwardedLabel(muted),
          if (message.replyTo != null) _replyPreview(context, fg),
          ..._content(context, fg, muted),
          if (translation != null) _translationBox(fg),
          const SizedBox(height: 3),
          _footer(context, muted),
          if (message.reactions.isNotEmpty) _reactionsRow(context),
        ],
      ),
    );
  }

  Widget _shell(BuildContext context,
      {required bool mine, required Color bg, required Widget child}) {
    return Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 2 : 14),
              bottomRight: Radius.circular(mine ? 14 : 2),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _forwardedLabel(Color muted) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shortcut, size: 12, color: muted),
            const SizedBox(width: 4),
            Text(
              message.forwardedFrom == null
                  ? tr('بازارسال‌شده')
                  : tr('بازارسال از {0}', [message.forwardedFrom]),
              style: TextStyle(
                  fontSize: 10, fontStyle: FontStyle.italic, color: muted),
            ),
          ],
        ),
      );

  Widget _replyPreview(BuildContext context, Color fg) {
    final r = message.replyTo!;
    return GestureDetector(
      onTap: () => onTapReply(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            right: BorderSide(color: fg.withValues(alpha: 0.5), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.senderName ?? tr('پاسخ'),
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
            Text(
              r.isDeleted ? tr('پیامِ حذف‌شده') : r.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, color: fg.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }

  /// بدنهٔ پیام بر اساسِ نوعِ محتوا.
  List<Widget> _content(BuildContext context, Color fg, Color muted) {
    final caption = message.content.trim();
    switch (message.mediaType) {
      case 'image':
        return [
          _imageBox(context),
          if (caption.isNotEmpty) _text(caption, fg),
        ];
      case 'video':
        return [
          _videoBox(context, fg),
          if (caption.isNotEmpty) _text(caption, fg),
        ];
      case 'voice':
        return [
          _fileTile(context, fg, icon: Icons.mic, title: tr('پیامِ صوتی')),
          if (caption.isNotEmpty) _text(caption, fg),
        ];
      case 'file':
        return [
          _fileTile(context, fg,
              icon: Icons.insert_drive_file,
              title: message.mediaName ?? tr('فایل')),
          if (caption.isNotEmpty) _text(caption, fg),
        ];
      case 'location':
      case 'live_location':
        return [
          if (message.location != null) _locationTile(fg),
          if (caption.isNotEmpty) _text(caption, fg),
        ];
      case 'poll':
        return [
          if (message.poll != null) _pollBox(context, fg),
        ];
      case 'contact':
        return [
          if (message.contact != null) _contactTile(fg),
        ];
      case 'event':
        return [
          if (message.event != null) _eventTile(fg),
          if (caption.isNotEmpty) _text(caption, fg),
        ];
      case 'red_packet':
        return [
          if (message.redPacket != null) _redPacketCard(context),
        ];
      case 'money':
      case 'money_request':
        return [
          if (message.money != null) _moneyCard(context),
        ];
      default:
        if (message.stickerId != null) return [_stickerBox()];
        return [_text(caption, fg)];
    }
  }

  Widget _text(String value, Color fg) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(value, style: TextStyle(color: fg, height: 1.35)),
      );

  Widget _imageBox(BuildContext context) {
    final url = AppConfig.absoluteMedia(message.mediaUrl);
    if (url == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => onTapMedia(message),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const SizedBox(height: 80, child: Center(child: Icon(Icons.broken_image))),
          loadingBuilder: (ctx, child, progress) => progress == null
              ? child
              : const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      ),
    );
  }

  Widget _stickerBox() {
    final url = AppConfig.absoluteMedia(message.mediaUrl);
    if (url == null) {
      return const Text('🙂', style: TextStyle(fontSize: 46));
    }
    return SizedBox(
      width: 120,
      height: 120,
      child: Image.network(url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Text('🙂', style: TextStyle(fontSize: 46))),
    );
  }

  Widget _videoBox(BuildContext context, Color fg) => GestureDetector(
        onTap: () => onTapMedia(message),
        child: Container(
          width: 200,
          height: 120,
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(Icons.play_circle_fill, size: 44, color: fg),
          ),
        ),
      );

  Widget _fileTile(BuildContext context, Color fg,
          {required IconData icon, required String title}) =>
      GestureDetector(
        onTap: () => onTapMedia(message),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
                    if (message.mediaMeta != null)
                      Text(message.mediaMeta!,
                          style: TextStyle(
                              fontSize: 10, color: fg.withValues(alpha: 0.7))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _locationTile(Color fg) {
    final loc = message.location!;
    final live = loc.live;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(live ? Icons.podcasts : Icons.place, color: fg),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  live
                      ? (loc.active ? tr('موقعیتِ زنده (فعال)') : tr('موقعیتِ زنده (پایان‌یافته)'))
                      : (loc.label ?? tr('موقعیتِ مکانی')),
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${loc.lat.toStringAsFixed(5)}, ${loc.lng.toStringAsFixed(5)}',
                  style:
                      TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pollBox(BuildContext context, Color fg) {
    final poll = message.poll!;
    return Container(
      width: 240,
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, size: 16, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(poll.question,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < poll.options.length; i++)
            _pollOption(poll, i, fg),
          const SizedBox(height: 2),
          Text(
            tr('{0} رأی{1}', [poll.totalVotes, poll.multiple ? tr(' • چندگزینه‌ای') : '']),
            style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _pollOption(PollInfo poll, int index, Color fg) {
    final opt = poll.options[index];
    final ratio = poll.totalVotes == 0 ? 0.0 : opt.votes / poll.totalVotes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => onVote(poll, index),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  opt.voted
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(opt.text,
                      style: TextStyle(fontSize: 12, color: fg)),
                ),
                Text('${opt.votes}',
                    style: TextStyle(
                        fontSize: 11, color: fg.withValues(alpha: 0.8))),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: fg.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(fg.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactTile(Color fg) {
    final c = message.contact!;
    final avatar = AppConfig.absoluteMedia(c.avatarUrl);
    return GestureDetector(
      onTap: () => onTapContact(c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null ? const Icon(Icons.person, size: 16) : null,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.name,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(c.earthId,
                    style: TextStyle(
                        fontSize: 10, color: fg.withValues(alpha: 0.7))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventTile(Color fg) {
    final e = message.event!;
    final d = e.startsAt.toLocal();
    final when = '${d.year}/${_two(d.month)}/${_two(d.day)}'
        ' • ${_two(d.hour)}:${_two(d.minute)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event, color: fg),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.title,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(when,
                    style: TextStyle(
                        fontSize: 11, color: fg.withValues(alpha: 0.8))),
                if (e.location != null && e.location!.isNotEmpty)
                  Text(e.location!,
                      style: TextStyle(
                          fontSize: 10, color: fg.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _redPacketCard(BuildContext context) {
    final p = message.redPacket!;
    final toman = (p.totalAmount / 10).round();
    return GestureDetector(
      onTap: () => onOpenRedPacket(p),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFDC2626), Color(0xFFF59E0B)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🧧', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.greeting?.isNotEmpty == true
                        ? p.greeting!
                        : tr('هدیهٔ نقدی'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(tr('{0} تومان • {1} سهم', [toman, p.count]),
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            Text(
              p.mode == 'random' ? tr('تقسیمِ شانسی') : tr('تقسیمِ مساوی'),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 10),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  _redPacketLabel(p),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(tr('{0} از {1} برداشته شد', [p.claimedCount, p.count]),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85), fontSize: 9)),
          ],
        ),
      ),
    );
  }

  /// کارتِ پولِ درون‌چت. سبز = پولی که واقعاً جابه‌جا شده، کهربایی = درخواستِ
  /// بازِ پرداخت‌نشده، خاکستری = درخواستی که رد یا لغو شده.
  Widget _moneyCard(BuildContext context) {
    final m = message.money!;
    final toman = (m.amount / 10).round();
    final gradient = m.isDead
        ? const [Color(0xFF3F3F46), Color(0xFF52525B)]
        : m.isRequest
            ? const [Color(0xFFF59E0B), Color(0xFFEA580C)]
            : const [Color(0xFF10B981), Color(0xFF0D9488)];
    return Container(
      width: 230,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(m.isRequest ? Icons.request_quote : Icons.payments,
                  color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _moneyHeadline(m),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(tr('{0} تومان', [toman]),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          if (m.note?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(m.note!,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
          ],
          const SizedBox(height: 8),
          if (m.canPay)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => onSettleMoney(message, 'pay'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0D9488),
                        visualDensity: VisualDensity.compact),
                    child: Text(tr('پرداخت')),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () => onSettleMoney(message, 'decline'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact),
                  child: Text(tr('رد')),
                ),
              ],
            )
          else if (m.canCancel)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => onSettleMoney(message, 'decline'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    visualDensity: VisualDensity.compact),
                child: Text(tr('لغوِ درخواست')),
              ),
            )
          else
            Text(_moneyStatusLabel(m),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _moneyHeadline(MoneyInfo m) {
    if (m.isRequest) {
      return m.isMine ? tr('درخواست کردی') : tr('از تو درخواست کرد');
    }
    return m.isMine ? tr('فرستادی') : tr('برایت فرستاد');
  }

  String _moneyStatusLabel(MoneyInfo m) {
    switch (m.status) {
      case 'completed':
        return tr('انجام شد');
      case 'paid':
        return tr('پرداخت شد');
      case 'declined':
        return tr('رد شد');
      case 'cancelled':
        return tr('لغو شد');
      default:
        return tr('در انتظارِ پرداخت');
    }
  }

  String _redPacketLabel(RedPacketInfo p) {
    if (p.claimed && p.myAmount != null) {
      return tr('سهمِ تو: {0} تومان', [(p.myAmount! / 10).round()]);
    }
    if (p.isMine) return tr('مشاهدهٔ جزئیات');
    if (p.status == 'refunded') return tr('بازگردانده شد');
    if (p.isExhausted || p.status == 'finished') return tr('تمام شد');
    return tr('بازکردن');
  }

  Widget _translationBox(Color fg) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.translate, size: 13, color: fg.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(translation!,
                  style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: fg.withValues(alpha: 0.9))),
            ),
          ],
        ),
      );

  Widget _footer(BuildContext context, Color muted) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isPinned) ...[
            Icon(Icons.push_pin, size: 10, color: muted),
            const SizedBox(width: 3),
          ],
          Text(_time(message.sentAt),
              style: TextStyle(fontSize: 10, color: muted)),
          if (message.edited) ...[
            const SizedBox(width: 4),
            Text(tr('ویرایش'), style: TextStyle(fontSize: 10, color: muted)),
          ],
          if (message.isMine) ...[
            const SizedBox(width: 4),
            Icon(message.isRead ? Icons.done_all : Icons.done,
                size: 12,
                color: message.isRead ? const Color(0xFF60A5FA) : muted),
          ],
        ],
      );

  Widget _reactionsRow(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 4,
        children: message.reactions.entries.map((e) {
          final isMine = message.myReaction == e.key;
          return GestureDetector(
            onTap: () => onToggleReaction(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isMine
                    ? theme.colorScheme.secondary.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${e.key} ${e.value}',
                  style: const TextStyle(fontSize: 11)),
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _time(DateTime t) {
    final l = t.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }
}
