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

          AppTheme.gapHeightXL,

          // قسم التطبيق
          _sectionTitle('التطبيق', Icons.phone_android_outlined),
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

  Widget _settingsTile(String title, IconData icon, VoidCallback onTap) {
    return Card(
      color: AppTheme.surfaceBlack,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusMedium),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryGold),
        title: Text(title, style: const TextStyle(color: AppTheme.textWhite)),
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
                        Icons.privacy_tip_outlined, () => _launchUrl(privacyUrl)),
                  if (SocialLinks.isValidUrl(termsUrl))
                    _socialLinkTile('شروط الاستخدام',
                        Icons.description_outlined, () => _launchUrl(termsUrl)),
                  AppTheme.gapHeightLarge,
                ],

                // ── التطوير ──
                _aboutHeading('التطوير'),
                AppTheme.gapHeightLarge,
                Center(
                  child: ClipRRect(
                    borderRadius: AppTheme.radiusMedium,
                    child: Image.asset(
                      'assets/images/loraneem_tech_logo.png',
                      // الصورة أصلها عريضة (1200×520) — contain بلا قص
                      width: 150,
                      fit: BoxFit.contain,
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
            color: AppTheme.deepBlack,
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: AppTheme.primaryGold.withOpacity(0.25)),
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
            color: AppTheme.deepBlack,
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: AppTheme.successGreen.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline,
                  color: AppTheme.successGreen, size: 18),
              AppTheme.gapWidthSmall,
              const Expanded(
                child: Text(
                  'راسلنا على واتساب',
                  style: TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: AppTheme.fontSizeBody,
                      fontWeight: FontWeight.w600),
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
  /// الرابط نفسه لا يُعرض نصاً (يزحم الواجهة وقد يكون طويلاً جداً).
  Widget _socialLinkTile(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusSmall,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.deepBlack,
            borderRadius: AppTheme.radiusSmall,
            border: Border.all(color: AppTheme.primaryGold.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primaryGold, size: 20),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: AppTheme.fontSizeMedium,
                      fontWeight: FontWeight.w500),
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
