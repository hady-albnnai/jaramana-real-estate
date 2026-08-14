import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/network/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../services/storage_service.dart';

/// 💳 محرّر قنوات الدفع — المرحلة 11 (Config-Driven)
///
/// يقرأ `config.payChannels` ويسمح بـ:
///   - تفعيل/تعطيل كل قناة
///   - تعديل البيانات (اسم المستقبل، رقم الحساب...)
///   - رفع صورة QR لشام كاش إلى bucket `config_assets`
///   - تعديل نص التعليمات
class PaymentChannelsEditorScreen extends StatefulWidget {
  const PaymentChannelsEditorScreen({super.key});

  @override
  State<PaymentChannelsEditorScreen> createState() =>
      _PaymentChannelsEditorScreenState();
}

class _PaymentChannelsEditorScreenState
    extends State<PaymentChannelsEditorScreen> {
  bool _saving = false;
  Map<String, Map<String, dynamic>> _channels = {};
  Map<String, Map<String, TextEditingController>> _controllers = {};
  Map<String, bool> _enabled = {};

  /// 📞 رقم المكتب الهاتفي — يُستخدم كوجهة تحويل رصيد الجوال
  final _officePhoneCtrl = TextEditingController();

  /// القنوات القابلة للتحرير من هذه الشاشة
  static const _editableChannels = ['haram', 'sham_cash', 'syriatel_cash', 'balance', 'bank'];

  final _storage = StorageService();

  /// الحقول لكل قناة (ما عدا enabled, name, icon, instructions)
  static const Map<String, List<String>> _channelFields = {
    'haram': ['recipient_name', 'recipient_phone'],
    'sham_cash': ['account_number'], // qr_image_url منفصل
    'syriatel_cash': ['number'],
    // 2026-08-14: قناة تحويل الرصيد صارت برقم واحد موحّد = رقم المكتب،
    // ويُحرَّر من بطاقة «رقم المكتب» أعلى الشاشة لا من حقول القناة.
    'balance': [],
    'bank': [
      'bank_name',
      'account_holder',
      'account_number',
      'iban',
      'branch',
    ],
  };

  static const Map<String, String> _fieldLabels = {
    'recipient_name': 'اسم المستقبل (ثلاثي)',
    'recipient_phone': 'رقم هاتف المستقبل',
    'account_number': 'رقم الحساب',
    'number': 'رقم التحويل',
    'syriatel_number': 'رقم سيرياتل',
    'mtn_number': 'رقم MTN',
    'bank_name': 'اسم البنك',
    'account_holder': 'اسم صاحب الحساب',
    'iban': 'IBAN',
    'branch': 'الفرع',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final prov = context.read<ConfigProvider>();
    if (prov.config == null) await prov.loadConfig();
    final pay = prov.config?.payChannels ?? {};

    _disposeControllers();
    _channels = {};
    _controllers = {};
    _enabled = {};

    // رقم المكتب: المصدر office.phone، وإن كان فارغاً نقرأ balance.number
    final officeMap = Map<String, dynamic>.from(
        (prov.config?.data['office'] as Map?) ?? <String, dynamic>{});
    final balanceMap = Map<String, dynamic>.from(
        (pay['balance'] as Map?) ?? <String, dynamic>{});
    _officePhoneCtrl.text = (officeMap['phone'] ?? '').toString().trim().isNotEmpty
        ? officeMap['phone'].toString()
        : (balanceMap['number'] ?? '').toString();

    for (final key in _editableChannels) {
      final data =
          Map<String, dynamic>.from(pay[key] ?? <String, dynamic>{});
      _channels[key] = data;
      _enabled[key] = data['enabled'] == true;

      final ctrls = <String, TextEditingController>{};
      for (final f in _channelFields[key] ?? <String>[]) {
        ctrls[f] = TextEditingController(text: (data[f] ?? '').toString());
      }
      ctrls['instructions'] =
          TextEditingController(text: (data['instructions'] ?? '').toString());
      // qr_image_url لشام كاش — حقل خاص (للعرض والتعديل اليدوي إن لزم)
      if (key == 'sham_cash') {
        ctrls['qr_image_url'] = TextEditingController(
            text: (data['qr_image_url'] ?? '').toString());
      }
      _controllers[key] = ctrls;
    }

    if (mounted) setState(() {});
  }

  void _disposeControllers() {
    for (final m in _controllers.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    _officePhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _uploadShamCashQR() async {
    final XFile? file = await _storage.pickImage(fromCamera: false);
    if (file == null) return;

    setState(() => _saving = true);
    try {
      final storage = SupabaseService().storage;
      final fileName = 'sham_cash_qr_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'payment_channels/$fileName';

      final bytes = kIsWeb
          ? await file.readAsBytes()
          : await (await _storage.compressImage(File(file.path)) ??
                  File(file.path))
              .readAsBytes();

      await storage.from(StorageService.configAssetsBucket).uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(cacheControl: '3600', upsert: true),
          );
      final url =
          storage.from(StorageService.configAssetsBucket).getPublicUrl(path);

      setState(() {
        _controllers['sham_cash']!['qr_image_url']!.text = url;
        _saving = false;
      });
      _snack('✅ تم رفع QR بنجاح');
    } catch (e) {
      setState(() => _saving = false);
      _snack('❌ فشل الرفع: $e');
    }
  }

  /// تطبيع رقم سوري لصيغة محلية موحّدة 09xxxxxxxx
  String _normalizeOfficePhone(String phone) {
    final d = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (d.isEmpty) return '';
    if (d.startsWith('963') && d.length == 12) return '0${d.substring(3)}';
    if (d.startsWith('09') && d.length == 10) return d;
    if (d.startsWith('9') && d.length == 9) return '0$d';
    return d;
  }

  /// الحفظ عبر Edge Function `admin-config` (action: update_sections).
  ///
  /// ⚠️ 2026-08-14: كان الحفظ يمر بـ `ConfigProvider.updateConfig` = PATCH مباشر
  /// على app_config بمفتاح anon، وسياسة RLS تشترط `auth.uid()` مع `role >= 6`،
  /// فمدير الهاتف (staff session بلا JWT) كان حفظه **يفشل بصمت** رغم رسالة
  /// النجاح — نفس الدرس الموثّق في §18 من دليل التطوير.
  Future<void> _save() async {
    final officePhone = _normalizeOfficePhone(_officePhoneCtrl.text.trim());
    if (officePhone.isNotEmpty && officePhone.length < 9) {
      _snack('❌ رقم المكتب غير صالح — استخدم صيغة 09xxxxxxxx');
      return;
    }

    setState(() => _saving = true);
    final prov = context.read<ConfigProvider>();

    final payChannels = <String, dynamic>{};
    for (final key in _editableChannels) {
      final existing = <String, dynamic>{};
      existing['enabled'] = _enabled[key] ?? true;
      final ctrls = _controllers[key] ?? {};
      for (final entry in ctrls.entries) {
        existing[entry.key] = entry.value.text.trim();
      }
      payChannels[key] = existing;
    }

    // 📞 رقم المكتب الهاتفي = مصدر واحد للحقيقة:
    // يُكتب في office.phone وفي قناة «تحويل رصيد» (balance.number) معاً،
    // فلا ينحرف ما يراه المستخدم عمّا سجّلته الإدارة.
    final sections = <String, dynamic>{'payChannels': payChannels};
    if (officePhone.isNotEmpty) {
      final balance = Map<String, dynamic>.from(payChannels['balance'] as Map);
      balance['number'] = officePhone;
      if ((balance['instructions'] ?? '').toString().trim().isEmpty) {
        balance['instructions'] =
            'حوّل رصيد الجوال إلى رقم المكتب: $officePhone ثم أدخل رقم العملية وارفع صورة الإشعار.';
      }
      payChannels['balance'] = balance;
      sections['office'] = {'phone': officePhone};
    }

    bool ok = false;
    String err = '';
    try {
      final res = await SupabaseService().invokeFunction('admin-config', body: {
        'action': 'update_sections',
        'admin_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'sections': sections,
      });
      final data = res is Map ? Map<String, dynamic>.from(res) : null;
      ok = data?['success'] == true;
      if (ok && data?['value'] is Map) {
        prov.applyServerConfig(Map<String, dynamic>.from(data!['value'] as Map));
      } else {
        err = data?['error']?.toString() ?? 'UNKNOWN_ERROR';
      }
    } catch (e) {
      ok = false;
      err = e.toString();
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _snack('✅ تم حفظ قنوات الدفع');
      await _load();
    } else {
      _snack('❌ فشل الحفظ — $err');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('💳 قنوات الدفع'),
        backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: _channels.isEmpty
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppTheme.primaryGold))
          : Stack(
              children: [
                ListView(
                  padding: AppTheme.paddingAllLarge,
                  children: [
                    _infoBanner(),
                    AppTheme.gapHeightLarge,
                    _officePhoneCard(),
                    AppTheme.gapHeightLarge,
                    for (final key in _editableChannels)
                      _channelCard(key),
                    AppTheme.gapHeightXL,
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.deepBlack))
                            : const Icon(Icons.save),
                        label: Text(_saving
                            ? 'جارٍ الحفظ...'
                            : 'حفظ جميع التغييرات'),
                        style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
                if (_saving)
                  Container(
                    color: Colors.black.withOpacity(0.4),
                    child: const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryGold),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _infoBanner() => Container(
        padding: AppTheme.paddingAllMedium,
        decoration: BoxDecoration(
          color: AppTheme.infoBlue.withOpacity(0.1),
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: AppTheme.infoBlue.withOpacity(0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.lightBlueAccent),
            AppTheme.gapWidthSmall,
            Expanded(
              child: Text(
                'هذه القنوات تظهر للمستخدمين في شاشة الدفع.\nالقنوات المعطّلة لا تظهر، والحقول الفارغة تخفى تلقائياً.',
                style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall),
              ),
            ),
          ],
        ),
      );

  /// 📞 بطاقة رقم المكتب الهاتفي — وجهة تحويل رصيد الجوال (أُضيفت 2026-08-14)
  Widget _officePhoneCard() => Container(
        padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: AppTheme.primaryGold.withOpacity(0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.phone_in_talk, color: AppTheme.primaryGold),
                AppTheme.gapWidthSmall,
                Expanded(
                  child: Text(
                    'رقم المكتب الهاتفي',
                    style: TextStyle(
                        color: AppTheme.primaryGold,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontSizeSubtitle),
                  ),
                ),
              ],
            ),
            AppTheme.gapHeightSmall,
            const Text(
              'هذا الرقم هو وجهة «تحويل رصيد الجوال» التي تظهر للمستخدم في كل شاشات الدفع '
              '(الباقات • الإعلان المميز • الاستشارة القانونية). تعديله هنا يغيّره فوراً لكل المستخدمين.',
              style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall, height: 1.5),
            ),
            AppTheme.gapHeightMedium,
            TextFormField(
              controller: _officePhoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppTheme.textWhite),
              decoration: const InputDecoration(
                labelText: 'رقم المكتب (09xxxxxxxx)',
                hintText: '0958750199',
                filled: true,
                fillColor: AppTheme.scaffoldBackground,
                prefixIcon: Icon(Icons.phone, color: AppTheme.primaryGold),
              ),
            ),
          ],
        ),
      );

  Widget _channelCard(String key) {
    final data = _channels[key] ?? {};
    final ctrls = _controllers[key] ?? {};
    final icon = (data['icon'] ?? '💳').toString();
    final name = (data['name'] ?? key).toString();
    final enabled = _enabled[key] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: enabled
              ? AppTheme.primaryGold.withOpacity(0.4)
              : AppTheme.textGrey.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: AppTheme.fontSizeLarge)),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: AppTheme.primaryGold,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontSizeSubtitle)),
              ),
              Switch(
                value: enabled,
                activeColor: AppTheme.primaryGold,
                onChanged: (v) => setState(() => _enabled[key] = v),
              ),
            ],
          ),
          const Divider(color: AppTheme.textGrey, height: 18),

          // حقول القناة العامة
          for (final f in _channelFields[key] ?? <String>[])
            _textField(_fieldLabels[f] ?? f, ctrls[f]!),

          // تحويل رصيد: الرقم يأتي من بطاقة «رقم المكتب» أعلى الشاشة
          if (key == 'balance')
            Container(
              padding: AppTheme.paddingAllMedium,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppTheme.infoBlue.withOpacity(0.08),
                borderRadius: AppTheme.radiusSmall,
                border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.infoBlue, size: 18),
                  AppTheme.gapWidthSmall,
                  Expanded(
                    child: Text(
                      'الرقم المعروض للمستخدم = رقم المكتب أعلى الشاشة'
                      '${_officePhoneCtrl.text.trim().isEmpty ? '' : ' (${_officePhoneCtrl.text.trim()})'}.',
                      style: const TextStyle(
                          color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

          // QR لشام كاش
          if (key == 'sham_cash') ...[
            _textField('رابط QR (يدوي)', ctrls['qr_image_url']!),
            AppTheme.gapHeightSmall,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadShamCashQR,
                    icon: const Icon(Icons.qr_code,
                        color: AppTheme.primaryGold),
                    label: const Text('رفع صورة QR',
                        style: TextStyle(color: AppTheme.primaryGold)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppTheme.primaryGold)),
                  ),
                ),
              ],
            ),
            if ((ctrls['qr_image_url']!.text).isNotEmpty) ...[
              AppTheme.gapHeightSmall,
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppTheme.radiusSmall,
                    border: Border.all(
                        color: AppTheme.primaryGold.withOpacity(0.5)),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Image.network(
                    ctrls['qr_image_url']!.text,
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text('فشل تحميل',
                        style: TextStyle(color: AppTheme.errorRed)),
                  ),
                ),
              ),
            ],
          ],

          AppTheme.gapHeightSmall,

          // التعليمات
          _textField('التعليمات (يدعم الأسطر المتعددة)',
              ctrls['instructions']!,
              maxLines: 3),
        ],
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: AppTheme.textWhite),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppTheme.scaffoldBackground,
          labelStyle: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
        ),
      ),
    );
  }
}
