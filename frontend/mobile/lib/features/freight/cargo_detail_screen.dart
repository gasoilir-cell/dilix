import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/location_service.dart';
import '../../models/models.dart';

import '../../core/l10n.dart';
/// برچسبِ فارسیِ وضعیت‌های واقعیِ سرور (`CargoPost.status`).
Map<String, String> get cargoStatusLabels =>
    cargoStatusLabelsSrc.map((k, v) => MapEntry(k, tr(v)));

const cargoStatusLabelsSrc = <String, String>{
  'open': 'باز',
  'in_progress': 'پذیرفته‌شده',
  'picked_up': 'تحویل‌گرفته‌شده',
  'in_transit': 'در مسیر',
  'delivered': 'تحویل در مقصد',
  'received': 'تسویه‌شده',
  'cancelled': 'لغوشده',
};

/// جزئیات و چرخهٔ عمرِ یک حمل — `GET /freight/posts/{id}` و کنش‌های
/// take / pickup / deliver / receive / cancel به‌همراهِ خطِ زمانیِ رهگیری.
///
/// نقشِ کاربر از روی `owner_id`/`driver_id` تعیین می‌شود، پس شناسهٔ داخلیِ خودم
/// را لازم داریم؛ Earth ID اینجا به کار نمی‌آید.
class CargoDetailScreen extends StatefulWidget {
  const CargoDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  State<CargoDetailScreen> createState() => _CargoDetailScreenState();
}

class _CargoDetailScreenState extends State<CargoDetailScreen> {
  CargoPost? _post;
  List<TrackingEvent> _events = const [];
  List<FreightOffer> _offers = const [];
  String? _myId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// اگر چیزی عوض شد، فهرستِ پشتِ سر باید تازه شود.
  bool _changed = false;

  /// سرور امتیازِ تکراری را رد می‌کند و راهی برای «آیا امتیاز داده‌ام؟» ندارد،
  /// پس در همین نشست دکمه را پس از ثبت پنهان می‌کنیم.
  bool _rated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _post == null) _load();
  }

  Future<void> _load() async {
    final api = ApiScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await api.cargoPost(widget.postId);
      String? myId = _myId;
      myId ??= (await api.me()).userId;
      // رهگیری فقط برای طرفینِ حمل مجاز است؛ برای بقیه ۴۰۳ می‌دهد و آن را
      // خطای صفحه حساب نمی‌کنیم.
      List<TrackingEvent> events = const [];
      try {
        events = await api.cargoTracking(widget.postId);
      } catch (_) {}
      // پیشنهادها هم دیدِ نقش-محور دارند؛ برای بارِ بسته یا کاربرِ بی‌ربط
      // خالی/خطا برمی‌گردد و نباید صفحه را بشکند.
      List<FreightOffer> offers = const [];
      try {
        offers = await api.cargoOffers(widget.postId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _post = post;
        _myId = myId;
        _events = events;
        _offers = offers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('بارگذاریِ اطلاعاتِ حمل ممکن نشد.\n{0}', [e]);
        _loading = false;
      });
    }
  }

  bool get _isOwner => _myId != null && _post?.ownerId == _myId;
  bool get _isDriver => _myId != null && _post?.driverId == _myId;

  Future<void> _run(Future<CargoPost> Function() action, String okText) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        _post = updated;
        _busy = false;
        _changed = true;
      });
      messenger.showSnackBar(SnackBar(content: Text(okText)));
      // خطِ زمانی پس از هر کنش یک رویدادِ تازه دارد.
      try {
        final events = await ApiScope.of(context).cargoTracking(widget.postId);
        if (mounted) setState(() => _events = events);
      } catch (_) {}
      await _reloadOffers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  /// متنِ خطای سرور معمولاً پیامِ فارسیِ قابلِ‌نمایش دارد؛ همان را نشان می‌دهیم.
  String _message(Object e) {
    final s = e.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  Future<void> _take() => _run(
        () => ApiScope.of(context).takeCargo(widget.postId),
        tr('بار پذیرفته شد؛ وجهِ صاحبِ بار امانی شد.'),
      );

  Future<void> _pickup() async {
    final code = await _askCode(tr('کدِ مبدأ'), tr('کدِ ۴رقمی را از صاحبِ بار بگیرید.'));
    if (code == null) return;
    await _run(
      () => ApiScope.of(context).pickupCargo(widget.postId, code),
      tr('تحویل‌گیری در مبدأ ثبت شد.'),
    );
  }

  Future<void> _deliver() => _run(
        () => ApiScope.of(context).deliverCargo(widget.postId),
        tr('تحویل در مقصد ثبت شد؛ منتظرِ تأییدِ گیرنده بمانید.'),
      );

  Future<void> _receive() async {
    final code = await _askCode(tr('کدِ مقصد'), tr('کدِ ۴رقمیِ مقصد را وارد کنید.'));
    if (code == null) return;
    await _run(
      () => ApiScope.of(context).receiveCargo(widget.postId, code),
      tr('دریافت تأیید و حمل تسویه شد.'),
    );
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('لغوِ بار')),
        content: Text(
          tr('اگر بار پذیرفته شده باشد، وجهِ امانی کاملاً به شما بازمی‌گردد. پس از تحویل‌گیری دیگر لغو ممکن نیست.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('بی‌خیال'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('لغو کن'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ApiScope.of(context).cancelCargo(widget.postId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('بار لغو شد.'))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  Future<void> _reloadOffers() async {
    try {
      final offers = await ApiScope.of(context).cargoOffers(widget.postId);
      if (mounted) setState(() => _offers = offers);
    } catch (_) {}
  }

  /// پیشنهادِ من روی این بار (اگر داده باشم). سرور برای راننده فقط همین یکی را
  /// برمی‌گرداند، ولی برای اطمینان با `isMine` هم فیلتر می‌کنیم.
  FreightOffer? get _myOffer {
    for (final o in _offers) {
      if (o.isMine && o.isPending) return o;
    }
    return null;
  }

  Future<void> _makeOffer() async {
    final existing = _myOffer;
    final result = await showDialog<(int, int?, String)>(
      context: context,
      builder: (ctx) => _OfferDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final (price, eta, message) = result;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ApiScope.of(context).makeCargoOffer(
        widget.postId,
        price: price,
        etaDays: eta,
        message: message,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _changed = true;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(existing == null
            ? tr('پیشنهادِ شما ثبت شد.')
            : tr('پیشنهادِ شما به‌روزرسانی شد.')),
      ));
      await _reloadOffers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  Future<void> _withdrawOffer(FreightOffer offer) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ApiScope.of(context).withdrawCargoOffer(offer.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _changed = true;
      });
      messenger.showSnackBar(SnackBar(content: Text(tr('پیشنهاد پس گرفته شد.'))));
      await _reloadOffers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  Future<void> _acceptOffer(FreightOffer offer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('پذیرشِ پیشنهاد')),
        content: Text(
          tr('با پذیرش، {0} تومان از کیفِ پولِ شما امانی می‌شود و بقیهٔ پیشنهادها رد می‌شوند. این کار برگشت‌پذیر نیست.', [_money(offer.price ~/ 10)]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('بی‌خیال'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('می‌پذیرم'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => ApiScope.of(context).acceptCargoOffer(offer.id),
      tr('پیشنهاد پذیرفته شد و راننده تخصیص یافت.'),
    );
  }

  /// راننده موقعیتِ فعلیِ گوشی را روی مسیر ثبت می‌کند. نخستین ارسال، بار را از
  /// «تحویل‌گرفته‌شده» به «در مسیر» می‌برد.
  Future<void> _sendLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final fix = await const LocationService().current();
    if (!mounted) return;
    if (fix.error != null) {
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(fix.error!)));
      return;
    }
    setState(() => _busy = false);
    await _run(
      () => ApiScope.of(context)
          .updateCargoLocation(widget.postId, lat: fix.lat, lng: fix.lng),
      tr('موقعیتِ شما ثبت شد.'),
    );
  }

  Future<void> _rate() async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (ctx) => const _RatingDialog(),
    );
    if (result == null || !mounted) return;
    final (score, comment) = result;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ApiScope.of(context)
          .rateCargo(widget.postId, score: score, comment: comment);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _rated = true;
      });
      messenger.showSnackBar(SnackBar(content: Text(tr('امتیازِ شما ثبت شد.'))));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // سرور برای امتیازِ تکراری ۴۰۰ می‌دهد؛ همان را نشان می‌دهیم و دکمه را
      // پنهان می‌کنیم تا کاربر دوباره تلاش نکند.
      if (_message(e).contains(tr('قبلاً'))) setState(() => _rated = true);
      messenger.showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  Future<String?> _askCode(String title, String hint) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: InputDecoration(hintText: hint, counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('انصراف'))),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            child: Text(tr('تأیید')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(p?.ref ?? tr('جزئیاتِ حمل'))),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _summaryCard(p!),
                        const SizedBox(height: 8),
                        if (_isOwner && (p.pickupCode != null || p.deliveryCode != null))
                          _codesCard(p),
                        _actionsCard(p),
                        const SizedBox(height: 8),
                        _offersCard(p),
                        _timelineCard(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _summaryCard(CargoPost p) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.title,
                      style: t.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Chip(label: Text(cargoStatusLabels[p.status] ?? p.status)),
              ],
            ),
            const SizedBox(height: 8),
            _row(Icons.route_outlined, '${p.origin} ← ${p.destination}'),
            _row(Icons.scale_outlined, _weight(p.weightGrams)),
            if (p.budgetMinor != null && p.budgetMinor! > 0)
              _row(Icons.payments_outlined, tr('{0} تومان', [_money(p.budgetMinor!)])),
            if (p.escrowStatus != null)
              _row(Icons.lock_outline, tr('وجهِ امانی: {0}', [_escrow(p.escrowStatus!)])),
            if (p.consigneeName != null)
              _row(Icons.person_outline, tr('گیرنده: {0}', [p.consigneeName])),
            if (p.description != null && p.description!.isNotEmpty) ...[
              const Divider(height: 24),
              Text(p.description!, style: t.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _codesCard(CargoPost p) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('کدهای تأیید'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              tr('کدِ مبدأ را هنگامِ بارگیری به راننده بدهید؛ کدِ مقصد را فقط پس از دریافتِ سالمِ بار وارد کنید.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (p.pickupCode != null)
                  Expanded(child: _codeBox(tr('مبدأ'), p.pickupCode!)),
                if (p.pickupCode != null && p.deliveryCode != null)
                  const SizedBox(width: 8),
                if (p.deliveryCode != null)
                  Expanded(child: _codeBox(tr('مقصد'), p.deliveryCode!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeBox(String label, String code) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(code,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 4)),
          ],
        ),
      );

  Widget _actionsCard(CargoPost p) {
    final buttons = <Widget>[];

    if (!_isOwner && !_isDriver && p.isOpen) {
      final mine = _myOffer;
      buttons.add(FilledButton.icon(
        onPressed: _busy ? null : _makeOffer,
        icon: const Icon(Icons.local_offer_outlined),
        label: Text(mine == null ? tr('پیشنهادِ قیمت') : tr('ویرایشِ پیشنهاد')),
      ));
      if (mine != null) {
        buttons.add(OutlinedButton.icon(
          onPressed: _busy ? null : () => _withdrawOffer(mine),
          icon: const Icon(Icons.undo),
          label: Text(tr('پس‌گرفتنِ پیشنهاد')),
        ));
      }
      // پذیرشِ مستقیم با کرایهٔ اعلامیِ صاحبِ بار، بدونِ چانه‌زنی.
      buttons.add(OutlinedButton.icon(
        onPressed: _busy ? null : _take,
        icon: const Icon(Icons.local_shipping_outlined),
        label: Text(tr('پذیرشِ بار با کرایهٔ اعلامی')),
      ));
    }
    if (_isDriver && p.status == 'in_progress') {
      buttons.add(FilledButton.icon(
        onPressed: _busy ? null : _pickup,
        icon: const Icon(Icons.qr_code_2),
        label: Text(tr('تحویل‌گیری با کدِ مبدأ')),
      ));
    }
    if (_isDriver && (p.status == 'picked_up' || p.status == 'in_transit')) {
      buttons.add(OutlinedButton.icon(
        onPressed: _busy ? null : _sendLocation,
        icon: const Icon(Icons.my_location),
        label: Text(tr('ثبتِ موقعیتِ فعلی')),
      ));
      buttons.add(FilledButton.icon(
        onPressed: _busy ? null : _deliver,
        icon: const Icon(Icons.done_all),
        label: Text(tr('ثبتِ تحویل در مقصد')),
      ));
    }
    if (_isOwner && p.status == 'delivered') {
      buttons.add(FilledButton.icon(
        onPressed: _busy ? null : _receive,
        icon: const Icon(Icons.verified_outlined),
        label: Text(tr('تأییدِ دریافت با کدِ مقصد')),
      ));
    }
    if (_isOwner && (p.isOpen || p.status == 'in_progress')) {
      buttons.add(OutlinedButton.icon(
        onPressed: _busy ? null : _cancel,
        icon: const Icon(Icons.cancel_outlined),
        label: Text(tr('لغوِ بار')),
      ));
    }
    // امتیازدهیِ متقابل فقط پس از تسویه و فقط برای طرفینِ حمل.
    if ((_isOwner || _isDriver) && p.status == 'received' && !_rated) {
      buttons.add(FilledButton.icon(
        onPressed: _busy ? null : _rate,
        icon: const Icon(Icons.star_outline),
        label: Text(_isOwner ? tr('امتیاز به راننده') : tr('امتیاز به صاحبِ بار')),
      ));
    }

    if (buttons.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            p.status == 'received'
                ? tr('این حمل کامل و تسویه شده است.')
                : tr('در این مرحله کنشی از سمتِ شما لازم نیست.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final b in buttons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(width: double.infinity, child: b),
              ),
          ],
        ),
      ),
    );
  }

  Widget _offersCard(CargoPost p) {
    if (_offers.isEmpty) {
      // برای صاحبِ بارِ باز، «هنوز پیشنهادی نیست» خودش اطلاعاتِ مفیدی است.
      if (!_isOwner || !p.isOpen) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr('هنوز پیشنهادی برای این بار ثبت نشده است.'),
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isOwner ? tr('پیشنهادهای رانندگان') : tr('پیشنهادِ من'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final o in _offers) _offerRow(o, p),
          ],
        ),
      ),
    );
  }

  Widget _offerRow(FreightOffer o, CargoPost p) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  o.driverName?.isNotEmpty == true ? o.driverName! : tr('راننده'),
                  style: t.titleSmall,
                ),
              ),
              if (o.best)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Chip(
                    label: Text(tr('بهترین')),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Text(tr('{0} تومان', [_money(o.price ~/ 10)]),
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.star, size: 14),
              const SizedBox(width: 3),
              Text(o.driverRating.toStringAsFixed(1), style: t.bodySmall),
              const SizedBox(width: 10),
              Text(tr('{0} سفر', [o.driverTrips]), style: t.bodySmall),
              if (o.etaDays != null) ...[
                const SizedBox(width: 10),
                Text(tr('حدودِ {0} روز', [o.etaDays]), style: t.bodySmall),
              ],
            ],
          ),
          if (o.message != null && o.message!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(o.message!, style: t.bodySmall),
            ),
          if (_isOwner && p.isOpen && o.isPending)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _busy ? null : () => _acceptOffer(o),
                child: Text(tr('پذیرشِ این پیشنهاد')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timelineCard() {
    if (_events.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('خطِ زمانیِ رهگیری'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final e in _events)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_eventIcon(e.eventType), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.note ?? _eventLabel(e.eventType)),
                          if (e.createdAt != null)
                            Text(_when(e.createdAt!),
                                style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(text)),
          ],
        ),
      );

  static String _weight(int grams) {
    final kg = grams / 1000;
    final text =
        kg == kg.roundToDouble() ? kg.round().toString() : kg.toStringAsFixed(1);
    return tr('{0} کیلوگرم', [text]);
  }

  static String _money(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(tr('،'));
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _escrow(String s) => switch (s) {
        'locked' => tr('بلوکه‌شده'),
        'released' => tr('آزادشده'),
        'refunded' => tr('بازگردانده‌شده'),
        _ => s,
      };

  static IconData _eventIcon(String t) => switch (t) {
        'created' => Icons.add_box_outlined,
        'accepted' => Icons.handshake_outlined,
        'picked_up' => Icons.inventory_2_outlined,
        'location' => Icons.my_location,
        'delivered' => Icons.done_all,
        'received' => Icons.verified_outlined,
        'cancelled' => Icons.cancel_outlined,
        _ => Icons.circle_outlined,
      };

  static String _eventLabel(String t) => switch (t) {
        'created' => tr('بار ثبت شد'),
        'accepted' => tr('راننده تخصیص یافت'),
        'picked_up' => tr('بار در مبدأ تحویل گرفته شد'),
        'location' => tr('موقعیتِ تازه ثبت شد'),
        'delivered' => tr('بار در مقصد تحویل داده شد'),
        'received' => tr('دریافت تأیید شد'),
        'cancelled' => tr('بار لغو شد'),
        _ => t,
      };

  static String _when(DateTime t) {
    final d = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

/// فرمِ پیشنهادِ قیمت. خروجی `(قیمتِ ریالی، روزِ تخمینی، پیام)`.
///
/// کاربر مبلغ را به **تومان** وارد می‌کند ولی سرور ریال می‌خواهد، پس ×۱۰ می‌شود.
class _OfferDialog extends StatefulWidget {
  const _OfferDialog({this.existing});

  final FreightOffer? existing;

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  late final TextEditingController _price = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.price ~/ 10}',
  );
  late final TextEditingController _eta = TextEditingController(
    text: widget.existing?.etaDays?.toString() ?? '',
  );
  late final TextEditingController _msg =
      TextEditingController(text: widget.existing?.message ?? '');
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    _eta.dispose();
    _msg.dispose();
    super.dispose();
  }

  void _submit() {
    final toman = int.tryParse(_price.text.trim().replaceAll(tr('،'), ''));
    if (toman == null || toman <= 0) {
      setState(() => _error = tr('کرایهٔ پیشنهادی را وارد کنید.'));
      return;
    }
    final eta = int.tryParse(_eta.text.trim());
    Navigator.pop(context, (toman * 10, eta, _msg.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? tr('پیشنهادِ قیمت') : tr('ویرایشِ پیشنهاد')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _price,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('کرایهٔ پیشنهادی (تومان)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _eta,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('زمانِ تخمینی (روز) — اختیاری'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _msg,
              maxLines: 2,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: tr('توضیح برای صاحبِ بار — اختیاری'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('انصراف'))),
        FilledButton(onPressed: _submit, child: Text(tr('ثبت'))),
      ],
    );
  }
}

/// امتیازِ ۱ تا ۵ ستاره + نظرِ اختیاری. خروجی `(امتیاز، نظر)`.
class _RatingDialog extends StatefulWidget {
  const _RatingDialog();

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _score = 5;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('امتیازِ این حمل')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _score = i),
                  icon: Icon(i <= _score ? Icons.star : Icons.star_border),
                  iconSize: 30,
                ),
            ],
          ),
          TextField(
            controller: _comment,
            maxLines: 2,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: tr('نظرِ شما — اختیاری'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('انصراف'))),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_score, _comment.text.trim())),
          child: Text(tr('ثبتِ امتیاز')),
        ),
      ],
    );
  }
}
