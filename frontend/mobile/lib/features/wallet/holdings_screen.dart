import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../models/models.dart';
import 'topup_screen.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
/// قالب‌بندیِ مبلغِ خرد (minor) به نمایشِ انسانی.
///
/// ⚠ سرور همه‌چیز را در واحدِ خرد می‌دهد و [scale] برای هر ارز فرق می‌کند
/// (IRR=1، USD=100، BTC=1e8). تقسیمِ ثابت بر ۱۰۰ ارزِ دیجیتال را خراب می‌کند.
String formatMinor(int amount, String currency, int scale) {
  final cur = currency.toUpperCase();
  if (cur == 'IRR') return tr('{0} تومان', [_group((amount / 10).round())]);
  final major = scale <= 0 ? amount.toDouble() : amount / scale;
  final digits = scale >= 1000000 ? 8 : (scale > 1 ? 2 : 0);
  final text = major
      .toStringAsFixed(digits)
      .replaceFirst(RegExp(r'(\.\d*?)0+$'), r'$1')
      .replaceFirst(RegExp(r'\.$'), '');
  return '$text $cur';
}

/// ارزهای بدونِ زیرواحد (۰ اعشار) — بایدِ `ZERO_DECIMAL` در سرویسِ FXِ سرور.
const _zeroDecimal = {'IRR', 'JPY', 'KRW', 'VND', 'CLP', 'ISK'};

/// ارزهای دیجیتال و اعشارشان — بایدِ `CRYPTO_DECIMALS` در سرور.
const _cryptoDecimals = {'BTC': 8, 'ETH': 8, 'TON': 6, 'TRX': 6};

/// مقیاسِ واحدِ خردِ یک ارز وقتی جیبِ متناظری نداریم (مثلاً در شارژِ درگاه).
/// اگر جیب در دست است، همیشه `pocket.scale` معتبرتر است.
int minorScale(String currency) {
  final c = currency.toUpperCase();
  if (_zeroDecimal.contains(c)) return 1;
  final d = _cryptoDecimals[c];
  if (d != null) {
    var s = 1;
    for (var i = 0; i < d; i++) {
      s *= 10;
    }
    return s;
  }
  return 100;
}

String _group(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(tr('،'));
    buf.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$buf';
}

/// کیفِ چندارزی: جیب‌های ارزی/کریپتو، تبدیلِ ارز، انتقال، دریافت و برداشت.
/// معادلِ بخشِ holdings در وب.
class HoldingsScreen extends StatefulWidget {
  const HoldingsScreen({super.key});

  @override
  State<HoldingsScreen> createState() => _HoldingsScreenState();
}

class _HoldingsScreenState extends State<HoldingsScreen> {
  HoldingsSnapshot? _snapshot;
  List<HoldingTx> _transactions = const [];
  bool _loading = true;
  String? _error;
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _snapshot == null) _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final api = ApiScope.of(context);
    try {
      final snapshot = await api.holdings();
      var txs = const <HoldingTx>[];
      try {
        txs = await api.holdingTransactions(limit: 25);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _transactions = txs;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('بارگذاریِ جیب‌ها ممکن نشد: {0}', [e]);
        _loading = false;
      });
    }
  }

  Future<void> _openSheet(Widget sheet, {String? successNote}) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => sheet,
    );
    if (ok == true && mounted) {
      setState(() => _notice = successNote);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('جیب‌های ارزی')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: tr('تازه‌سازی'),
          ),
        ],
      ),
      body: _loading && snap == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (_notice != null)
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_notice!),
                      ),
                    ),
                  if (snap != null) ...[
                    _totalCard(snap),
                    const SizedBox(height: 12),
                    _actions(snap),
                    const SizedBox(height: 12),
                    _pocketsCard(snap),
                  ],
                  if (_transactions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _txCard(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _totalCard(HoldingsSnapshot s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('ارزشِ کل'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              formatMinor(s.totalBase, s.baseCurrency, 1),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(tr('≈ {0} دلار', [s.totalUsd.toStringAsFixed(2)]),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _actions(HoldingsSnapshot s) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _openSheet(
            _ExchangeSheet(snapshot: s),
            successNote: tr('تبدیلِ ارز انجام شد.'),
          ),
          icon: const Icon(Icons.swap_horiz),
          label: Text(tr('تبدیل')),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _openSheet(
            _SendSheet(snapshot: s),
            successNote: tr('انتقال انجام شد.'),
          ),
          icon: const Icon(Icons.north_east),
          label: Text(tr('ارسال')),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _openSheet(_ReceiveSheet(snapshot: s)),
          icon: const Icon(Icons.south_west),
          label: Text(tr('دریافت')),
        ),
        OutlinedButton.icon(
          onPressed: () => _openSheet(
            _WithdrawSheet(snapshot: s),
            successNote: tr('درخواستِ برداشت ثبت شد و در صفِ تسویه است.'),
          ),
          icon: const Icon(Icons.output),
          label: Text(tr('برداشت')),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final done = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const TopupScreen()),
            );
            if (done == true && mounted) {
              setState(() => _notice = tr('شارژ با موفقیت انجام شد.'));
              await _load();
            }
          },
          icon: const Icon(Icons.add_card),
          label: Text(tr('شارژ')),
        ),
      ],
    );
  }

  Widget _pocketsCard(HoldingsSnapshot s) {
    return Card(
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(tr('جیب‌ها'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final p in s.pockets)
            ListTile(
              leading: CircleAvatar(
                child: Text(
                  p.currency.length >= 3
                      ? p.currency.substring(0, 3)
                      : p.currency,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              title: Text(p.currency),
              subtitle: p.isPrimary ? Text(tr('جیبِ اصلی')) : null,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMinor(p.balance, p.currency, p.scale),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (p.usdValue != null)
                    Text('≈ ${p.usdValue!.toStringAsFixed(2)}\$',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _txCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            dense: true,
            title:
                Text(tr('تراکنش‌ها'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final t in _transactions)
            ListTile(
              dense: true,
              leading: Icon(
                t.isCredit ? Icons.south_west : Icons.north_east,
                color: t.isCredit
                    ? DilixSemanticColors.from(context).success
                    : Theme.of(context).colorScheme.error,
              ),
              title: Text(t.description ?? _txLabel(t.type)),
              subtitle: Text([
                if (t.counterparty != null && t.counterparty!.isNotEmpty)
                  t.counterparty!,
                if (t.status != 'completed') _statusLabel(t.status),
              ].join(' · ')),
              trailing: Text(
                '${t.isCredit ? '+' : '−'}${formatMinor(t.amount, t.currency, _scaleOf(t.currency))}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: t.isCredit
                      ? DilixSemanticColors.from(context).success
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// scaleِ ارز از خودِ snapshot خوانده می‌شود؛ تراکنش آن را همراه ندارد.
  int _scaleOf(String currency) {
    for (final p in _snapshot?.pockets ?? const <Pocket>[]) {
      if (p.currency == currency.toUpperCase()) return p.scale;
    }
    return currency.toUpperCase() == 'IRR' ? 1 : 100;
  }

  static String _txLabel(String type) => switch (type) {
        'deposit' => tr('واریز'),
        'withdrawal' => tr('برداشت'),
        'transfer_in' => tr('دریافت'),
        'transfer_out' => tr('ارسال'),
        'exchange_in' => tr('تبدیل (ورودی)'),
        'exchange_out' => tr('تبدیل (خروجی)'),
        _ => type,
      };

  static String _statusLabel(String status) => switch (status) {
        'pending' => tr('در انتظار'),
        'failed' => tr('ناموفق'),
        'completed' => tr('انجام‌شده'),
        _ => status,
      };
}

// ─────────────── شیتِ تبدیلِ ارز ───────────────
class _ExchangeSheet extends StatefulWidget {
  const _ExchangeSheet({required this.snapshot});

  final HoldingsSnapshot snapshot;

  @override
  State<_ExchangeSheet> createState() => _ExchangeSheetState();
}

class _ExchangeSheetState extends State<_ExchangeSheet> {
  late String _from = widget.snapshot.pockets.first.currency;
  late String _to = _otherThan(_from);
  final _amountCtrl = TextEditingController();
  FxQuote? _quote;
  bool _busy = false;
  String? _error;

  String _otherThan(String cur) {
    for (final p in widget.snapshot.pockets) {
      if (p.currency != cur) return p.currency;
    }
    return cur == 'USD' ? 'IRR' : 'USD';
  }

  /// همهٔ ارزهای قابلِ انتخاب: جیب‌های موجود + ارزهای رایج برای مقصد.
  List<String> get _currencies {
    final set = <String>{
      ...widget.snapshot.pockets.map((p) => p.currency),
      // فقط ارزهایی که سرور نرخ دارد؛ USDT در `fx_rates` نیست و تبدیل را
      // با خطا برمی‌گرداند. ارزهای دیجیتالِ پشتیبانی‌شده: BTC/ETH/TON/TRX.
      'IRR',
      'USD',
      'EUR',
      'BTC',
      'ETH',
      'TON',
      'TRX',
    };
    return set.toList()..sort();
  }

  Pocket? _pocket(String cur) {
    for (final p in widget.snapshot.pockets) {
      if (p.currency == cur) return p;
    }
    return null;
  }

  int? _minorAmount() {
    final scale = _pocket(_from)?.scale ?? (_from == 'IRR' ? 1 : 100);
    final v = double.tryParse(_amountCtrl.text.trim());
    if (v == null || v <= 0) return null;
    return (v * scale).round();
  }

  Future<void> _refreshQuote() async {
    final amount = _minorAmount();
    if (amount == null || _from == _to) {
      setState(() => _quote = null);
      return;
    }
    try {
      final q = await ApiScope.of(context)
          .fxQuote(from: _from, to: _to, amount: amount);
      if (mounted) setState(() => _quote = q);
    } catch (_) {
      if (mounted) setState(() => _quote = null);
    }
  }

  Future<void> _submit() async {
    final amount = _minorAmount();
    if (amount == null) {
      setState(() => _error = tr('مبلغ را وارد کنید.'));
      return;
    }
    if (_from == _to) {
      setState(() => _error = tr('ارزِ مبدأ و مقصد نباید یکی باشند.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiScope.of(context)
          .exchangeHolding(from: _from, to: _to, amount: amount);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fromPocket = _pocket(_from);
    return _SheetFrame(
      title: tr('تبدیلِ ارز'),
      error: _error,
      busy: _busy,
      onSubmit: _submit,
      submitLabel: tr('تبدیل'),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _from,
                decoration: InputDecoration(labelText: tr('از')),
                items: [
                  for (final c in _currencies)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _from = v);
                  _refreshQuote();
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_back),
            ),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _to,
                decoration: InputDecoration(labelText: tr('به')),
                items: [
                  for (final c in _currencies)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _to = v);
                  _refreshQuote();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr('مبلغ ({0})', [_from]),
            helperText: fromPocket == null
                ? null
                : tr('موجودی: {0}', [formatMinor(fromPocket.balance, fromPocket.currency, fromPocket.scale)]),
          ),
          onChanged: (_) => _refreshQuote(),
        ),
        if (_quote != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr('دریافت می‌کنید')),
                  Text(
                    formatMinor(
                        _quote!.converted, _quote!.toCurrency, _quote!.toScale),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────── شیتِ ارسال (انتقالِ درون‌شبکه‌ای) ───────────────
class _SendSheet extends StatefulWidget {
  const _SendSheet({required this.snapshot});

  final HoldingsSnapshot snapshot;

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  late String _currency = widget.snapshot.pockets.first.currency;
  final _toCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  Pocket? get _pocket {
    for (final p in widget.snapshot.pockets) {
      if (p.currency == _currency) return p;
    }
    return null;
  }

  Future<void> _submit() async {
    final scale = _pocket?.scale ?? 1;
    final v = double.tryParse(_amountCtrl.text.trim());
    final to = _toCtrl.text.trim().toUpperCase();
    if (to.length < 3) {
      setState(() => _error = tr('Earth ID گیرنده را وارد کنید.'));
      return;
    }
    if (v == null || v <= 0) {
      setState(() => _error = tr('مبلغ را وارد کنید.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiScope.of(context).transferHolding(
        toEarthId: to,
        currency: _currency,
        amount: (v * scale).round(),
        description: _noteCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pocket;
    return _SheetFrame(
      title: tr('ارسال به کاربرِ نقطه'),
      error: _error,
      busy: _busy,
      onSubmit: _submit,
      submitLabel: tr('ارسال'),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _currency,
          decoration: InputDecoration(labelText: tr('ارز')),
          items: [
            for (final x in widget.snapshot.pockets)
              DropdownMenuItem(value: x.currency, child: Text(x.currency)),
          ],
          onChanged: (v) => setState(() => _currency = v ?? _currency),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _toCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: tr('Earth ID گیرنده'),
            hintText: tr('مثلاً EA1234'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr('مبلغ ({0})', [_currency]),
            helperText: p == null
                ? null
                : tr('موجودی: {0}', [formatMinor(p.balance, p.currency, p.scale)]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteCtrl,
          decoration: InputDecoration(labelText: tr('توضیح (اختیاری)')),
        ),
      ],
    );
  }
}

// ─────────────── شیتِ دریافت ───────────────
class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({required this.snapshot});

  final HoldingsSnapshot snapshot;

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  late String _currency = widget.snapshot.pockets.first.currency;
  ReceiveInfo? _info;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final info = await ApiScope.of(context).receiveInfo(_currency);
      if (mounted) setState(() => _info = info);
    } catch (_) {
      if (mounted) setState(() => _info = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return _SheetFrame(
      title: tr('دریافت'),
      busy: _busy,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _currency,
          decoration: InputDecoration(labelText: tr('ارز')),
          items: [
            for (final x in widget.snapshot.pockets)
              DropdownMenuItem(value: x.currency, child: Text(x.currency)),
          ],
          onChanged: (v) {
            setState(() => _currency = v ?? _currency);
            _load();
          },
        ),
        const SizedBox(height: 12),
        if (info != null) ...[
          _copyRow(context, tr('Earth ID شما (دریافتِ درون‌شبکه‌ای)'), info.earthId),
          if (info.isCrypto && info.address != null) ...[
            const SizedBox(height: 8),
            _copyRow(context, tr('آدرسِ واریز ({0})', [info.network ?? '']),
                info.address!),
          ],
          if (info.note != null) ...[
            const SizedBox(height: 8),
            Text(info.note!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ],
    );
  }

  Widget _copyRow(BuildContext context, String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label, style: Theme.of(context).textTheme.bodySmall),
        subtitle: SelectableText(value,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          tooltip: tr('کپی'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr('کپی شد.'))),
              );
            }
          },
        ),
      ),
    );
  }
}

// ─────────────── شیتِ برداشت ───────────────
class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.snapshot});

  final HoldingsSnapshot snapshot;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  late String _currency = widget.snapshot.pockets
      .firstWhere((p) => !p.isPrimary,
          orElse: () => widget.snapshot.pockets.first)
      .currency;
  final _addressCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  Pocket? get _pocket {
    for (final p in widget.snapshot.pockets) {
      if (p.currency == _currency) return p;
    }
    return null;
  }

  Future<void> _submit() async {
    final scale = _pocket?.scale ?? 1;
    final v = double.tryParse(_amountCtrl.text.trim());
    final address = _addressCtrl.text.trim();
    if (address.length < 6) {
      setState(() => _error = tr('آدرسِ مقصد را وارد کنید.'));
      return;
    }
    if (v == null || v <= 0) {
      setState(() => _error = tr('مبلغ را وارد کنید.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiScope.of(context).withdrawHolding(
        currency: _currency,
        amount: (v * scale).round(),
        address: address,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pocket;
    return _SheetFrame(
      title: tr('برداشت به آدرسِ بیرونی'),
      error: _error,
      busy: _busy,
      onSubmit: _submit,
      submitLabel: tr('ثبتِ برداشت'),
      children: [
        Text(
          tr('برداشتِ بیرونی فقط برای ارزِ دیجیتال ممکن است و پس از ثبت در صفِ تسویه قرار می‌گیرد.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _currency,
          decoration: InputDecoration(labelText: tr('ارز')),
          items: [
            for (final x in widget.snapshot.pockets)
              DropdownMenuItem(value: x.currency, child: Text(x.currency)),
          ],
          onChanged: (v) => setState(() => _currency = v ?? _currency),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressCtrl,
          decoration: InputDecoration(labelText: tr('آدرسِ مقصد')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr('مبلغ ({0})', [_currency]),
            helperText: p == null
                ? null
                : tr('موجودی: {0}', [formatMinor(p.balance, p.currency, p.scale)]),
          ),
        ),
      ],
    );
  }
}

/// قابِ مشترکِ شیت‌ها: عنوان، خطا، دکمهٔ ثبت و فاصله از کیبورد.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.children,
    this.error,
    this.busy = false,
    this.onSubmit,
    this.submitLabel,
  });

  final String title;
  final List<Widget> children;
  final String? error;
  final bool busy;
  final Future<void> Function()? onSubmit;
  final String? submitLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 12),
            ...children,
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (onSubmit != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : () => onSubmit!(),
                child: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(submitLabel ?? tr('ثبت')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
