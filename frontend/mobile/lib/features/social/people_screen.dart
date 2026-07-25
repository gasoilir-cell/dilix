import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models/models.dart';
import 'user_list_screen.dart';

/// یافتنِ آدم‌ها: جستجو با نام/یوزرنیم/Earth ID و پیشنهادهای سرور.
///
/// وقتی جعبهٔ جستجو خالی است پیشنهادها (`/social/suggestions`) نمایش داده
/// می‌شوند؛ با تایپ‌کردن به نتیجهٔ `/social/search` سوییچ می‌کند.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  List<SocialUser>? _suggestions;
  List<SocialUser>? _results;
  bool _searching = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_suggestions == null) _loadSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final list = await ApiScope.of(context).followSuggestions();
      if (mounted) setState(() => _suggestions = list);
    } catch (_) {
      // پیشنهاد اختیاری است؛ نبودش نباید جستجو را از کار بیندازد.
      if (mounted) setState(() => _suggestions = const []);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
        _error = null;
      });
      return;
    }
    // سرور حداکثر ۵۰ نویسه می‌پذیرد؛ debounce تا با هر حرف یک درخواست نرود.
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final list = await ApiScope.of(context)
          .searchUsers(q.length > 50 ? q.substring(0, 50) : q);
      if (!mounted || _ctrl.text.trim() != q) return;
      setState(() {
        _results = list;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showingSearch = _ctrl.text.trim().isNotEmpty;
    final list = showingSearch ? _results : _suggestions;
    return Scaffold(
      appBar: AppBar(title: const Text('یافتنِ آدم‌ها')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'نام، یوزرنیم یا DLX-XXXXXXXX',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: showingSearch
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          _onChanged('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (!showingSearch)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('پیشنهاد برای شما'),
              ),
            ),
          Expanded(child: _body(showingSearch, list)),
        ],
      ),
    );
  }

  Widget _body(bool showingSearch, List<SocialUser>? list) {
    if (_error != null) {
      return Center(child: Text('جستجو ناموفق بود.\n$_error',
          textAlign: TextAlign.center));
    }
    if (_searching && list == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) {
      return Center(
          child: Text(showingSearch ? 'کاربری پیدا نشد.' : 'پیشنهادی نیست.'));
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => UserTile(user: list[i]),
    );
  }
}
