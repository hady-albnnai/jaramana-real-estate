import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/social_account_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin/social_accounts_service.dart';
import '../../widgets/e2e.dart';

/// 📣 شاشة إدارة حسابات النشر الاجتماعي.
///
/// تُضاف الحسابات (صفحات فيسبوك / حسابات إنستغرام المهنية) مع توكناتها من
/// هنا، والنشر التلقائي للعروض (عند قبولها) يوزّع عليها كلها.
///
/// ⚠️ التوكن لا يظهر كاملاً في القائمة أبداً — فقط آخر 4 محارف، لأن الشاشة
/// تعرض ما يعيده السيرفر مقنّعاً (Edge Function: social-accounts).
///
/// خطوات الحصول على التوكن موثقة بالتفصيل في:
/// docs/SOCIAL_ACCOUNTS_MANAGEMENT_2026_08_27.md
class SocialAccountsScreen extends StatefulWidget {
  const SocialAccountsScreen({super.key});

  @override
  State<SocialAccountsScreen> createState() => _SocialAccountsScreenState();
}

class _SocialAccountsScreenState extends State<SocialAccountsScreen> {
  final _service = SocialAccountsService();

  List<SocialAccountModel> _accounts = [];
  bool _loading = true;
  final Set<String> _busyIds = {};

  String get _adminUid => context.read<AuthProvider>().userModel?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final accounts = await _service.list(_adminUid);
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── نافذة الإضافة/التعديل ───

  Future<void> _openEditor({SocialAccountModel? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final externalIdCtrl = TextEditingController(
        text: existing?.accountExternalId ?? '');
    final tokenCtrl = TextEditingController();
    String platform = existing?.platform ?? 'facebook';
    bool isActive = existing?.isActive ?? true;
    bool obscureToken = true;
    bool saving = false;
    String errorText = '';

    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: Text(
            isEdit ? 'تعديل حساب النشر' : 'إضافة حساب نشر جديد',
            style: const TextStyle(
                color: AppTheme.textWhite, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // المنصة
                DropdownButtonFormField<String>(
                  value: platform,
                  dropdownColor: AppTheme.surfaceBlack,
                  decoration: const InputDecoration(
                    labelText: 'المنصة',
                    filled: true,
                    fillColor: AppTheme.inputBackground,
                    prefixIcon: Icon(Icons.share_outlined,
                        color: AppTheme.primaryGold),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'facebook',
                        child: Text('فيسبوك — صفحة')),
                    DropdownMenuItem(
                        value: 'instagram',
                        child: Text('إنستغرام — حساب مهني')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => platform = v);
                  },
                ),
                const SizedBox(height: 12),

                // اسم للعرض
                TextFormField(
                  controller: nameCtrl,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'اسم الحساب (للعرض داخل التطبيق)',
                    hintText: 'مثال: صفحة المكتب العقاري على فيسبوك',
                    filled: true,
                    fillColor: AppTheme.inputBackground,
                    prefixIcon: Icon(Icons.label_outline,
                        color: AppTheme.primaryGold),
                  ),
                ),
                const SizedBox(height: 12),

                // المعرف لدى Meta
                TextFormField(
                  controller: externalIdCtrl,
                  decoration: InputDecoration(
                    labelText: platform == 'facebook'
                        ? 'رقم صفحة فيسبوك (Page ID)'
                        : 'رقم حساب إنستغرام المهني',
                    hintText: platform == 'facebook'
                        ? 'مثال: 61592278445595'
                        : 'مثال: 17841400000000000',
                    filled: true,
                    fillColor: AppTheme.inputBackground,
                    prefixIcon: const Icon(Icons.tag, color: AppTheme.primaryGold),
                    helperText: platform == 'facebook'
                        ? 'رقم الصفحة تجده من صفحتها ← «عن» ← «معرّف الصفحة»'
                        : 'رقم الحساب المهني يظهر عند ربطه بصفحة فيسبوك',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),

                // التوكن
                TextFormField(
                  controller: tokenCtrl,
                  obscureText: obscureToken,
                  maxLines: 1,
                  decoration: InputDecoration(
                    labelText: isEdit
                        ? 'توكن الوصول (اتركه فارغاً للإبقاء على الحالي)'
                        : 'توكن الوصول (Page Access Token طويل الأمد)',
                    hintText: isEdit ? null : 'الصق التوكن هنا',
                    filled: true,
                    fillColor: AppTheme.inputBackground,
                    prefixIcon: const Icon(Icons.key_outlined,
                        color: AppTheme.primaryGold),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureToken
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppTheme.textGrey,
                      ),
                      onPressed: () => setDialogState(
                          () => obscureToken = !obscureToken),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SwitchListTile(
                  value: isActive,
                  onChanged: (v) => setDialogState(() => isActive = v),
                  activeColor: AppTheme.primaryGold,
                  title: const Text('مفعّل للنشر التلقائي',
                      style: TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: AppTheme.fontSizeBody)),
                  subtitle: const Text(
                    'الحساب المعطّل يبقى محفوظاً لكن لا يُنشر عليه.',
                    style: TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: AppTheme.fontSizeCaption),
                  ),
                ),
                if (!isEdit)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: AppTheme.paddingAllSmall,
                    decoration: BoxDecoration(
                      color: AppTheme.infoBlue.withOpacity(0.08),
                      borderRadius: AppTheme.radiusSmall,
                      border: Border.all(
                          color: AppTheme.infoBlue.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'سيتم التحقق من الحساب تلقائياً بعد الحفظ مباشرة.',
                      style: TextStyle(
                          color: AppTheme.textGrey,
                          fontSize: AppTheme.fontSizeCaption),
                    ),
                  ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText,
                    style: const TextStyle(
                        color: AppTheme.errorRed,
                        fontSize: AppTheme.fontSizeSmall),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            E2E(
              id: 'socialAccountSaveBtn',
              button: true,
              child: ElevatedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        final externalId = externalIdCtrl.text.trim();
                        final token = tokenCtrl.text.trim();
                        if (name.isEmpty) {
                          setDialogState(
                              () => errorText = 'اكتب اسماً للحساب.');
                          return;
                        }
                        if (externalId.isEmpty) {
                          setDialogState(() =>
                              errorText = 'اكتب رقم الحساب/الصفحة.');
                          return;
                        }
                        if (!isEdit && token.length < 10) {
                          setDialogState(
                              () => errorText = 'الصق توكن الوصول.');
                          return;
                        }
                        setDialogState(() {
                          saving = true;
                          errorText = '';
                        });
                        final result = await _service.save(
                          adminUid: _adminUid,
                          id: existing?.id,
                          platform: platform,
                          name: name,
                          accountExternalId: externalId,
                          accessToken: token,
                          isActive: isActive,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext, result);
                      },
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(saving ? 'جارٍ الحفظ...' : 'حفظ'),
              ),
            ),
          ],
        ),
      ),
    );

    if (saved == null) return;
    final ok = saved['success'] == true;
    if (ok) {
      final verified = saved['verified'] == true;
      final verifiedName = saved['verifiedName']?.toString() ?? '';
      _snack(verified
          ? '✅ تم الحفظ والتحقق بنجاح: $verifiedName'
          : '⚠️ تم الحفظ لكن التحقق فشل: ${saved['verifyError'] ?? 'خطأ غير معروف'}');
    } else {
      _snack('❌ فشل الحفظ: ${_service.lastError ?? saved['error']}');
    }
    await _load();
  }

  // ─── التحقق اليدوي ───

  Future<void> _verify(SocialAccountModel account) async {
    if (_busyIds.contains(account.id)) return;
    setState(() => _busyIds.add(account.id));
    final result = await _service.verify(_adminUid, account.id);
    if (!mounted) return;
    setState(() => _busyIds.remove(account.id));
    if (result['success'] == true && result['verified'] == true) {
      _snack('✅ التحقق ناجح: ${result['verifiedName'] ?? ''}');
    } else {
      _snack('❌ التحقق فشل: ${result['verifyError'] ?? result['error'] ?? _service.lastError ?? 'خطأ غير معروف'}');
    }
    await _load();
  }

  // ─── الحذف ───

  Future<void> _delete(SocialAccountModel account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: Text('حذف حساب «${account.name}»؟',
            style: const TextStyle(color: AppTheme.textWhite)),
        content: const Text(
          'لن يُنشر على هذا الحساب بعد الآن. سجلّات النشر السابقة تبقى محفوظة.',
          style: TextStyle(color: AppTheme.textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorRed),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await _service.delete(_adminUid, account.id);
    if (!mounted) return;
    _snack(ok ? 'تم حذف الحساب' : '❌ فشل الحذف: ${_service.lastError ?? ''}');
    await _load();
  }

  // ─── الواجهة ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        title: const Text('حسابات النشر الاجتماعي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: E2E(
        id: 'socialAccountAddBtn',
        button: true,
        child: FloatingActionButton.extended(
          onPressed: _loading ? null : () => _openEditor(),
          backgroundColor: AppTheme.primaryGold,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('إضافة حساب'),
        ),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppTheme.primaryGold))
          : RefreshIndicator(
              color: AppTheme.primaryGold,
              onRefresh: _load,
              child: ListView(
                padding: AppTheme.paddingAllLarge,
                children: [
                  _infoBanner(),
                  const SizedBox(height: 16),
                  if (_accounts.isEmpty)
                    _emptyState()
                  else
                    ..._accounts.map(_accountCard),
                  const SizedBox(height: 88), // مساحة لزر الإضافة العائم
                ],
              ),
            ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.primaryGold.withOpacity(0.08),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_outlined,
                  color: AppTheme.primaryGold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'كيف يعمل النشر التلقائي؟',
                  style: const TextStyle(
                    color: AppTheme.textWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTheme.fontSizeMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '• عند قبول المدير لعرض مفعّل به «النشر على السوشيال» يُنشر تلقائياً مع صوره كألبوم على كل الحسابات المفعّلة هنا.\n'
            '• لا نشر بدون صورة عامة واحدة على الأقل (متوافق مع قاعدة إلزام الصور).\n'
            '• التوكن لا يظهر كاملاً بعد حفظه — فقط آخر 4 محارف للتأكد.\n'
            '• تجديد التوكن: عدّل الحساب والصق التوكن الجديد.',
            style: TextStyle(
              color: AppTheme.textGrey,
              fontSize: AppTheme.fontSizeSmall,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.borderGrey),
      ),
      child: Column(
        children: [
          const Icon(Icons.share_outlined,
              size: 48, color: AppTheme.primaryGold),
          const SizedBox(height: 12),
          const Text(
            'لا توجد حسابات نشر بعد',
            style: TextStyle(
              color: AppTheme.textWhite,
              fontWeight: FontWeight.bold,
              fontSize: AppTheme.fontSizeSubtitle,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'أضف صفحة فيسبوكك الأولى بزر «إضافة حساب».\n'
            'تحتاج: رقم الصفحة (Page ID) + توكن وصول طويل الأمد.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textGrey,
              fontSize: AppTheme.fontSizeSmall,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountCard(SocialAccountModel account) {
    final busy = _busyIds.contains(account.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: account.isActive
              ? AppTheme.primaryGold.withOpacity(0.25)
              : AppTheme.borderGrey,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الرأس: المنصة + الاسم + الحالة
          Row(
            children: [
              Icon(
                account.isFacebook
                    ? Icons.facebook
                    : Icons.camera_alt_outlined,
                color: AppTheme.primaryGold,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: const TextStyle(
                        color: AppTheme.textWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontSizeMedium,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${account.platformLabel} • ${account.accountExternalId}',
                      style: const TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: AppTheme.fontSizeCaption,
                      ),
                    ),
                  ],
                ),
              ),
              _statusChip(account),
            ],
          ),

          // الاسم الحقيقي من Meta
          if (account.verifiedName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.verified_outlined,
                    size: 14, color: AppTheme.successGreen),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'الاسم الحقيقي: ${account.verifiedName}',
                    style: const TextStyle(
                      color: AppTheme.successGreen,
                      fontSize: AppTheme.fontSizeCaption,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // التوكن المقنّع
          const SizedBox(height: 6),
          Text(
            'التوكن: ${account.tokenMasked.isEmpty ? '—' : account.tokenMasked} (${account.tokenLength} محرف)',
            style: const TextStyle(
              color: AppTheme.textGrey,
              fontSize: AppTheme.fontSizeCaption,
            ),
          ),

          // آخر خطأ تحقق
          if (account.lastError.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'آخر خطأ: ${account.lastError}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.errorRed,
                fontSize: AppTheme.fontSizeCaption,
              ),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: busy ? null : () => _verify(account),
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('تحقق'),
              ),
              TextButton.icon(
                onPressed: () => _openEditor(existing: account),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('تعديل'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.errorRed),
                onPressed: () => _delete(account),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('حذف'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(SocialAccountModel account) {
    if (!account.isActive) {
      return _chip('معطّل', AppTheme.disabledGrey);
    }
    if (account.isVerified) return _chip('موثّق ✓', AppTheme.successGreen);
    return _chip('غير موثّق', AppTheme.warningOrange);
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: AppTheme.fontSizeCaption,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
