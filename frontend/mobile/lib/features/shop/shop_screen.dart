import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/models.dart';

/// فروشگاه و پرداختِ امانی — معادلِ صفحهٔ وبِ `app/(main)/shop/page.tsx`.
///
/// پنج بخش: کاتالوگ، کالاهای من، سبدِ خرید، خریدها، فروش‌ها.
///
/// پولِ خریدار هنگامِ ثبتِ سفارش **بلوکه** می‌شود، نه منتقل؛ تا تأییدِ دریافت،
/// نه در دسترسِ خریدار است و نه مالِ فروشنده. دکمه‌های هر سفارش از پرچم‌های
/// `can*`ِ سرور می‌آیند تا ماشینِ وضعیت دوباره در کلاینت پیاده نشود.
///
/// موجِ B: گونهٔ کالا، چندتصویری، نظراتِ مشروط به تحویل، کدِ تخفیف و سبدِ
/// چندفروشنده — معادلِ کاملِ نسخهٔ وب.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

/// یک ردیفِ سبدِ خرید — فقط محلی است؛ سرور تا لحظهٔ نهاییِ‌شدن آن را نمی‌بیند.
class _CartLine {
  _CartLine({
    required this.productId,
    required this.title,
    required this.price,
    required this.qty,
    required this.sellerEarthId,
    this.variantId,
  });

  final String productId;
  final String? variantId;
  final String title;
  final int price; // ریال — قیمتِ گونه اگر انتخاب شده، وگرنه قیمتِ کالا
  int qty;
  final String sellerEarthId;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'variant_id': variantId,
        'title': title,
        'price': price,
        'qty': qty,
        'seller_earth_id': sellerEarthId,
      };

  factory _CartLine.fromJson(Map<String, dynamic> j) => _CartLine(
        productId: j['product_id'] as String,
        variantId: j['variant_id'] as String?,
        title: (j['title'] ?? '') as String,
        price: (j['price'] ?? 0) as int,
        qty: (j['qty'] ?? 1) as int,
        sellerEarthId: (j['seller_earth_id'] ?? '') as String,
      );
}

/// وقتی کاربر در میانهٔ انتخابِ گونه یا وارد نکردنِ گونهٔ لازم منصرف می‌شود.
class _CancelledException implements Exception {
  const _CancelledException();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  static const _cartPrefsKey = 'dilix_shop_cart_v1';

  late final TabController _tabs = TabController(length: 5, vsync: this);

  final _searchCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _imagesCtrl = TextEditingController();
  final _cartCouponCtrl = TextEditingController();
  final _cartAddressCtrl = TextEditingController();

  bool _busy = false;
  bool _loaded = false;
  String? _error;
  String? _notice;

  List<ShopProduct> _catalog = const [];
  List<ShopProduct> _mine = const [];
  List<ShopOrder> _orders = const [];
  List<ShopOrder> _sales = const [];
  List<_CartLine> _cart = const [];

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

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
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _descCtrl.dispose();
    _imagesCtrl.dispose();
    _cartCouponCtrl.dispose();
    _cartAddressCtrl.dispose();
    super.dispose();
  }

  // سرور ریال می‌دهد؛ کاربرِ ایرانی تومان می‌خواند.
  String _toman(int rial) => tr('{0} تومان', [(rial / 10).round()]);

  // ── سبدِ خرید — پایدار در shared_preferences تا با بستنِ اپ از دست نرود ────
  Future<void> _loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cartPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => _CartLine.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => _cart = list);
    } catch (_) {
      // سبدِ خراب یا فرمتِ کهنه را نادیده بگیر؛ اپ نباید به همین دلیل بشکند.
    }
  }

  Future<void> _saveCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cartPrefsKey,
        jsonEncode(_cart.map((c) => c.toJson()).toList()),
      );
    } catch (_) {
      // فضای ذخیره‌سازی پر یا غیرقابلِ‌دسترس — بی‌اهمیت برای این قابلیت.
    }
  }

  Future<void> _loadAll() async {
    await _run(() async {
      final api = ApiScope.of(context);
      final catalog = await api.shopProducts();
      final mine = await api.myProducts();
      final orders = await api.myOrders();
      final sales = await api.mySales();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _mine = mine;
        _orders = orders;
        _sales = sales;
      });
    }, tr('بارگیریِ فروشگاه ناموفق بود'));
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
      // پیامِ سرور دقیق‌تر است (مثلِ «موجودیِ کالا کافی نیست»).
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

  Future<void> _search() async {
    await _run(() async {
      final api = ApiScope.of(context);
      final rows = await api.shopProducts(q: _searchCtrl.text.trim());
      if (mounted) setState(() => _catalog = rows);
    }, tr('جستجو ناموفق بود'));
  }

  Future<void> _addProduct() async {
    final title = _titleCtrl.text.trim();
    final toman = int.tryParse(_priceCtrl.text.trim()) ?? 0;
    if (title.length < 2) {
      setState(() => _error = tr('عنوان دستِ‌کم دو نویسه باشد'));
      return;
    }
    if (toman < 100) {
      setState(() => _error = tr('قیمت دستِ‌کم ۱۰۰ تومان باشد'));
      return;
    }
    // خالی یعنی نامحدود؛ سرور آن را با ‎-۱ می‌شناسد.
    final raw = _stockCtrl.text.trim();
    final stock = raw.isEmpty ? -1 : (int.tryParse(raw) ?? -1);
    final images = _imagesCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(8)
        .toList();

    await _run(() async {
      final api = ApiScope.of(context);
      await api.createProduct(
        title: title,
        price: toman * 10,
        stock: stock,
        description: _descCtrl.text.trim(),
        images: images.isEmpty ? null : images,
      );
      final mine = await api.myProducts();
      final catalog = await api.shopProducts();
      if (!mounted) return;
      _titleCtrl.clear();
      _priceCtrl.clear();
      _stockCtrl.clear();
      _descCtrl.clear();
      _imagesCtrl.clear();
      setState(() {
        _mine = mine;
        _catalog = catalog;
        _notice = tr('کالا افزوده شد');
      });
    }, tr('افزودنِ کالا ناموفق بود'));
  }

  Future<void> _removeProduct(ShopProduct p) async {
    final yes = await _confirm(
      tr('برداشتنِ کالا'),
      tr('«{0}» از کاتالوگ برداشته شود؟', [p.title]),
    );
    if (!yes) return;
    await _run(() async {
      final api = ApiScope.of(context);
      await api.removeProduct(p.id);
      final mine = await api.myProducts();
      final catalog = await api.shopProducts();
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _catalog = catalog;
        _notice = tr('کالا برداشته شد');
      });
    }, tr('برداشتنِ کالا ناموفق بود'));
  }

  // ── گونهٔ کالا ────────────────────────────────────────────────────────────

  /// اگر کالا گونه دارد یکی را با یک شیت انتخاب می‌کند؛ اگر گونه ندارد `null`
  /// برمی‌گرداند؛ اگر کاربر منصرف شود یا کالا گونهٔ فعالی نداشته باشد استثنا
  /// می‌زند تا صدازننده مطمئن شود خرید نباید ادامه یابد.
  Future<ShopVariant?> _pickVariant(ShopProduct p) async {
    if (!p.hasVariants) return null;
    List<ShopVariant> list;
    try {
      final api = ApiScope.of(context);
      list = (await api.listVariants(p.id)).where((v) => v.isActive).toList();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e is ApiException && e.detail.isNotEmpty ? e.detail : tr('گونه‌های کالا خوانده نشد'));
      }
      throw const _CancelledException();
    }
    if (list.isEmpty) {
      if (mounted) setState(() => _error = tr('این کالا گونهٔ فعالِ خریدپذیری ندارد'));
      throw const _CancelledException();
    }
    if (!mounted) throw const _CancelledException();
    final chosen = await showModalBottomSheet<ShopVariant>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VariantPickSheet(product: p, variants: list, toman: _toman),
    );
    if (chosen == null) throw const _CancelledException();
    return chosen;
  }

  int _unitPrice(ShopProduct p, ShopVariant? v) => v?.price ?? p.price;

  Future<void> _buy(ShopProduct p) async {
    ShopVariant? variant;
    try {
      variant = await _pickVariant(p);
    } on _CancelledException {
      return;
    }
    final qty = await _askQty(
      unlimited: variant?.unlimited ?? p.unlimited,
      stock: variant?.stock ?? p.stock,
    );
    if (qty == null) return;
    final coupon = await _askCoupon();
    final unit = _unitPrice(p, variant);
    final title = variant != null ? '${p.title} (${variant.name})' : p.title;
    final yes = await _confirm(
      tr('ثبتِ سفارش'),
      tr('{0} عدد «{1}» به مبلغِ {2}؟ مبلغ تا تأییدِ دریافت بلوکه می‌ماند و '
          'پس از آن به فروشنده می‌رسد.', [qty, title, _toman(unit * qty)]),
    );
    if (!yes) return;
    await _run(() async {
      final api = ApiScope.of(context);
      await api.createOrder(
        productId: p.id,
        variantId: variant?.id,
        qty: qty,
        couponCode: coupon,
      );
      final orders = await api.myOrders();
      final catalog = await api.shopProducts();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _catalog = catalog;
        _notice = tr('سفارش ثبت شد');
      });
      _tabs.animateTo(3);
    }, tr('ثبتِ سفارش ناموفق بود'));
  }

  Future<void> _addToCart(ShopProduct p) async {
    ShopVariant? variant;
    try {
      variant = await _pickVariant(p);
    } on _CancelledException {
      return;
    }
    final unit = _unitPrice(p, variant);
    final title = variant != null ? '${p.title} (${variant.name})' : p.title;
    setState(() {
      final idx = _cart.indexWhere(
          (c) => c.productId == p.id && c.variantId == variant?.id);
      if (idx >= 0) {
        _cart[idx].qty += 1;
      } else {
        _cart = [
          ..._cart,
          _CartLine(
            productId: p.id,
            variantId: variant?.id,
            title: title,
            price: unit,
            qty: 1,
            sellerEarthId: p.sellerEarthId,
          ),
        ];
      }
      _notice = tr('به سبد افزوده شد');
    });
    await _saveCart();
  }

  void _setCartQty(int i, int qty) {
    setState(() => _cart[i].qty = qty < 1 ? 1 : qty);
    _saveCart();
  }

  void _removeCartLine(int i) {
    setState(() => _cart = List.of(_cart)..removeAt(i));
    _saveCart();
  }

  Future<void> _checkoutCart() async {
    if (_cart.isEmpty) return;
    final code = _cartCouponCtrl.text.trim();
    final address = _cartAddressCtrl.text.trim();
    await _run(() async {
      final api = ApiScope.of(context);
      await api.cartCheckout(
        items: _cart
            .map((c) => {
                  'product_id': c.productId,
                  if (c.variantId != null) 'variant_id': c.variantId,
                  'qty': c.qty,
                  if (code.isNotEmpty) 'coupon_code': code,
                })
            .toList(),
        address: address.isEmpty ? null : address,
      );
      setState(() {
        _cart = const [];
        _cartCouponCtrl.clear();
        _cartAddressCtrl.clear();
        _notice = tr('سبد نهایی شد');
      });
      await _saveCart();
      final orders = await api.myOrders();
      final catalog = await api.shopProducts();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _catalog = catalog;
      });
      _tabs.animateTo(3);
    }, tr('نهاییِ سبد ناموفق بود'));
  }

  Future<int?> _askQty({required bool unlimited, required int stock}) async {
    final ctrl = TextEditingController(text: '1');
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('تعداد')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('چند عدد؟'),
            helperText:
                unlimited ? tr('موجودیِ نامحدود') : tr('موجودی: {0}', [stock]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('انصراف')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 1),
            child: Text(tr('تأیید')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (r == null) return null;
    return r < 1 ? 1 : r;
  }

  /// کدِ تخفیفِ اختیاری پیش از ثبتِ سفارشِ تکی. لغو یا خالی‌گذاشتن هر دو یعنی
  /// بدونِ کد.
  Future<String?> _askCoupon() async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('کدِ تخفیف (اختیاری)')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: tr('کدِ تخفیف')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text(tr('رد کردن')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('اعمال')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _act(ShopOrder o, String kind) async {
    final ask = switch (kind) {
      'accept' => tr('این سفارش پذیرفته شود؟'),
      'ship' => tr('ارسالِ کالا ثبت شود؟'),
      'complete' =>
        tr('دریافتِ کالا تأیید شود؟ پس از آن پول به فروشنده می‌رسد و بازگشتی '
            'در کار نیست.'),
      _ => tr('سفارش لغو و وجهِ بلوکه بازگردانده شود؟'),
    };
    final yes = await _confirm(tr('سفارشِ {0}', [o.ref]), ask);
    if (!yes) return;

    await _run(() async {
      final api = ApiScope.of(context);
      switch (kind) {
        case 'accept':
          await api.acceptOrder(o.id);
        case 'ship':
          await api.shipOrder(o.id);
        case 'complete':
          await api.completeOrder(o.id);
        default:
          await api.cancelOrder(o.id);
      }
      final orders = await api.myOrders();
      final sales = await api.mySales();
      final catalog = await api.shopProducts();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _sales = sales;
        _catalog = catalog;
        _notice = tr('انجام شد');
      });
    }, tr('انجامِ عملیات ناموفق بود'));
  }

  // ── نظرات ────────────────────────────────────────────────────────────────

  Future<void> _openReviews(ShopProduct p) async {
    await _run(() async {
      final api = ApiScope.of(context);
      final reviews = await api.listReviews(p.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _ReviewsSheet(product: p, reviews: reviews),
      );
    }, tr('نظرات خوانده نشد'));
  }

  Future<void> _writeReview(ShopOrder o) async {
    var productId = o.productId;
    var productTitle = o.title;
    if (o.items.length > 1) {
      final chosen = await showDialog<ShopOrderItem>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(tr('نظر برایِ کدام کالا؟')),
          children: o.items
              .map((it) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, it),
                    child: Text(it.title),
                  ))
              .toList(),
        ),
      );
      if (chosen == null) return;
      if (!mounted) return;
      productId = chosen.productId;
      productTitle = chosen.title;
    }
    var rating = 5;
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(tr('نظر برایِ «{0}»', [productTitle])),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    icon: Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                    onPressed: () => setSt(() => rating = i + 1),
                  ),
                ),
              ),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                decoration: InputDecoration(labelText: tr('نظرِ شما (اختیاری)')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('انصراف')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('ثبت')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) {
      commentCtrl.dispose();
      return;
    }
    final comment = commentCtrl.text.trim();
    commentCtrl.dispose();
    await _run(() async {
      final api = ApiScope.of(context);
      await api.reviewOrder(o.id, productId: productId, rating: rating, comment: comment);
      if (mounted) setState(() => _notice = tr('نظر ثبت شد'));
    }, tr('ثبتِ نظر ناموفق بود'));
  }

  // ── مدیریتِ گونه/تخفیف برای فروشنده ─────────────────────────────────────

  Future<void> _manageVariants(ShopProduct p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VariantManageSheet(product: p, toman: _toman),
    );
    await _run(() async {
      final api = ApiScope.of(context);
      final mine = await api.myProducts();
      final catalog = await api.shopProducts();
      if (mounted) {
        setState(() {
          _mine = mine;
          _catalog = catalog;
        });
      }
    }, tr('به‌روزرسانیِ کالاها ناموفق بود'));
  }

  Future<void> _manageCoupons(ShopProduct p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CouponManageSheet(product: p, toman: _toman),
    );
  }

  StatusTone _statusTone(String s) => switch (s) {
        'pending' => StatusTone.warning,
        'accepted' => StatusTone.info,
        'shipped' => StatusTone.accent,
        'completed' => StatusTone.success,
        _ => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('فروشگاه')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: tr('کاتالوگ')),
            Tab(text: tr('کالاهای من')),
            Tab(
              text: _cart.isEmpty
                  ? tr('سبد')
                  : tr('سبد ({0})', [_cart.length]),
            ),
            Tab(text: tr('خریدها')),
            Tab(text: tr('فروش‌ها')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _catalogTab(),
          _mineTab(),
          _cartTab(),
          _ordersTab(),
          _salesTab(),
        ],
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

  Widget _wrap(List<Widget> children, {Future<void> Function()? onRefresh}) {
    final banner = _banner();
    return RefreshIndicator(
      onRefresh: onRefresh ?? _loadAll,
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

  Widget _productThumb(ShopProduct p, {double size = 48}) {
    final url = AppConfig.absoluteMedia(p.gallery.isNotEmpty ? p.gallery.first : null);
    if (url == null) {
      return CircleAvatar(
        radius: size / 2,
        child: const Icon(Icons.inventory_2_outlined),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CircleAvatar(
          radius: size / 2,
          child: const Icon(Icons.inventory_2_outlined),
        ),
      ),
    );
  }

  // ── کاتالوگ ───────────────────────────────────────────────────────────────
  Widget _catalogTab() {
    return _wrap([
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: tr('جستجوی کالا'),
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
      if (_catalog.isEmpty) _empty(tr('فعلاً کالایی برای فروش نیست')),
      ..._catalog.map((p) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _productThumb(p),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(p.title,
                                      style: Theme.of(context).textTheme.titleSmall,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (p.hasVariants) ...[
                                  const SizedBox(width: 6),
                                  Chip(
                                    label: Text(tr('چندگونه'),
                                        style: const TextStyle(fontSize: 10)),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ],
                            ),
                            Text(p.sellerName ?? p.sellerEarthId,
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Text(_toman(p.price),
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                  if ((p.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(p.description!,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.unlimited
                              ? tr('موجودیِ نامحدود')
                              : tr('موجودی: {0}', [p.stock]),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      InkWell(
                        onTap: () => _openReviews(p),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 16, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(
                                p.ratingCount > 0
                                    ? '${(p.ratingAvg ?? 0).toStringAsFixed(1)} (${p.ratingCount})'
                                    : tr('نظرات'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : () => _buy(p),
                          icon: const Icon(Icons.shopping_cart_outlined),
                          label: Text(tr('خرید')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _addToCart(p),
                        child: const Icon(Icons.add_shopping_cart),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )),
      const SizedBox(height: 12),
      Text(
        tr('پولِ شما تا تأییدِ دریافتِ کالا بلوکه می‌ماند و تنها پس از آن به '
            'فروشنده می‌رسد.'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }

  // ── کالاهای من ────────────────────────────────────────────────────────────
  Widget _mineTab() {
    return _wrap([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('افزودنِ کالا'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(labelText: tr('عنوان')),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: tr('قیمت (تومان)')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('موجودی'),
                        helperText: tr('خالی = نامحدود'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr('توضیح')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _imagesCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: tr('تصاویر (اختیاری)'),
                  helperText: tr('هر خط یک نشانی، حداکثر ۸ تا'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _addProduct,
                  icon: const Icon(Icons.add),
                  label: Text(tr('افزودنِ کالا')),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (_mine.isEmpty) _empty(tr('هنوز کالایی نگذاشته‌اید')),
      ..._mine.map((p) => Card(
            child: ListTile(
              leading: _productThumb(p, size: 40),
              title: Row(
                children: [
                  Expanded(child: Text(p.title)),
                  if (!p.isActive)
                    Chip(
                      label: Text(tr('غیرفعال'),
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              subtitle: Text(
                '${_toman(p.price)} · '
                '${p.unlimited ? tr('نامحدود') : tr('موجودی: {0}', [p.stock])} · '
                '${tr('فروخته‌شده: {0}', [p.soldCount])}'
                '${p.ratingCount > 0 ? ' · ★${(p.ratingAvg ?? 0).toStringAsFixed(1)}' : ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: tr('گونه‌های کالا'),
                    icon: const Icon(Icons.style_outlined),
                    onPressed: _busy ? null : () => _manageVariants(p),
                  ),
                  IconButton(
                    tooltip: tr('کدهای تخفیف'),
                    icon: const Icon(Icons.local_offer_outlined),
                    onPressed: _busy ? null : () => _manageCoupons(p),
                  ),
                  if (p.isActive)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _removeProduct(p),
                    ),
                ],
              ),
            ),
          )),
    ]);
  }

  // ── سبدِ خرید ─────────────────────────────────────────────────────────────
  Widget _cartTab() {
    final total = _cart.fold<int>(0, (s, c) => s + c.price * c.qty);
    return _wrap([
      if (_cart.isEmpty) _empty(tr('سبدِ خرید خالی است')),
      ..._cart.asMap().entries.map((entry) {
        final i = entry.key;
        final c = entry.value;
        return Card(
          child: ListTile(
            title: Text(c.title),
            subtitle: Text(_toman(c.price)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _busy ? null : () => _setCartQty(i, c.qty - 1),
                ),
                Text('${c.qty}'),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _busy ? null : () => _setCartQty(i, c.qty + 1),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _removeCartLine(i),
                ),
              ],
            ),
          ),
        );
      }),
      if (_cart.isNotEmpty) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _cartCouponCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: tr('کدِ تخفیف (اختیاری)')),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _cartAddressCtrl,
          decoration: InputDecoration(labelText: tr('نشانی (اختیاری)')),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                tr('جمعِ کل: {0}', [_toman(total)]),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _checkoutCart,
            icon: const Icon(Icons.shopping_cart_checkout),
            label: Text(tr('نهاییِ سبد')),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr('اگر کالاهایِ سبد از فروشنده‌های مختلف باشند، به‌ازای هر فروشنده '
              'یک سفارشِ جدا ساخته می‌شود؛ همه در یک تراکنش.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ]);
  }

  // ── سفارش‌ها ──────────────────────────────────────────────────────────────
  Widget _ordersTab() => _wrap([
        if (_orders.isEmpty) _empty(tr('هنوز خریدی نداشته‌اید')),
        ..._orders.map((o) => _orderCard(o, buying: true)),
      ]);

  Widget _salesTab() => _wrap([
        if (_sales.isEmpty) _empty(tr('هنوز فروشی نداشته‌اید')),
        ..._sales.map((o) => _orderCard(o, buying: false)),
      ]);

  Widget _orderCard(ShopOrder o, {required bool buying}) {
    final peer = buying
        ? (o.sellerName ?? o.sellerEarthId)
        : (o.buyerName ?? o.buyerEarthId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(o.title,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                StatusChip(label: o.statusLabel, tone: _statusTone(o.status)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${buying ? tr('فروشنده') : tr('خریدار')}: $peer',
                style: Theme.of(context).textTheme.bodySmall),
            Text(o.ref, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            if (o.items.length > 1)
              ...o.items.map((it) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('${it.title}: ${it.qty} × ${_toman(it.unitPrice)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ))
            else
              Text('${o.qty} × ${_toman(o.unitPrice)} = ${_toman(o.total + o.discount)}'),
            if (o.discount > 0)
              Text(
                tr('تخفیف{0}: -{1}',
                    [o.couponCode != null ? ' (${o.couponCode})' : '', _toman(o.discount)]),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DilixSemanticColors.from(context).success),
              ),
            Text(tr('جمعِ کل: {0}', [_toman(o.total)]),
                style: Theme.of(context).textTheme.bodySmall),
            if (o.commission > 0)
              Text(tr('کارمزدِ پلتفرم: {0}', [_toman(o.commission)]),
                  style: Theme.of(context).textTheme.bodySmall),
            if (o.escrowLocked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('وجه بلوکه است'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DilixSemanticColors.from(context).warning)),
              ),
            if ((o.address ?? '').isNotEmpty)
              Text(tr('نشانی: {0}', [o.address!]),
                  style: Theme.of(context).textTheme.bodySmall),
            if (o.hasAction || (buying && o.status == 'completed')) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (o.canAccept)
                    FilledButton(
                      onPressed: _busy ? null : () => _act(o, 'accept'),
                      child: Text(tr('پذیرش')),
                    ),
                  if (o.canShip)
                    FilledButton(
                      onPressed: _busy ? null : () => _act(o, 'ship'),
                      child: Text(tr('ارسال شد')),
                    ),
                  if (o.canComplete)
                    FilledButton(
                      onPressed: _busy ? null : () => _act(o, 'complete'),
                      child: Text(tr('تأییدِ دریافت')),
                    ),
                  if (o.canCancel)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _act(o, 'cancel'),
                      child: Text(tr('لغو')),
                    ),
                  if (buying && o.status == 'completed')
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _writeReview(o),
                      icon: const Icon(Icons.star_border, size: 18),
                      label: Text(tr('ثبتِ نظر')),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// شیتِ انتخابِ گونهٔ کالا پیش از خرید/افزودن به سبد.
class _VariantPickSheet extends StatelessWidget {
  const _VariantPickSheet({
    required this.product,
    required this.variants,
    required this.toman,
  });

  final ShopProduct product;
  final List<ShopVariant> variants;
  final String Function(int) toman;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.style_outlined),
            title: Text(tr('انتخابِ گونه — {0}', [product.title])),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: variants.length,
              itemBuilder: (ctx, i) {
                final v = variants[i];
                final out = !v.unlimited && v.stock <= 0;
                return ListTile(
                  enabled: !out,
                  title: Text(v.name),
                  subtitle: Text(
                    '${toman(v.price ?? product.price)} · '
                    '${v.unlimited ? tr('نامحدود') : tr('موجودی: {0}', [v.stock])}',
                  ),
                  trailing: out ? Text(tr('ناموجود')) : null,
                  onTap: out ? null : () => Navigator.pop(context, v),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// شیتِ نمایشِ نظراتِ یک کالا.
class _ReviewsSheet extends StatelessWidget {
  const _ReviewsSheet({required this.product, required this.reviews});

  final ShopProduct product;
  final List<ShopReview> reviews;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(tr('نظراتِ «{0}»', [product.title])),
            subtitle: reviews.isNotEmpty
                ? Text(tr('میانگین {0} از {1} نظر',
                    [(product.ratingAvg ?? 0).toStringAsFixed(1), reviews.length]))
                : null,
          ),
          const Divider(height: 1),
          if (reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('هنوز نظری ثبت نشده است.')),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: reviews.length,
                itemBuilder: (ctx, i) {
                  final r = reviews[i];
                  return ListTile(
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        5,
                        (j) => Icon(
                          j < r.rating ? Icons.star : Icons.star_border,
                          size: 14,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                    title: Text(r.buyerName ?? r.buyerEarthId),
                    subtitle: (r.comment ?? '').isNotEmpty ? Text(r.comment!) : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// شیتِ مدیریتِ گونه‌های یک کالا برای فروشنده — افزودن/فهرست/غیرفعال‌سازی.
class _VariantManageSheet extends StatefulWidget {
  const _VariantManageSheet({required this.product, required this.toman});

  final ShopProduct product;
  final String Function(int) toman;

  @override
  State<_VariantManageSheet> createState() => _VariantManageSheetState();
}

class _VariantManageSheetState extends State<_VariantManageSheet> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  List<ShopVariant> _variants = const [];
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final list = await ApiScope.of(context).listVariants(widget.product.id);
      if (mounted) setState(() => _variants = list);
    } catch (_) {
      if (mounted) setState(() => _error = tr('گونه‌ها خوانده نشد'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = tr('نامِ گونه لازم است'));
      return;
    }
    final toman = int.tryParse(_priceCtrl.text.trim());
    final stockRaw = _stockCtrl.text.trim();
    final stock = stockRaw.isEmpty ? -1 : (int.tryParse(stockRaw) ?? -1);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiScope.of(context).addVariant(
        widget.product.id,
        name: name,
        price: toman == null ? null : toman * 10,
        stock: stock,
      );
      _nameCtrl.clear();
      _priceCtrl.clear();
      _stockCtrl.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail.isNotEmpty ? e.detail : tr('افزودنِ گونه ناموفق بود'));
    } catch (_) {
      if (mounted) setState(() => _error = tr('افزودنِ گونه ناموفق بود'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ShopVariant v) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('غیرفعال‌سازیِ گونه')),
        content: Text(tr('«{0}» غیرفعال شود؟', [v.name])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('انصراف'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('تأیید'))),
        ],
      ),
    );
    if (yes != true) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ApiScope.of(context).deactivateVariant(widget.product.id, v.id);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = tr('غیرفعال‌سازیِ گونه ناموفق بود'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('گونه‌هایِ «{0}»', [widget.product.title]),
                    style: Theme.of(context).textTheme.titleMedium),
                if (_busy) const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (_variants.isEmpty && !_busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(tr('هنوز گونه‌ای ندارد')),
                  ),
                ..._variants.map((v) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(v.name),
                      subtitle: Text(
                        '${widget.toman(v.price ?? widget.product.price)} · '
                        '${v.unlimited ? tr('نامحدود') : tr('موجودی: {0}', [v.stock])}'
                        '${v.isActive ? '' : ' · ${tr('غیرفعال')}'}',
                      ),
                      trailing: v.isActive
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _remove(v),
                            )
                          : null,
                    )),
                const Divider(),
                Text(tr('افزودنِ گونهٔ تازه'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(labelText: tr('نام (مثلاً قرمز/بزرگ)')),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('قیمت (تومان)'),
                          helperText: tr('خالی = هم‌قیمتِ کالا'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('موجودی'),
                          helperText: tr('خالی = نامحدود'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add),
                    label: Text(tr('افزودنِ گونه')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شیتِ مدیریتِ کدهایِ تخفیفِ یک کالا (یا کلِ فروشگاهِ فروشنده).
class _CouponManageSheet extends StatefulWidget {
  const _CouponManageSheet({required this.product, required this.toman});

  final ShopProduct product;
  final String Function(int) toman;

  @override
  State<_CouponManageSheet> createState() => _CouponManageSheetState();
}

class _CouponManageSheetState extends State<_CouponManageSheet> {
  final _codeCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();
  final _maxUsesCtrl = TextEditingController();
  final _daysCtrl = TextEditingController();
  String _type = 'percent';
  bool _scopeThisProduct = true;
  List<ShopCoupon> _coupons = const [];
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _maxUsesCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final all = await ApiScope.of(context).myCoupons();
      final mine = all
          .where((c) => c.productId == null || c.productId == widget.product.id)
          .toList();
      if (mounted) setState(() => _coupons = mine);
    } catch (_) {
      if (mounted) setState(() => _error = tr('کدهایِ تخفیف خوانده نشد'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final code = _codeCtrl.text.trim();
    final value = int.tryParse(_valueCtrl.text.trim()) ?? 0;
    if (code.length < 3) {
      setState(() => _error = tr('کدِ تخفیف دستِ‌کم سه نویسه باشد'));
      return;
    }
    if (value <= 0 || (_type == 'percent' && value > 90)) {
      setState(() => _error = tr('مقدارِ تخفیف نامعتبر است (درصد حداکثر ۹۰)'));
      return;
    }
    final maxUsesRaw = _maxUsesCtrl.text.trim();
    final daysRaw = _daysCtrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiScope.of(context).createCoupon(
        code: code,
        discountType: _type,
        discountValue: _type == 'fixed' ? value * 10 : value,
        productId: _scopeThisProduct ? widget.product.id : null,
        maxUses: maxUsesRaw.isEmpty ? null : int.tryParse(maxUsesRaw),
        expiresAt: daysRaw.isEmpty
            ? null
            : DateTime.now().add(Duration(days: int.tryParse(daysRaw) ?? 0)),
      );
      _codeCtrl.clear();
      _valueCtrl.clear();
      _maxUsesCtrl.clear();
      _daysCtrl.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.detail.isNotEmpty ? e.detail : tr('ساختِ کدِ تخفیف ناموفق بود'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = tr('ساختِ کدِ تخفیف ناموفق بود'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ShopCoupon c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('غیرفعال‌سازیِ کدِ تخفیف')),
        content: Text(tr('«{0}» غیرفعال شود؟', [c.code])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('انصراف'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('تأیید'))),
        ],
      ),
    );
    if (yes != true) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ApiScope.of(context).deactivateCoupon(c.id);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = tr('غیرفعال‌سازی ناموفق بود'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(ShopCoupon c) {
    final val = c.discountType == 'percent'
        ? tr('{0}٪', [c.discountValue])
        : widget.toman(c.discountValue);
    final scope = c.productId == null ? tr('همهٔ کالاها') : tr('همین کالا');
    final uses = c.maxUses == null
        ? tr('{0} بار مصرف‌شده', [c.usedCount])
        : tr('{0}/{1} مصرف‌شده', [c.usedCount, c.maxUses]);
    return '$val · $scope · $uses${c.isActive ? '' : ' · ${tr('غیرفعال')}'}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('کدهایِ تخفیفِ «{0}»', [widget.product.title]),
                    style: Theme.of(context).textTheme.titleMedium),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (_coupons.isEmpty && !_busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(tr('هنوز کدِ تخفیفی ندارید')),
                  ),
                ..._coupons.map((c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.code),
                      subtitle: Text(_describe(c)),
                      trailing: c.isActive
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _remove(c),
                            )
                          : null,
                    )),
                const Divider(),
                Text(tr('ساختِ کدِ تازه'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: tr('کد')),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: InputDecoration(labelText: tr('نوع')),
                        items: [
                          DropdownMenuItem(value: 'percent', child: Text(tr('درصدی'))),
                          DropdownMenuItem(value: 'fixed', child: Text(tr('مبلغِ ثابت'))),
                        ],
                        onChanged: (v) => setState(() => _type = v ?? 'percent'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _valueCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _type == 'percent' ? tr('درصد (≤۹۰)') : tr('تومان'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _maxUsesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('سقفِ مصرف'),
                          helperText: tr('خالی = نامحدود'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _daysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('اعتبار (روز)'),
                          helperText: tr('خالی = بدونِ انقضا'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('فقط رویِ همین کالا')),
                  subtitle: Text(tr('خاموش = رویِ کلِ کالاهایِ فروشگاهِ شما')),
                  value: _scopeThisProduct,
                  onChanged: (v) => setState(() => _scopeThisProduct = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add),
                    label: Text(tr('ساختِ کد')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
