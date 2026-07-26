import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import '../messages/media_viewer.dart';

import '../../core/l10n.dart';
/// کنسولِ بررسیِ احرازِ هویت — فقط برای نقشِ `admin`/`super_admin`.
///
/// معادلِ `/(main)/admin/kyc` در وب. سرور خودش نقش را چک می‌کند و برای بقیه
/// ۴۰۳ می‌دهد؛ ما ورودیِ صفحه را هم در تبِ «من» فقط به ادمین نشان می‌دهیم تا
/// کاربرِ عادی به بن‌بست نخورد.
class AdminKycScreen extends StatefulWidget {
  const AdminKycScreen({super.key});

  @override
  State<AdminKycScreen> createState() => _AdminKycScreenState();
}

/// وضعیت‌هایی که سرور در فیلترِ `status` می‌پذیرد (`all` = بدونِ فیلتر).
List<(String, String)> get _kycTabs =>
    _kycTabsSrc.map((e) => (e.$1, tr(e.$2))).toList();

const _kycTabsSrc = <(String, String)>[
  ('pending', 'در انتظار'),
  ('approved', 'تأییدشده'),
  ('rejected', 'ردشده'),
  ('all', 'همه'),
];

Map<String, String> get _kycStatusLabels =>
    _kycStatusLabelsSrc.map((k, v) => MapEntry(k, tr(v)));

const _kycStatusLabelsSrc = <String, String>{
  'pending': 'در انتظارِ بررسی',
  'approved': 'تأییدشده',
  'rejected': 'ردشده',
};

class _AdminKycScreenState extends State<AdminKycScreen> {
  String _status = 'pending';
  List<KycRequestItem> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _items.isEmpty && _error == null) _load();
  }

  Future<void> _load() async {
    final api = ApiScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await api.adminKycQueue(status: _status);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.contains('403')
            ? tr('این بخش فقط برای مدیرانِ پلتفرم است.')
            : tr('بارگذاریِ صفِ احرازِ هویت ممکن نشد.\n{0}', [e]);
        _loading = false;
      });
    }
  }

  Future<void> _review(KycRequestItem item, bool approve) async {
    final note = await _askNote(approve);
    if (note == null) return; // انصراف
    if (!mounted) return;
    final api = ApiScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await api.adminReviewKyc(
        item.id,
        approve: approve,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(
        content: Text(result == 'approved'
            ? tr('درخواست تأیید شد.')
            : tr('درخواست رد شد.')),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('ثبتِ بررسی ممکن نشد.\n{0}', [e]))));
    }
  }

  /// یادداشتِ بررسی. `null` = کاربر منصرف شد، رشتهٔ خالی = بدونِ یادداشت.
  Future<String?> _askNote(bool approve) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? tr('تأییدِ هویت') : tr('ردِ درخواست')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              approve
                  ? tr('سطحِ احرازِ هویتِ کاربر ارتقا می‌یابد.')
                  : tr('دلیلِ رد برای کاربر ثبت می‌شود.'),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: approve ? tr('یادداشت (اختیاری)') : tr('دلیلِ رد'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(approve ? tr('تأیید') : tr('رد')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('بررسیِ احرازِ هویت')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: tr('تازه‌سازی'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<String>(
              segments: [
                for (final (value, label) in _kycTabs)
                  ButtonSegment<String>(value: value, label: Text(label)),
              ],
              selected: {_status},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _status = s.first);
                _load();
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: Text(tr('تلاشِ دوباره'))),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(tr('درخواستی در این وضعیت نیست.')));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: _items.length,
        itemBuilder: (_, i) => _card(_items[i]),
      ),
    );
  }

  Widget _card(KycRequestItem item) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.fullName?.isNotEmpty == true ? item.fullName! : tr('بدونِ نام'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(_kycStatusLabels[item.status] ?? item.status),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _row(tr('کدِ ملی'), item.nationalId),
            _row(tr('تاریخِ تولد'), item.dateOfBirth),
            _row(tr('سطحِ درخواستی'), '${item.level}'),
            if (item.createdAt != null)
              _row(tr('تاریخِ ثبت'), _fmtDate(item.createdAt!)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _doc(tr('تصویرِ مدرک'), item.docFrontUrl)),
                const SizedBox(width: 8),
                Expanded(child: _doc(tr('سلفی'), item.docSelfieUrl)),
              ],
            ),
            if (item.isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _review(item, false),
                      icon: const Icon(Icons.close),
                      label: Text(tr('رد')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _review(item, true),
                      icon: const Icon(Icons.check),
                      label: Text(tr('تأیید')),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  /// بندانگشتیِ مدرک؛ با تپ در نمایشگرِ تمام‌صفحه باز می‌شود تا ادمین بتواند
  /// جزئیاتِ کارتِ ملی را بخواند.
  Widget _doc(String label, String? path) {
    final url = AppConfig.absoluteMedia(path);
    if (url == null) {
      return Container(
        height: 110,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(tr('{0} ندارد', [label]),
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MediaViewer(url: url, isVideo: false),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              url,
              height: 110,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 110,
                alignment: Alignment.center,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/'
        '${l.day.toString().padLeft(2, '0')}';
  }
}
