import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app.dart';
import '../../models/models.dart';
import 'holdings_screen.dart' show formatMinor, minorScale;

import '../../core/l10n.dart';
/// شارژِ کیف‌پول از درگاهِ پرداخت.
///
/// سه مرحله دارد: فرم (انتخابِ درگاه/مبلغ) → پرداخت → تأیید. مرحلهٔ پرداخت دو
/// شکلِ کاملاً متفاوت دارد:
///  * درگاهِ معمولی: `payment_url` داخلِ WebView باز می‌شود و بازگشتِ درگاه به
///    `/api/v1/paygate/callback` گرفته می‌شود تا `authority` استخراج شود.
///  * درگاهِ کریپتو: هیچ ریدایرکتی وجود ندارد؛ آدرسِ واریز نمایش داده می‌شود و
///    کاربر پس از واریز دکمهٔ «پرداخت کردم» را می‌زند.
///
/// در هر دو حالت پایانِ کار `topupVerify` است که idempotent است، پس تکرارِ آن
/// خطرِ واریزِ دوباره ندارد.
class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key, this.creditTo});

  /// ارزِ جیبِ مقصد. اگر null باشد سرور ارزِ پایهٔ کیف‌پول را واریز می‌کند.
  final String? creditTo;

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

enum _Stage { form, web, crypto, verifying, done }

class _TopupScreenState extends State<TopupScreen> {
  /// حداقلِ مبلغ در واحدِ خرد — بایدِ سرور (`MIN_AMOUNT`).
  static const _minMinor = 1000;

  final _amountCtrl = TextEditingController();

  List<PayGateway> _gateways = const [];
  PayGateway? _gateway;
  String _currency = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  _Stage _stage = _Stage.form;
  TopupIntent? _intent;
  WebViewController? _web;
  String _resultText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGateways());
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGateways() async {
    try {
      final list = await ApiScope.of(context).paymentGateways();
      if (!mounted) return;
      setState(() {
        _gateways = list;
        _gateway = list.isEmpty ? null : list.first;
        _currency = _currenciesOf(_gateway).first;
        _loading = false;
        _error = list.isEmpty ? tr('درگاهِ فعالی برای شارژ ثبت نشده است.') : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr('بارگذاریِ درگاه‌ها ممکن نشد: {0}', [e]);
      });
    }
  }

  /// درگاهی که فهرستِ ارزش خالی است یعنی «همهٔ ارزها»؛ در آن حالت ارزِ مقصد (یا
  /// ریال) را پیشنهاد می‌دهیم تا فرم بدونِ انتخاب هم قابلِ ارسال باشد.
  List<String> _currenciesOf(PayGateway? gw) {
    final list = gw?.supportedCurrencies ?? const <String>[];
    if (list.isNotEmpty) return list;
    return [widget.creditTo?.toUpperCase() ?? 'IRR'];
  }

  int get _scale => minorScale(_currency);

  int? get _amountMinor {
    final raw = _amountCtrl.text.trim().replaceAll(tr('،'), '').replaceAll(',', '');
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return null;
    // ⚠ IRR در کیف‌پول «ریال» است ولی کاربر تومان وارد می‌کند.
    final factor = _currency == 'IRR' ? 10 : _scale;
    return (v * factor).round();
  }

  Future<void> _initiate() async {
    final gw = _gateway;
    final minor = _amountMinor;
    if (gw == null) return;
    if (minor == null) {
      setState(() => _error = tr('مبلغ را وارد کنید.'));
      return;
    }
    if (minor < _minMinor) {
      setState(() => _error =
          tr('مبلغ کمتر از حدِ مجاز است (حداقل {0}).', [formatMinor(_minMinor, _currency, _scale)]));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final intent = await ApiScope.of(context).topupInitiate(
        gatewayCode: gw.code,
        amount: minor,
        currency: _currency,
        creditTo: widget.creditTo,
      );
      if (!mounted) return;
      if (intent.crypto) {
        setState(() {
          _intent = intent;
          _busy = false;
          _stage = _Stage.crypto;
        });
        return;
      }
      final url = intent.paymentUrl;
      if (url == null || url.isEmpty) {
        setState(() {
          _busy = false;
          _error = tr('درگاه آدرسِ پرداخت برنگرداند.');
        });
        return;
      }
      setState(() {
        _intent = intent;
        _busy = false;
        _stage = _Stage.web;
        _web = _buildWebView(url);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  WebViewController _buildWebView(String url) {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri != null && uri.path.contains('/paygate/callback')) {
              _onCallback(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (err) {
            if ((err.isForMainFrame ?? true) && mounted) {
              setState(() => _error = tr('خطا در بارگذاریِ درگاه: {0}', [err.description]));
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  /// بازگشت از درگاه. `status` غیرِ success یعنی کاربر انصراف داده یا پرداخت رد
  /// شده؛ در آن حالت verify نمی‌فرستیم تا خطای بی‌مورد نگیریم.
  void _onCallback(Uri uri) {
    final status = uri.queryParameters['status'] ?? 'success';
    final authority = uri.queryParameters['authority'] ?? '';
    if (status.toLowerCase() != 'success' && status.toLowerCase() != 'ok') {
      setState(() {
        _stage = _Stage.form;
        _web = null;
        _error = tr('پرداخت انجام نشد یا لغو شد.');
      });
      return;
    }
    _verify(authority: authority);
  }

  Future<void> _verify({String authority = ''}) async {
    final intent = _intent;
    if (intent == null) return;
    setState(() {
      _stage = _Stage.verifying;
      _web = null;
      _error = null;
    });
    try {
      final (status, credited) = await ApiScope.of(context).topupVerify(
        intentId: intent.intentId,
        authority: authority.isNotEmpty ? authority : intent.authority,
      );
      if (!mounted) return;
      if (status == 'paid') {
        setState(() {
          _stage = _Stage.done;
          _resultText =
              tr('{0} به کیفِ شما افزوده شد.', [formatMinor(credited, intent.creditCurrency, minorScale(intent.creditCurrency))]);
        });
      } else {
        setState(() {
          _stage = _Stage.crypto;
          _error = tr('پرداخت هنوز تأیید نشده است (وضعیت: {0}).', [status]);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = intent.crypto ? _Stage.crypto : _Stage.form;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage != _Stage.web,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stage == _Stage.web) {
          setState(() {
            _stage = _Stage.form;
            _web = null;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(tr('شارژِ کیف‌پول'))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.form:
        return _form();
      case _Stage.web:
        final c = _web;
        return c == null
            ? const Center(child: CircularProgressIndicator())
            : WebViewWidget(controller: c);
      case _Stage.crypto:
        return _cryptoView();
      case _Stage.verifying:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(tr('در حالِ تأییدِ پرداخت…')),
            ],
          ),
        );
      case _Stage.done:
        return _doneView();
    }
  }

  Widget _form() {
    final currencies = _currenciesOf(_gateway);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) _errorBox(_error!),
        if (_gateways.isEmpty)
          const SizedBox.shrink()
        else ...[
          Text(tr('درگاهِ پرداخت'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final gw in _gateways)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                selected: _gateway?.code == gw.code,
                onTap: () => setState(() {
                  _gateway = gw;
                  _currency = _currenciesOf(gw).first;
                }),
                title: Text(gw.name),
                subtitle: Text(
                  [
                    if (gw.supportedCurrencies.isNotEmpty)
                      gw.supportedCurrencies.join(tr('، ')),
                    if (gw.isSandbox) tr('آزمایشی'),
                  ].join(' • '),
                ),
                leading: gw.logoUrl != null && gw.logoUrl!.isNotEmpty
                    ? Image.network(gw.logoUrl!,
                        width: 32,
                        height: 32,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.account_balance))
                    : const Icon(Icons.account_balance),
                trailing: Icon(
                  _gateway?.code == gw.code
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (currencies.length > 1)
            DropdownButtonFormField<String>(
              initialValue: currencies.contains(_currency) ? _currency : currencies.first,
              decoration: InputDecoration(labelText: tr('ارزِ پرداخت')),
              items: [
                for (final c in currencies)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _currency == 'IRR' ? tr('مبلغ (تومان)') : tr('مبلغ ({0})', [_currency]),
              helperText:
                  tr('حداقل {0}', [formatMinor(_minMinor, _currency, _scale)]),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final q in _quickAmounts())
                ActionChip(
                  label: Text(formatMinor(q, _currency, _scale)),
                  onPressed: () {
                    final factor = _currency == 'IRR' ? 10 : _scale;
                    _amountCtrl.text = (q / factor)
                        .toStringAsFixed(factor == 1 ? 0 : 2)
                        .replaceFirst(RegExp(r'\.00$'), '');
                    setState(() {});
                  },
                ),
            ],
          ),
          if (widget.creditTo != null) ...[
            const SizedBox(height: 12),
            Text(tr('واریز به جیبِ {0}', [widget.creditTo]),
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy || _gateway == null ? null : _initiate,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.payment),
            label: Text(tr('ادامه و پرداخت')),
          ),
        ],
      ],
    );
  }

  List<int> _quickAmounts() {
    if (_currency == 'IRR') {
      // واحدِ ذخیره ریال است؛ ۱۰۰/۲۰۰/۵۰۰ هزار تومان
      return const [1000000, 2000000, 5000000];
    }
    final s = _scale;
    return [10 * s, 50 * s, 100 * s];
  }

  Widget _cryptoView() {
    final i = _intent!;
    final address = i.address ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) _errorBox(_error!),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('مبلغِ {0} را به آدرسِ زیر بفرستید.', [formatMinor(i.amount, i.currency, minorScale(i.currency))]),
                    style: Theme.of(context).textTheme.titleSmall),
                if (i.network != null && i.network!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(tr('شبکه: {0}', [i.network]),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                SelectableText(address,
                    style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: address.isEmpty
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(ClipboardData(text: address));
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text(tr('آدرس کپی شد.'))),
                          );
                        },
                  icon: const Icon(Icons.copy),
                  label: Text(tr('کپیِ آدرس')),
                ),
                const SizedBox(height: 12),
                Text(
                  tr('ارسال به شبکهٔ اشتباه باعثِ از دست رفتنِ دارایی می‌شود. پس از واریز، دکمهٔ زیر را بزنید.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _verify(),
          icon: const Icon(Icons.check),
          label: Text(tr('واریز کردم، بررسی کن')),
        ),
      ],
    );
  }

  Widget _doneView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 12),
            Text(_resultText, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('بازگشت به کیف‌پول')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer)),
      );
}
