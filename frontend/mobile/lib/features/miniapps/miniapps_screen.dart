import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/models.dart';
import 'miniapp_host_screen.dart';

/// برنامه‌های کوچک — معادلِ صفحهٔ وبِ `app/(main)/miniapps/page.tsx`.
///
/// چهار بخش: ویترین، نصب‌شده‌ها، توسعه‌دهنده، پرداخت‌های در انتظار.
///
/// دو نکتهٔ اصلی: نصب یعنی رضایتِ صریح به فهرستِ دسترسی‌ها، و برنامه هرگز
/// نمی‌تواند خودش پول بردارد — فقط درخواستِ پرداخت می‌سازد و کاربر در همین
/// صفحه تأیید یا رد می‌کند.
class MiniAppsScreen extends StatefulWidget {
  const MiniAppsScreen({super.key});

  @override
  State<MiniAppsScreen> createState() => _MiniAppsScreenState();
}

const _categories = <String, String>{
  'tools': 'ابزار',
  'games': 'بازی',
  'shopping': 'خرید',
  'finance': 'مالی',
  'travel': 'سفر',
  'food': 'غذا',
  'education': 'آموزش',
  'health': 'سلامت',
  'social': 'اجتماعی',
  'other': 'سایر',
};

const _scopeLabels = <String, String>{
  'profile': 'نام و تصویر',
  'payment': 'درخواستِ پرداخت',
  'location': 'کشور و زبان',
};

class _MiniAppsScreenState extends State<MiniAppsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();

  String _category = 'tools';
  final Set<String> _scopes = {'profile'};

  bool _busy = false;
  bool _loaded = false;
  String? _error;
  String? _notice;

  List<MiniApp> _store = const [];
  List<MiniApp> _installed = const [];
  List<MiniApp> _mine = const [];
  List<MiniAppPayment> _payments = const [];

  // کلیدِ مخفی فقط یک‌بار از سرور می‌آید؛ تا وقتی کاربر نبسته نگهش می‌داریم.
  String? _secretAppId;
  String? _secretValue;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _loadAll();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  String _toman(int rial) => tr('{0} تومان', [(rial / 10).round()]);

  Future<void> _loadAll() async {
    await _run(() async {
      final api = ApiScope.of(context);
      final store = await api.miniApps();
      final installed = await api.installedMiniApps();
      final mine = await api.myMiniApps();
      final payments = await api.pendingMiniAppPayments();
      if (!mounted) return;
      setState(() {
        _store = store;
        _installed = installed;
        _mine = mine;
        _payments = payments;
      });
    }, tr('بارگیریِ برنامه‌ها ناموفق بود'));
  }

  Future<void> _run(Future<void> Function() body, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await body();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.detail.isNotEmpty ? e.detail : failure);
      }
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('تأیید')),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  String _scopeText(List<String> scopes) =>
      scopes.map((s) => tr(_scopeLabels[s] ?? s)).join('، ');

  Future<void> _search() async {
    await _run(() async {
      final rows =
          await ApiScope.of(context).miniApps(q: _searchCtrl.text.trim());
      if (mounted) setState(() => _store = rows);
    }, tr('جستجو ناموفق بود'));
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (name.length < 2) {
      setState(() => _error = tr('نامِ برنامه دستِ‌کم دو نویسه باشد'));
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _error = tr('نشانیِ ورود باید با http یا https شروع شود'));
      return;
    }
    if (_scopes.isEmpty) {
      setState(() => _error = tr('دستِ‌کم یک دسترسی انتخاب کنید'));
      return;
    }
    await _run(() async {
      final api = ApiScope.of(context);
      final app = await api.createMiniApp(
        name: name,
        entryUrl: url,
        tagline: _taglineCtrl.text.trim(),
        category: _category,
        scopes: _scopes.toList(),
      );
      final mine = await api.myMiniApps();
      if (!mounted) return;
      _nameCtrl.clear();
      _urlCtrl.clear();
      _taglineCtrl.clear();
      setState(() {
        _mine = mine;
        _secretAppId = app.appId;
        _secretValue = app.appSecret;
        _notice = tr('برنامه ساخته شد');
      });
    }, tr('ساختِ برنامه ناموفق بود'));
  }

  Future<void> _submit(MiniApp a) async {
    await _run(() async {
      final api = ApiScope.of(context);
      await api.submitMiniApp(a.appId);
      final mine = await api.myMiniApps();
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _notice = tr('برای بازبینی ارسال شد');
      });
    }, tr('ارسال برای بازبینی ناموفق بود'));
  }

  Future<void> _rotate(MiniApp a) async {
    final yes = await _confirm(
      tr('کلیدِ تازه'),
      tr('کلیدِ تازه ساخته شود؟ کلیدِ فعلی همان لحظه از کار می‌افتد.'),
    );
    if (!yes) return;
    await _run(() async {
      final secret = await ApiScope.of(context).rotateMiniAppSecret(a.appId);
      if (!mounted) return;
      setState(() {
        _secretAppId = a.appId;
        _secretValue = secret;
        _notice = tr('کلیدِ تازه ساخته شد');
      });
    }, tr('ساختِ کلیدِ تازه ناموفق بود'));
  }

  Future<void> _install(MiniApp a) async {
    final yes = await _confirm(
      tr('نصبِ «{0}»', [a.name]),
      tr('این برنامه به این موارد دسترسی می‌خواهد: {0}', [_scopeText(a.scopes)]),
    );
    if (!yes) return;
    await _run(() async {
      final api = ApiScope.of(context);
      await api.installMiniApp(a.appId, scopes: a.scopes);
      final store = await api.miniApps();
      final installed = await api.installedMiniApps();
      if (!mounted) return;
      setState(() {
        _store = store;
        _installed = installed;
        _notice = tr('نصب شد');
      });
    }, tr('نصبِ برنامه ناموفق بود'));
  }

  Future<void> _uninstall(MiniApp a) async {
    final yes = await _confirm(
      tr('حذفِ «{0}»', [a.name]),
      tr('برنامه حذف و دسترسی‌هایش پس گرفته شود؟'),
    );
    if (!yes) return;
    await _run(() async {
      final api = ApiScope.of(context);
      await api.uninstallMiniApp(a.appId);
      final store = await api.miniApps();
      final installed = await api.installedMiniApps();
      if (!mounted) return;
      setState(() {
        _store = store;
        _installed = installed;
        _notice = tr('حذف شد');
      });
    }, tr('حذفِ برنامه ناموفق بود'));
  }

  Future<void> _launch(MiniApp a) async {
    await _run(() async {
      final launch = await ApiScope.of(context).launchMiniApp(a.appId);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MiniAppHostScreen(app: a, launch: launch),
      ));
    }, tr('اجرای برنامه ناموفق بود'));
  }

  Future<void> _payAct(MiniAppPayment p, bool confirmIt) async {
    if (confirmIt) {
      final yes = await _confirm(
        tr('پرداخت به «{0}»', [p.appName]),
        tr('«{0}» به مبلغِ {1} پرداخت شود؟', [p.subject, _toman(p.amount)]),
      );
      if (!yes) return;
    }
    await _run(() async {
      final api = ApiScope.of(context);
      if (confirmIt) {
        await api.confirmMiniAppPayment(p.ref);
      } else {
        await api.cancelMiniAppPayment(p.ref);
      }
      final payments = await api.pendingMiniAppPayments();
      if (!mounted) return;
      setState(() {
        _payments = payments;
        _notice = confirmIt ? tr('پرداخت شد') : tr('پرداخت لغو شد');
      });
    }, tr('انجامِ عملیات ناموفق بود'));
  }

  StatusTone _statusTone(String s) => switch (s) {
        'approved' => StatusTone.success,
        'pending' => StatusTone.warning,
        'rejected' => StatusTone.danger,
        'suspended' => StatusTone.danger,
        _ => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('برنامه‌های کوچک')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: tr('ویترین')),
            Tab(text: tr('نصب‌شده')),
            Tab(text: tr('توسعه‌دهنده')),
            Tab(text: tr('پرداخت‌ها')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_storeTab(), _installedTab(), _devTab(), _paymentsTab()],
      ),
    );
  }

  Widget? _banner() {
    if (_error != null) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(_error!),
        ),
      );
    }
    if (_notice != null) {
      return Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text(_notice!),
        ),
      );
    }
    return null;
  }

  Widget _wrap(List<Widget> children) {
    final banner = _banner();
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (banner != null) ...[banner, const SizedBox(height: 12)],
          ...children,
        ],
      ),
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      );

  Widget _appCard(MiniApp a, String mode) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.widgets_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name, style: theme.textTheme.titleSmall),
                      Text(
                        '${tr(_categories[a.category] ?? a.category)} · '
                        '${a.ownerName ?? a.ownerEarthId}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (mode == 'mine')
                  StatusChip(
                    label: a.statusLabel,
                    tone: _statusTone(a.status),
                  ),
              ],
            ),
            if ((a.tagline ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(a.tagline!, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 6),
            Text(tr('دسترسی‌ها: {0}', [_scopeText(a.scopes)]),
                style: theme.textTheme.bodySmall),
            if (a.needsReconsent)
              Text(tr('برنامه دسترسیِ تازه‌ای خواسته است'),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: DilixSemanticColors.from(context).warning)),
            const SizedBox(height: 4),
            Text(
              mode == 'mine'
                  ? tr('نصب: {0} · اجرا: {1}', [a.installCount, a.openCount])
                  : tr('نصب: {0}', [a.installCount]),
              style: theme.textTheme.bodySmall,
            ),
            if (mode == 'mine' && (a.reviewNote ?? '').isNotEmpty)
              Text(tr('یادداشتِ بازبینی: {0}', [a.reviewNote!]),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            if (mode == 'mine' && _secretAppId == a.appId && _secretValue != null)
              _secretBox(_secretValue!),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (mode == 'store' && !a.isInstalled && !a.isMine)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _install(a),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('نصب')),
                  ),
                if ((a.isInstalled || a.isMine) && a.isApproved)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _launch(a),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(tr('اجرا')),
                  ),
                if (mode == 'installed')
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _uninstall(a),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(tr('حذف')),
                  ),
                if (mode == 'mine' && a.canSubmit)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _submit(a),
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: Text(tr('ارسال برای بازبینی')),
                  ),
                if (mode == 'mine')
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _rotate(a),
                    icon: const Icon(Icons.key_outlined, size: 18),
                    label: Text(tr('کلیدِ تازه')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _secretBox(String secret) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('این کلید فقط همین یک‌بار نمایش داده می‌شود'),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                SelectableText(secret,
                    style: const TextStyle(fontSize: 12, letterSpacing: .5)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: secret));
                        setState(() => _notice = tr('رونوشت شد'));
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(tr('رونوشت')),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _secretAppId = null;
                        _secretValue = null;
                      }),
                      child: Text(tr('بستن')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  // ── ویترین ────────────────────────────────────────────────────────────────
  Widget _storeTab() {
    return _wrap([
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: tr('جستجوی برنامه'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _search,
            child: Text(tr('جستجو')),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_store.isEmpty) _empty(tr('هنوز برنامهٔ تأییدشده‌ای نیست')),
      ..._store.map((a) => _appCard(a, 'store')),
    ]);
  }

  // ── نصب‌شده‌ها ─────────────────────────────────────────────────────────────
  Widget _installedTab() {
    return _wrap([
      if (_installed.isEmpty) _empty(tr('هنوز برنامه‌ای نصب نکرده‌اید')),
      ..._installed.map((a) => _appCard(a, 'installed')),
    ]);
  }

  // ── توسعه‌دهنده ────────────────────────────────────────────────────────────
  Widget _devTab() {
    return _wrap([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('برنامهٔ تازه'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: tr('نامِ برنامه')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                decoration:
                    InputDecoration(labelText: tr('نشانیِ ورود (https)')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _taglineCtrl,
                decoration: InputDecoration(labelText: tr('توضیحِ کوتاه')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(labelText: tr('دسته')),
                items: _categories.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(tr(e.value)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? 'other'),
              ),
              const SizedBox(height: 8),
              Text(tr('دسترسی‌های موردِ نیاز'),
                  style: Theme.of(context).textTheme.bodySmall),
              Wrap(
                spacing: 8,
                children: _scopeLabels.entries
                    .map((e) => FilterChip(
                          label: Text(tr(e.value)),
                          selected: _scopes.contains(e.key),
                          onSelected: (on) => setState(() {
                            if (on) {
                              _scopes.add(e.key);
                            } else {
                              _scopes.remove(e.key);
                            }
                          }),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add),
                  label: Text(tr('ساختِ برنامه')),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('کلیدِ مخفی فقط یک‌بار نشان داده می‌شود. برنامه با آن کدِ '
                    'ورود را به توکنِ نشست تبدیل می‌کند؛ شناسهٔ کاربر برای هر '
                    'برنامه مستعار و جداگانه است.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (_mine.isEmpty) _empty(tr('هنوز برنامه‌ای نساخته‌اید')),
      ..._mine.map((a) => _appCard(a, 'mine')),
    ]);
  }

  // ── پرداخت‌های در انتظار ───────────────────────────────────────────────────
  Widget _paymentsTab() {
    return _wrap([
      if (_payments.isEmpty) _empty(tr('پرداختِ در انتظاری ندارید')),
      ..._payments.map((p) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.subject,
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(p.appName,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(p.ref, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(_toman(p.amount),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : () => _payAct(p, true),
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(tr('پرداخت')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _payAct(p, false),
                          icon: const Icon(Icons.close, size: 18),
                          label: Text(tr('رد')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )),
      const SizedBox(height: 12),
      Text(
        tr('برنامه فقط می‌تواند درخواستِ پرداخت بسازد؛ برداشت از کیفِ پول '
            'همیشه به تأییدِ شما در همین صفحه نیاز دارد.'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }
}
