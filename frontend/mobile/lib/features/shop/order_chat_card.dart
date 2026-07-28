import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';

/// کارتِ سفارشِ فروشگاه درونِ گفتگو.
///
/// پیام فقط `ref` را حمل می‌کند، نه وضعیت را؛ وضعیتِ سفارش پس از ارسالِ پیام
/// بارها عوض می‌شود، پس اگر در خودِ پیام ذخیره می‌شد همان لحظه کهنه می‌شد.
/// این ویجت وضعیت را زنده می‌خواند و دکمه‌ها را از پرچم‌های `can*`ِ سرور
/// می‌گیرد تا ماشینِ وضعیت دوباره در کلاینت پیاده نشود.
class OrderChatCard extends StatefulWidget {
  const OrderChatCard({super.key, required this.orderRef});

  final String orderRef;

  @override
  State<OrderChatCard> createState() => _OrderChatCardState();
}

class _OrderChatCardState extends State<OrderChatCard> {
  ShopOrder? _order;
  bool _busy = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final o = await ApiScope.of(context).shopOrder(widget.orderRef);
      if (mounted) setState(() => _order = o);
    } catch (_) {
      // سفارشِ ناخوانا کارت را خالی نگه می‌دارد؛ گفتگو نباید بشکند.
    }
  }

  String _toman(int rial) => tr('{0} تومان', [(rial / 10).round()]);

  Future<void> _act(String kind) async {
    final o = _order;
    if (o == null) return;
    setState(() => _busy = true);
    try {
      final api = ApiScope.of(context);
      final updated = switch (kind) {
        'accept' => await api.acceptOrder(o.id),
        'ship' => await api.shipOrder(o.id),
        'complete' => await api.completeOrder(o.id),
        _ => await api.cancelOrder(o.id),
      };
      if (mounted) setState(() => _order = updated);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.detail.isNotEmpty ? e.detail : tr('ناموفق'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('ناموفق'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    if (o == null) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text('${tr('سفارشِ فروشگاه')} · ${widget.orderRef}',
            style: const TextStyle(fontSize: 12)),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final semantic = DilixSemanticColors.from(context);
    final done = o.status == 'completed';
    final dead = o.status == 'cancelled';
    // نوارِ بالا متنِ سفید دارد، پس رنگش باید *تیره و پُر* باشد. پیش از این
    // `Colors.green`/`Colors.deepOrange` با شفافیتِ ۸۵٪ استفاده می‌شد و سفید
    // رویشان به‌سختی خوانده می‌شد؛ این سه تن هر کدام ≥۵:۱ کنتراست با سفید دارند.
    final head = dead
        ? scheme.onSurfaceVariant
        : done
            ? semantic.success
            : semantic.warning;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(minWidth: 220),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: head,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined,
                        size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        o.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_toman(o.total)} × ${o.qty}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            // پیش از این «سیاهِ ۲۵٪» بود: روی حبابِ روشنِ گفتگو خاکستریِ گِل‌آلود
            // می‌ساخت و روی حبابِ تیره تقریباً نامرئی می‌شد.
            color: scheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(o.statusLabel,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurface)),
                    ),
                    if (o.escrowLocked)
                      Text(tr('وجه بلوکه'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: semantic.warning)),
                  ],
                ),
                if (o.hasAction) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (o.canAccept)
                        FilledButton(
                          onPressed: _busy ? null : () => _act('accept'),
                          child: Text(tr('پذیرش')),
                        ),
                      if (o.canShip)
                        FilledButton(
                          onPressed: _busy ? null : () => _act('ship'),
                          child: Text(tr('ارسال شد')),
                        ),
                      if (o.canComplete)
                        FilledButton(
                          onPressed: _busy ? null : () => _act('complete'),
                          child: Text(tr('تأییدِ دریافت')),
                        ),
                      if (o.canCancel)
                        OutlinedButton(
                          onPressed: _busy ? null : () => _act('cancel'),
                          child: Text(tr('لغو')),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
