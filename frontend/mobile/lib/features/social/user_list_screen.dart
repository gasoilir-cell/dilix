import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import 'profile_screen.dart';

import '../../core/l10n.dart';
/// فهرستِ کاربران با یک بارگذارِ تزریق‌شده.
///
/// هر چهار اندپوینتِ فهرستیِ social دقیقاً یک شکل برمی‌گردانند، پس به‌جای چهار
/// صفحهٔ تقریباً یکسان یک صفحه با [loader] داریم.
class UserListScreen extends StatefulWidget {
  const UserListScreen({
    super.key,
    required this.title,
    required this.loader,
    // پیش‌فرضِ پارامتر باید ثابتِ زمانِ کامپایل باشد و `tr()` نیست؛ `null`
    // یعنی «متنِ پیش‌فرض» و هنگامِ ساخت به زبانِ جاری حل می‌شود.
    this.emptyText,
  });

  final String title;
  final Future<List<SocialUser>> Function(ApiClient api) loader;
  final String? emptyText;

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  List<SocialUser>? _users;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_users == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.loader(ApiScope.of(context));
      if (!mounted) return;
      setState(() {
        _users = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('بارگذاری ناموفق بود.\n{0}', [_error]),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _load, child: Text(tr('تلاشِ دوباره'))),
                ],
              ),
            )
          : users == null
              ? const Center(child: CircularProgressIndicator())
              : users.isEmpty
                  ? Center(child: Text(widget.emptyText ?? tr('کسی اینجا نیست.')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: users.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => UserTile(user: users[i]),
                      ),
                    ),
    );
  }
}

/// ردیفِ یک کاربر؛ تپ → پروفایل. در صفحهٔ جستجو هم استفاده می‌شود.
class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.user});

  final SocialUser user;

  @override
  Widget build(BuildContext context) {
    final avatar = AppConfig.absoluteMedia(user.avatarUrl);
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: avatar == null ? null : NetworkImage(avatar),
        child: avatar == null ? Text(user.title.characters.first) : null,
      ),
      title: Text(user.title),
      subtitle: Text(user.username?.isNotEmpty == true
          ? '@${user.username}'
          : user.earthId),
      trailing: user.isFollowing
          ? const Icon(Icons.how_to_reg, size: 20)
          : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            ProfileScreen(earthId: user.earthId, fallbackName: user.name),
      )),
    );
  }
}
