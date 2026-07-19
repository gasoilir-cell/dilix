import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app.dart';
import '../../models/models.dart';

/// جریانِ ارتقای سطحِ تأیید (KYC سطح ۲) — `POST /api/v1/auth/me/kyc`.
/// کاربر کدِ ملی، نام، تاریخِ تولد و دو تصویر (کارتِ ملی + سلفی) را ثبت می‌کند.
class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _nationalIdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  String? _frontPath;
  String? _selfiePath;
  KycStatus? _status;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _nationalIdCtrl.dispose();
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await ApiScope.of(context).me();
      KycStatus? status;
      try {
        status = await ApiScope.of(context).myKyc();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = me.displayName ?? '';
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'بارگذاریِ وضعیت ممکن نشد: $e';
        _loading = false;
      });
    }
  }

  Future<void> _pick(bool front) async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (img == null) return;
    setState(() {
      if (front) {
        _frontPath = img.path;
      } else {
        _selfiePath = img.path;
      }
    });
  }

  bool get _canSubmit =>
      _nationalIdCtrl.text.trim().length == 10 &&
      _nameCtrl.text.trim().isNotEmpty &&
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_dobCtrl.text.trim()) &&
      _frontPath != null &&
      _selfiePath != null;

  Future<void> _submit() async {
    if (!_canSubmit) {
      setState(() => _error =
          'همهٔ فیلدها را کامل کنید (کدِ ملیِ ۱۰رقمی، تاریخ ۱۴۰۳-۰۱-۰۱، دو تصویر).');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final status = await ApiScope.of(context).submitKyc(
        nationalId: _nationalIdCtrl.text.trim(),
        fullName: _nameCtrl.text.trim(),
        dateOfBirth: _dobCtrl.text.trim(),
        frontPath: _frontPath!,
        selfiePath: _selfiePath!,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مدارکِ شما برای بررسی ثبت شد.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'ثبتِ مدارک ممکن نشد: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ارتقای سطحِ تأیید')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_status != null) _statusBanner(_status!),
                const SizedBox(height: 8),
                const Text(
                  'برای ارتقا به سطحِ ۲، مدارکِ زیر را ثبت کنید. اطلاعات پس از '
                  'بررسیِ کارشناس تأیید می‌شود.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nationalIdCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'کدِ ملی',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'نام و نامِ خانوادگی'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _dobCtrl,
                  keyboardType: TextInputType.datetime,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'تاریخِ تولد',
                    hintText: '۱۴۰۳-۰۱-۰۱ (سال-ماه-روز)',
                  ),
                ),
                const SizedBox(height: 16),
                _imagePicker('تصویرِ کارتِ ملی', _frontPath, () => _pick(true)),
                const SizedBox(height: 8),
                _imagePicker('عکسِ سلفی', _selfiePath, () => _pick(false)),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting || !_canSubmit ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('ثبتِ مدارک'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusBanner(KycStatus s) {
    final theme = Theme.of(context);
    late final Color bg;
    late final IconData icon;
    late final String label;
    switch (s.status) {
      case 'approved':
        bg = theme.colorScheme.primaryContainer;
        icon = Icons.verified;
        label = 'احرازِ هویتِ شما تأیید شده است (سطح ${s.level}).';
        break;
      case 'pending':
        bg = theme.colorScheme.secondaryContainer;
        icon = Icons.hourglass_top;
        label = 'مدارکِ شما در حالِ بررسی است.';
        break;
      case 'rejected':
        bg = theme.colorScheme.errorContainer;
        icon = Icons.cancel_outlined;
        label = s.message ?? 'مدارکِ شما رد شد. لطفاً دوباره ارسال کنید.';
        break;
      default:
        bg = theme.colorScheme.surfaceContainerHighest;
        icon = Icons.info_outline;
        label = 'هنوز مدارکی ثبت نکرده‌اید.';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  Widget _imagePicker(String label, String? path, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: path == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined),
                  const SizedBox(height: 8),
                  Text(label),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(path), fit: BoxFit.cover),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: theme.colorScheme.surface,
                      child: const Icon(Icons.edit, size: 16),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
