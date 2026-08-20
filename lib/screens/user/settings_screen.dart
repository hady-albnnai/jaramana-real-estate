import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/app_info_service.dart';
import '../../core/utils/social_links.dart';
import '../../widgets/bottom_nav_bar.dart';

/// شاشة الإعدادات
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifOffers = true;
  bool _notifAppointments = true;
  bool _notifFinance = true;
  bool _notifRatings = true;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ntf = auth.userModel?.ntf ?? {};
    setState(() {
      _notifOffers = (ntf['off'] ?? 0) == 0;
      _notifAppointments = (ntf['app'] ?? 0) == 0;
      _notifFinance = (ntf['fin'] ?? 0) == 0;
      _notifRatings = (ntf['rat'] ?? 0) == 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isInternal = auth.userModel?.isInternal ?? false;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: const Text('الإعدادات', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          // قسم الإشعارات
          _sectionTitle('إعدادات الإشعارات', Icons.notifications_outlined),
          if (isInternal) ...[
            // الإدارة: فقط إشعارات المواعيد
            _toggleTile('إشعارات المواعيد', _notifAppointments, (v) => _toggle('app', v)),
          ] else ...[
            // المستخدمون العاديون: كل الإشعارات
            _toggleTile('إشعارات العروض الجديدة', _notifOffers, (v) => _toggle('off', v)),
            _toggleTile('إشعارات المواعيد', _notifAppointments, (v) => _toggle('app', v)),
            _toggleTile('الإشعارات المالية', _notifFinance, (v) => _toggle('fin', v)),
            _toggleTile('التقييمات والتعليقات', _notifRatings, (v) => _toggle('rat', v)),
          ],

          AppTheme.gapHeightXL,

          // قسم الحساب
          _sectionTitle('الحساب', Icons.person_outline_rounded),
          _settingsTile('معلومات الحساب', Icons.person_outline, () => context.push('/user/account-info')),
          _settingsTile('تغيير كلمة المرور', Icons.lock_outline, () => context.push('/user/account-info')),
          if (!isInternal)
            _settingsTile('الباقة الحالية', Icons.card_membership,
                () => context.push('/user/packages')),

          // 🚫 GP-004 (2026-08-15): المستخدمون المحظورون — **متطلب سياسة
          // UGC في Google Play** (حظر + تبليغ معاً). الحظر يُنشأ من صفحة
          // العرض، وهنا مكان مراجعته ورفعه.
          if (!isInternal)
            _settingsTile('المستخدمون المحظورون', Icons.block_outlined,
                () => context.push('/user/blocked-users')),

          // 🗑️ GP-001 (2026-08-14): حذف الحساب — **شرط إلزامي في Google Play**.
          // إقرار Data Safety المرفوع لجوجل ينصّ على «حذف الحساب من داخل
          // التطبيق»، وكانت الميزة غير موجودة إطلاقاً (لا شاشة ولا فعل).
          // الموظفون مستثنَون: إنهاء التعيين قرار إداري لا ذاتي.
          if (!isInternal)
            _settingsTile('حذف الحساب', Icons.delete_forever_outlined,
                () => _showDeleteAccountDialog(),
                danger: true),

          AppTheme.gapHeightXL,

          // قسم التطبيق
          _sectionTitle('التطبيق', Icons.phone_android_outlined),
          // 🔔 BUG-003 (أُصلح 2026-08-14): شاشة «قنوات الإشعارات» كانت مبنية
          // ومسجَّلة بالراوتر **بلا أي زر يفتحها** — المستخدم لا يستطيع ضبط
          // قنواته إطلاقاً رغم أن الشاشة جاهزة.
          _settingsTile('قنوات الإشعارات', Icons.notifications_active_outlined,
              () => context.push('/user/push-channels')),
          _settingsTile('عن التطبيق', Icons.info, () => _showAboutDialog()),

          const SizedBox(height: 30),

          // تسجيل الخروج
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showLogoutDialog(context),
              icon: const Icon(Icons.logout, color: AppTheme.deepBlack),
              label: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                foregroundColor: AppTheme.deepBlack,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),

          AppTheme.gapHeightXL,

          // إصدار التطبيق — من الـAPK نفسه. يُخفى كلياً إن تعذّرت قراءته
          // (لا نعرض رقماً مخترَعاً؛ كان `1.0.0` نصاً ثابتاً وهمياً).
          if (AppInfoService.isReady)
            Center(
              child: Text('الإصدار ${AppInfoService.displayVersion}',
                  style: TextStyle(
                      color: AppTheme.textGrey.withOpacity(0.5),
                      fontSize: AppTheme.fontSizeSmall)),
            ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: auth.userModel?.isInternal == true ? 0 : 5),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 5),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryGold.withOpacity(0.8), size: 18),
          AppTheme.gapWidthSmall,
          Text(title, style: const TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _toggleTile(String title, bool value, Function(bool) onChanged) {
    return Card(
      color: AppTheme.surfaceBlack,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusMedium),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(color: AppTheme.textWhite)),
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.primaryGold,
        activeTrackColor: AppTheme.primaryGold.withOpacity(0.3),
      ),
    );
  }


  /// 🗑️ حوار حذف الحساب — تأكيد من خطوتين (GP-001، 2026-08-14).
  ///
  /// شرط إلزامي في Google Play: يجب أن يستطيع المستخدم حذف حسابه من داخل
  /// التطبيق. الحذف **لا رجعة فيه**، لذا نطلب كتابة كلمة تأكيد صريحة بدل
  /// زر واحد — يمنع الحذف بنقرة خاطئة أو بيد طفل.
  ///
  /// السيرفر يرفض الحذف عند وجود التزام قائم (دفعة قيد المراجعة · صفقة
  /// جارية · استشارة نشطة · موعد قائم) ويعيد سبباً عربياً مفصّلاً نعرضه كما هو.
  Future<void> _showDeleteAccountDialog() async {
    final confirmCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    const confirmWord = 'حذف';

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed),
              AppTheme.gapWidthSmall,
              Text('حذف الحساب نهائياً',
                  style: TextStyle(color: AppTheme.errorRed, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: AppTheme.paddingAllMedium,
                  decoration: BoxDecoration(
                    // 🩹 (2026-08-20): خلفية فاتحة بدل deepBlack (نص أسود على أسود)
                    color: AppTheme.scaffoldBackground,
                    borderRadius: AppTheme.radiusSmall,
                    border: Border.all(color: AppTheme.errorRed.withOpacity(0.4)),
                  ),
                  child: const Text(
                    'سيتم فوراً:\n'
                    '• حذف اسمك ورقمك وبريدك وعنوانك وصور هويتك\n'
                    '• إخفاء كل عروضك وطلباتك\n'
                    '• إنهاء الجلسة على كل أجهزتك\n\n'
                    'لا يمكن التراجع عن هذه الخطوة، ولن تستطيع الدخول بهذا '
                    'الحساب مرة أخرى.',
                    style: TextStyle(
                        color: AppTheme.textWhite,
                        fontSize: AppTheme.fontSizeSmall,
                        height: 1.6),
                  ),
                ),
                AppTheme.gapHeightMedium,
                const Text(
                  'ملاحظة: يتعذّر الحذف إن كان لديك دفعة قيد المراجعة أو صفقة '
                  'جارية أو استشارة نشطة أو موعد قائم.',
                  style: TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: AppTheme.fontSizeCaption,
                      height: 1.5),
                ),
                AppTheme.gapHeightMedium,
                TextField(
                  controller: reasonCtrl,
                  maxLength: 200,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(
                    labelText: 'سبب المغادرة (اختياري)',
                    filled: true,
                    // 🩹 (2026-08-20): فاتح بدل deepBlack حتى يُقرأ المكتوب
                    fillColor: AppTheme.inputBackground,
                  ),
                ),
                AppTheme.gapHeightSmall,
                const Text('للتأكيد اكتب كلمة: حذف',
                    style: TextStyle(
                        color: AppTheme.errorRed,
                        fontSize: AppTheme.fontSizeSmall,
                        fontWeight: FontWeight.bold)),
                AppTheme.gapHeightXXS,
                TextField(
                  controller: confirmCtrl,
                  onChanged: (_) => setDlg(() {}),
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(
                    hintText: 'حذف',
                    filled: true,
                    // 🩹 (2026-08-20): فاتح بدل deepBlack حتى يُقرأ المكتوب
                    fillColor: AppTheme.inputBackground,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('تراجع',
                    style: TextStyle(color: AppTheme.textGrey))),
            TextButton(
              onPressed: confirmCtrl.text.trim() == confirmWord
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: Text('حذف نهائي',
                  style: TextStyle(
                      color: confirmCtrl.text.trim() == confirmWord
                          ? AppTheme.errorRed
                          : AppTheme.textGrey)),
            ),
          ],
        ),
      ),
    );

    if (proceed != true || !mounted) return;

    final auth = context.read<AuthProvider>();
    final uid = auth.userModel?.uid ?? '';
    if (uid.isEmpty) return;

    try {
      final res = await SupabaseService().invokeFunction('user-account', body: {
        'action': 'delete_my_account',
        'user_uid': uid,
        // كلمة التأكيد التي يتوقعها السيرفر ثابتة بالإنكليزية (بروتوكول)
        'confirm': 'DELETE',
        'reason': reasonCtrl.text.trim(),
      });
      final d = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};

      if (d['success'] == true) {
        if (!mounted) return;
        AppTheme.showSnackBar(context,
            const SnackBar(content: Text('تم حذف حسابك. نأسف لمغادرتك.')));
        await auth.logout();
        if (!mounted) return;
        context.go('/user/profile');
        return;
      }

      // 🔒 §13: نعرض سبب الرفض كما أرسله السيرفر — لا رسالة عامة.
      // ACTIVE_OBLIGATIONS يأتي مع تفصيل عربي لكل مانع.
      if (!mounted) return;
      final detail = (d['detail'] ?? '').toString().trim();
      AppTheme.showSnackBar(
        context,
        SnackBar(
          content: Text(detail.isNotEmpty
              ? detail
              : 'تعذّر حذف الحساب — ${d['error'] ?? 'خطأ غير معروف'}'),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      AppTheme.showSnackBar(context,
          const SnackBar(content: Text('تعذّر حذف الحساب — تحقّق من اتصالك')));
    }
  }

  Widget _settingsTile(String title, IconData icon, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? AppTheme.errorRed : AppTheme.primaryGold;
    return Card(
      color: AppTheme.surfaceBlack,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusMedium),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title,
            style: TextStyle(
                color: danger ? AppTheme.errorRed : AppTheme.textWhite)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textGrey),
        onTap: onTap,
      ),
    );
  }

  void _toggle(String key, bool value) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.userModel;
    if (user == null) return;

    final ntf = Map<String, dynamic>.from(user.ntf);
    ntf[key] = value ? 0 : 1;

    try {
      await SupabaseService().invokeFunction('user-notifications', body: {'action': 'update_settings', 'ntf': ntf});
      await auth.refreshUser();

      if (!mounted) return;
      setState(() {
        switch (key) {
          case 'off': _notifOffers = value; break;
          case 'app': _notifAppointments = value; break;
          case 'fin': _notifFinance = value; break;
          case 'rat': _notifRatings = value; break;
        }
      });
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('تم الحفظ ✅'), duration: Duration(seconds: 1)),
      );
    } catch (e) {
      if (mounted) {
        AppTheme.showSnackBar(context,
          const SnackBar(content: Text('فشل الحفظ')),
        );
      }
    }
  }

  /// ℹ️ نافذة «عن التطبيق».
  ///
  /// **مبدأ حاكم (قرار المالك 2026-08-14): صفر قيم مطبوخة بالكود.**
  /// كل نص ورقم ورابط هنا مصدره `app_config` — عدا الإصدار الذي يُقرأ من
  /// الـAPK نفسه (لأن جعله قابلاً للتعديل يسمح بعرض رقم يخالف البناء الفعلي).
  /// أي بند فارغ **يختفي كلياً** بدل أن يعرض قيمة افتراضية.
  ///
  /// ما أُزيل ولماذا:
  ///   • «رقم المطور / المطور الثاني» ← «للتواصل معنا» — التسمية كانت توحي
  ///     بأنها أرقام شركة البرمجة، وكان الرقمان مطبوخين كقيمة افتراضية فلا
  ///     يختفيان عند تفريغ الحقل من الإدارة.
  ///   • «Backend: Supabase • Frontend: Flutter» — كشف بنية تقنية بلا فائدة
  ///     للمستخدم، ويسهّل على مهاجم استهداف الطبقة الصحيحة.
  ///   • «الإصدار: 1.0.0» كنص حرفي — رقم وهمي منفصل عن `pubspec.yaml`.
  void _showAboutDialog() {
    final configProv = Provider.of<ConfigProvider>(context, listen: false);
    final config = configProv.config;

    // ── الروابط الاجتماعية: المعروفة أولاً بترتيب ثابت، ثم الإضافية ──
    // تُدمج `txts.facebook` و`txts.instagram` القديمة مع `txts.socialPages`
    // في خريطة واحدة حتى لا يظهر أي رابط مرتين، ويبقى التوافق مع البيانات
    // المخزَّنة سابقاً (facebook محفوظ حالياً بالمفتاح القديم).
    final socials = <String, String>{};
    void addSocial(String key, String? url) {
      final k = SocialLinks.normalizeKey(key);
      final u = (url ?? '').trim();
      if (k.isEmpty || u.isEmpty) return;
      if (!SocialLinks.isValidUrl(u)) return; // رابط غير آمن ⇒ لا يُعرض
      socials.putIfAbsent(k, () => u);
    }

    addSocial('facebook', config?.facebookPage);
    addSocial('instagram', config?.instagramPage);
    (config?.socialPages ?? {}).forEach((k, v) => addSocial(k, v?.toString()));

    // ترتيب العرض: الشبكات المعروفة بترتيب SocialLinks.known ثم الباقي أبجدياً
    final orderedKeys = <String>[
      ...SocialLinks.known.map((n) => n.key).where(socials.containsKey),
      ...(socials.keys.where((k) => SocialLinks.byKey(k) == null).toList()
        ..sort()),
    ];

    // ── أرقام التواصل ──
    final phone1 = (config?.contactPhone1 ?? '').trim();
    final phone2 = (config?.contactPhone2 ?? '').trim();
    final waRaw = (config?.contactWhatsApp ?? '').trim();
    final waNumber = SocialLinks.toWhatsAppNumber(waRaw);
    final hasContact =
        phone1.isNotEmpty || phone2.isNotEmpty || waNumber.isNotEmpty;

    // ── النصوص التحريرية ──
    final aboutUs = (config?.aboutUsText ?? '').trim();
    final appDesc = (config?.appDescriptionText ?? '').trim();

    // ── الروابط القانونية (شرط نشر Google Play) ──
    final privacyUrl = (config?.privacyPolicyUrl ?? '').trim();
    final termsUrl = (config?.termsUrl ?? '').trim();
    final hasLegal = SocialLinks.isValidUrl(privacyUrl) ||
        SocialLinks.isValidUrl(termsUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('عن التطبيق',
            style: TextStyle(color: AppTheme.primaryGold)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── من نحن — يُحرَّر من الإدارة، يختفي إن فُرِّغ ──
                if (aboutUs.isNotEmpty) ...[
                  _aboutHeading('من نحن'),
                  AppTheme.gapHeightSmall,
                  Text(
                    aboutUs,
                    style: const TextStyle(
                        color: AppTheme.textWhite,
                        fontSize: AppTheme.fontSizeBody,
                        height: 1.5),
                  ),
                  AppTheme.gapHeightXL,
                ],

                // ── تابعنا على ──
                if (orderedKeys.isNotEmpty) ...[
                  _aboutHeading('تابعنا على'),
                  AppTheme.gapHeightSmall,
                  ...orderedKeys.map((k) => _socialLinkTile(
                        SocialLinks.labelFor(k),
                        SocialLinks.iconFor(k),
                        () => _launchUrl(socials[k]!),
                        linkText: socials[k],
                      )),
                  AppTheme.gapHeightLarge,
                ],

                // ── للتواصل معنا ──
                if (hasContact) ...[
                  _aboutHeading('للتواصل معنا'),
                  AppTheme.gapHeightXXS,
                  const Text(
                    'اضغط للاتصال · اضغط مطولاً لنسخ الرقم',
                    style: TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: AppTheme.fontSizeCaption),
                  ),
                  AppTheme.gapHeightSmall,
                  if (phone1.isNotEmpty)
                    _contactPhoneTile('رقم التواصل الأول', phone1),
                  if (phone2.isNotEmpty)
                    _contactPhoneTile('رقم التواصل الثاني', phone2),
                  if (waNumber.isNotEmpty)
                    _whatsAppTile(waNumber),
                  AppTheme.gapHeightLarge,
                ],

                // ── سياسة الخصوصية وشروط الاستخدام ──
                if (hasLegal) ...[
                  _aboutHeading('السياسات'),
                  AppTheme.gapHeightSmall,
                  if (SocialLinks.isValidUrl(privacyUrl))
                    _socialLinkTile('سياسة الخصوصية',
                        Icons.privacy_tip_outlined, () => _launchUrl(privacyUrl),
                        linkText: privacyUrl),
                  if (SocialLinks.isValidUrl(termsUrl))
                    _socialLinkTile('شروط الاستخدام',
                        Icons.description_outlined, () => _launchUrl(termsUrl),
                        linkText: termsUrl),
                  AppTheme.gapHeightLarge,
                ],

                // ── التطوير ──
                _aboutHeading('التطوير'),
                AppTheme.gapHeightLarge,
                // 🩹 م3 (2026-08-20): شعار المطور كان يُعرض مباشرة على خلفية
                // الحوار الداكنة فيظهر أسود بلا تفاصيل — الآن على بطاقة فاتحة
                // بإطار ذهبي فيظهر بكل وضوح مهما كان لون الشعار.
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppTheme.radiusMedium,
                      border: Border.all(color: AppTheme.primaryGold.withOpacity(0.5)),
                    ),
                    child: ClipRRect(
                      borderRadius: AppTheme.radiusSmall,
                      child: Image.asset(
                        'assets/images/loraneem_tech_logo.png',
                        // الصورة أصلها عريضة (1200×520) — contain بلا قص
                        width: 150,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                AppTheme.gapHeightMedium,
                const Center(
                  child: Column(
                    children: [
                      Text(
                        'loraneem-tech',
                        style: TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: AppTheme.fontSizeSubtitle,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      AppTheme.gapHeightXXS,
                      Text(
                        'CODE • AI • LIMITLESS EVOLUTION',
                        style: TextStyle(
                          color: AppTheme.primaryGold,
                          fontSize: AppTheme.fontSizeCaption,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                AppTheme.gapHeightXL,

                // ── وصف التطبيق والإصدار ──
                const Divider(color: Colors.white12),
                AppTheme.gapHeightSmall,
                Text(
                  AppConstants.appName,
                  style: const TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: AppTheme.fontSizeSmall,
                      fontWeight: FontWeight.bold),
                ),
                if (appDesc.isNotEmpty) ...[
                  AppTheme.gapHeightXXS,
                  Text(
                    appDesc,
                    style: const TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: AppTheme.fontSizeSmall),
                  ),
                ],
                // الإصدار من الـAPK — يُخفى إن تعذّرت قراءته بدل عرض رقم مخترَع
                if (AppInfoService.isReady) ...[
                  AppTheme.gapHeightSmall,
                  Text(
                    'الإصدار: ${AppInfoService.displayVersion}',
                    style: TextStyle(
                        color: AppTheme.textGrey.withValues(alpha: 0.7),
                        fontSize: AppTheme.fontSizeCaption),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً',
                  style: TextStyle(color: AppTheme.primaryGold))),
        ],
      ),
    );
  }

  /// عنوان قسم داخل نافذة «عن التطبيق».
  Widget _aboutHeading(String text) => Text(
        text,
        style: const TextStyle(
            color: AppTheme.primaryGold,
            fontSize: AppTheme.fontSizeSubtitle,
            fontWeight: FontWeight.bold),
      );

  /// 📞 بند رقم تواصل — **قابل للضغط**.
  /// كان `Container` أصمّ: يعرض الرقم ويترك المستخدم يحفظه غيباً ويكتبه يدوياً
  /// في تطبيق الهاتف. الآن: نقرة = اتصال، ونقرة مطوّلة = نسخ.
  /// مخطط `tel` مصرَّح به في AndroidManifest ضمن `<queries>` ✅
  Widget _contactPhoneTile(String label, String phone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _launchUrl('tel:$phone'),
        onLongPress: () => _copyToClipboard(phone),
        borderRadius: AppTheme.radiusSmall,
        child: Container(
          padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(
            // 🩹 (2026-08-20): خلفية فاتحة بدل deepBlack حتى يظهر الرقم
            color: AppTheme.inputBackground,
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.phone, color: AppTheme.primaryGold, size: 18),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: AppTheme.textGrey,
                            fontSize: AppTheme.fontSizeCaption)),
                    Text(
                      phone,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: AppTheme.fontSizeBody,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.call, color: AppTheme.textGrey, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// 💬 زر «راسلنا واتساب».
  /// ⚠️ يتطلب `<package android:name="com.whatsapp"/>` داخل `<queries>` في
  /// AndroidManifest، وإلا يُرجع `canLaunchUrl` القيمة false على أندرويد 11+
  /// فيفشل الزر **بصمت** رغم أن واتساب مثبَّت (قيود visibility الحزم).
  Widget _whatsAppTile(String waNumber) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _launchUrl('https://wa.me/$waNumber'),
        onLongPress: () => _copyToClipboard(waNumber),
        borderRadius: AppTheme.radiusSmall,
        child: Container(
          padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(
            // 🩹 (2026-08-20): خلفية فاتحة بدل deepBlack حتى يظهر النص والرقم
            color: AppTheme.inputBackground,
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: AppTheme.successGreen.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline,
                  color: AppTheme.successGreen, size: 18),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'راسلنا على واتساب',
                      style: TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: AppTheme.fontSizeBody,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      waNumber,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                      style: const TextStyle(
                          color: AppTheme.textGrey,
                          fontSize: AppTheme.fontSizeCaption),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, color: AppTheme.textGrey, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppTheme.showSnackBar(
      context,
      const SnackBar(
          content: Text('✅ تم نسخ الرقم'), duration: Duration(seconds: 1)),
    );
  }

  /// بند رابط داخل «عن التطبيق» — الاسم والأيقونة يُشتقّان من SocialLinks.
  /// 🩹 (2026-08-20): الخلفية كانت `deepBlack` من التصميم الغامق القديم
  /// فيصير نص أسود على أسود بعد اعتماد التصميم الفاتح — الآن خلفية فاتحة
  /// بإطار ذهبي، والرابط يُعرض نصاً صغيراً تحت العنوان (قرار المالك).
  Widget _socialLinkTile(String label, IconData icon, VoidCallback onTap,
      {String? linkText}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusSmall,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.inputBackground,
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primaryGold, size: 20),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: AppTheme.fontSizeMedium,
                          fontWeight: FontWeight.w500),
                    ),
                    if (linkText != null && linkText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        linkText,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textGrey,
                            fontSize: AppTheme.fontSizeCaption),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, color: AppTheme.textGrey, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        AppTheme.showSnackBar(context, const SnackBar(content: Text('تعذر فتح الرابط')));
      }
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تسجيل الخروج', style: TextStyle(color: AppTheme.textWhite)),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟', style: TextStyle(color: AppTheme.textGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () {
              Provider.of<AuthProvider>(context, listen: false).logout();
              context.go('/login');
            },
            child: const Text('خروج', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
  }
}
