import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/network/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/social_links.dart';
import 'payment_channels_editor_screen.dart';

/// ⚙️ محرّر إعدادات التطبيق الديناميكية (app_config / key=main)
/// يعرض القيم الحالية ويسمح بتعديل النقاط/العمولة/الحصص بسرعة.
class ConfigEditorScreen extends StatefulWidget {
  const ConfigEditorScreen({super.key});

  @override
  State<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends State<ConfigEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // متحكّمات الحقول الشائعة
  final _signupPts = TextEditingController();
  final _weeklyPts = TextEditingController();
  final _addOfferPts = TextEditingController();
  final _dealDonePts = TextEditingController();
  final _sellCom = TextEditingController();
  final _userOffersQuota = TextEditingController();
  final _brokerOffersQuota = TextEditingController();

  // ── Video request WhatsApp (مدير + نائب المدير فقط) ──
  final _videoWaNumber = TextEditingController();
  /// رابط تحميل التطبيق — يظهر أسفل منشورات السوشيال (فارغ بانتظار نشر المتجر)
  final _appLinkCtrl = TextEditingController();
  final _videoGroupLink = TextEditingController();

  // ── صفحات التواصل الاجتماعي (قابلة للتوسعة) ──
  final _facebookCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();

  // ── 📞 أرقام التواصل ونصوص «عن التطبيق» (2026-08-14) ──
  // كانت تُسمّى «رقم المطور / المطور الثاني» — تسمية خاطئة توحي بأنها أرقام
  // شركة البرمجة، وكانت قيمتاهما مطبوختين بالكود كافتراضي فلا يختفيان عند
  // تفريغ الحقل. الآن: أرقام تواصل، افتراضها فارغ، والفارغ يُخفي البند.
  final _contactPhone1Ctrl = TextEditingController();
  final _contactPhone2Ctrl = TextEditingController();
  final _contactWhatsAppCtrl = TextEditingController();
  final _aboutUsCtrl = TextEditingController();
  final _appDescCtrl = TextEditingController();
  final _privacyUrlCtrl = TextEditingController();
  final _termsUrlCtrl = TextEditingController();
  final _referralBaseUrlCtrl = TextEditingController();

  final _photoPriceCtrl = TextEditingController();
  // ⚖️ أسعار الاستشارة القانونية ومدة المحادثة (legalPrice) — أُضيفت 2026-08-14
  final _legalPhoneCtrl = TextEditingController();
  final _legalOnsiteCtrl = TextEditingController();
  final _legalRenewCtrl = TextEditingController();
  final _legalDurationCtrl = TextEditingController();
  bool _socialAutoPublish = true; // مفعّل افتراضياً منذ 2026-07-13
  // للصفحات الإضافية: نستخدم قائمة بسيطة (key: label, value: url)
  final List<Map<String, TextEditingController>> _extraSocialCtrls = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final prov = context.read<ConfigProvider>();
    await prov.loadConfig();
    final c = prov.config;
    if (c != null && mounted) {
      setState(() {
        _signupPts.text = '${c.signupPoints}';
        _weeklyPts.text = '${c.weeklyLoginPoints}';
        _addOfferPts.text = '${c.addOfferPoints}';
        _dealDonePts.text = '${c.dealDonePoints}';
        _sellCom.text = '${c.sellCommission}';
        _userOffersQuota.text = '${c.userQuotas['o'] ?? 1}';
        _brokerOffersQuota.text = '${c.brokerQuotas['o'] ?? 5}';

        // Video WhatsApp dedicated + group link (for video requests)
        final txts = c.texts;
        _videoWaNumber.text = (txts['videoRequestWhatsApp'] ?? '').toString();
        _appLinkCtrl.text = (txts['appDownloadLink'] ?? '').toString();
        _videoGroupLink.text = (txts['videoRequestGroupLink'] ?? '').toString();

        // Social pages
        _facebookCtrl.text = c.facebookPage;
        _instagramCtrl.text = c.instagramPage;
        _contactPhone1Ctrl.text = c.contactPhone1;
        _contactPhone2Ctrl.text = c.contactPhone2;
        _contactWhatsAppCtrl.text = c.contactWhatsApp;
        _aboutUsCtrl.text = c.aboutUsText;
        _appDescCtrl.text = c.appDescriptionText;
        _privacyUrlCtrl.text = c.privacyPolicyUrl;
        _termsUrlCtrl.text = c.termsUrl;
        _referralBaseUrlCtrl.text = c.referralBaseUrl;
        _photoPriceCtrl.text = c.photographyPrice.toString();
        _legalPhoneCtrl.text = c.legalPhonePrice.toString();
        _legalOnsiteCtrl.text = c.legalOnsitePrice.toString();
        _legalRenewCtrl.text = c.legalRenewPrice.toString();
        _legalDurationCtrl.text = c.legalDurationMins.toString();
        _socialAutoPublish = c.socialAutoPublish;

        // Extra social pages (socialPages)
        final extra = c.socialPages;
        _extraSocialCtrls.clear();
        extra.forEach((key, val) {
          final labelCtrl = TextEditingController(text: key);
          final urlCtrl = TextEditingController(text: val?.toString() ?? '');
          _extraSocialCtrls.add({'label': labelCtrl, 'url': urlCtrl});
        });
        if (_extraSocialCtrls.isEmpty) {
          _extraSocialCtrls.add({'label': TextEditingController(), 'url': TextEditingController()});
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _signupPts,
      _weeklyPts,
      _addOfferPts,
      _dealDonePts,
      _sellCom,
      _userOffersQuota,
      _brokerOffersQuota,
      _videoWaNumber,
      _videoGroupLink,
      _appLinkCtrl,
      _facebookCtrl,
      _instagramCtrl,
      _contactPhone1Ctrl,
      _contactPhone2Ctrl,
      _contactWhatsAppCtrl,
      _aboutUsCtrl,
      _appDescCtrl,
      _privacyUrlCtrl,
      _termsUrlCtrl,
      _referralBaseUrlCtrl,
      _photoPriceCtrl,
      _legalPhoneCtrl,
      _legalOnsiteCtrl,
      _legalRenewCtrl,
      _legalDurationCtrl,
    ]) {
      c.dispose();
    }
    for (final map in _extraSocialCtrls) {
      map['label']?.dispose();
      map['url']?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ConfigProvider>();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('إعدادات التطبيق'),
        backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: prov.isLoading && prov.config == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : prov.config == null
              ? _error(prov.error)
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: AppTheme.paddingAllLarge,
                    children: [
                      _warning(),
                      AppTheme.gapHeightLarge,
                      _section('⭐ النقاط'),
                      _numField('نقاط التسجيل', _signupPts),
                      _numField('نقاط الدخول الأسبوعي', _weeklyPts),
                      _numField('نقاط إضافة عرض', _addOfferPts),
                      _numField('نقاط إتمام صفقة', _dealDonePts),
                      AppTheme.gapHeightXL,
                      _section('💰 العمولة'),
                      _numField('عمولة البيع (%)', _sellCom),
                      AppTheme.gapHeightXL,
                      _section('📊 الحصص (عدد العروض)'),
                      _numField('حصة المستخدم', _userOffersQuota),
                      _numField('حصة الوسيط', _brokerOffersQuota),
                      AppTheme.gapHeightXL,

                      // ── 🎥 طلبات الفيديو (مدير + نائب المدير فقط)
                      _section('🎥 طلبات الفيديو (خاصة)'),
                      Container(
                        padding: AppTheme.paddingAllMedium,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.infoBlue.withOpacity(0.08),
                          borderRadius: AppTheme.radiusSmall,
                          border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3)),
                        ),
                        child: const Text(
                          '⚠️ هذه الخانتان مخصصتان للمدير ونائب المدير فقط.\n'
                          '• الرقم الأول: الواتساب الخاص بطلبات الفيديو (يفضل).\n'
                          '• الرابط الثاني: مجموعة احتياطية في حال تم حظر الرقم.\n'
                          'يتم استخدامهما تلقائياً بعد حجز الموعد من زر "مشاهدة الفيديو".',
                          style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall, height: 1.45),
                        ),
                      ),
                      TextFormField(
                        controller: _videoWaNumber,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رقم الواتساب المخصص لطلبات الفيديو (09xxxxxxxx أو +963...)',
                          hintText: '0933123456',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon: Icon(Icons.phone, color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightMedium,
                      TextFormField(
                        controller: _appLinkCtrl,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رابط تحميل التطبيق (يُدرج بمنشورات التواصل عند تعبئته)',
                          hintText: 'يُترك فارغاً الآن — يُعبّأ برابط المتجر بعد النشر',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon: Icon(Icons.download, color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightMedium,
                      TextFormField(
                        controller: _videoGroupLink,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رابط المجموعة الاحتياطي (في حال حظر الرقم)',
                          hintText: 'https://chat.whatsapp.com/XXXXX أو wa.me/963...',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon: Icon(Icons.link, color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightXL,

                      // ── 📣 صفحات التواصل الاجتماعي (فيسبوك + إنستغرام + قابلة للتوسعة)
                      _section('📣 صفحات التواصل الاجتماعي'),
                      Container(
                        padding: AppTheme.paddingAllMedium,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.successGreen.withOpacity(0.08),
                          borderRadius: AppTheme.radiusSmall,
                          border: Border.all(color: AppTheme.successGreen.withOpacity(0.3)),
                        ),
                        child: const Text(
                          '• روابط الصفحات الرسمية تظهر في "عن التطبيق".\n'
                          '• يمكنك إضافة صفحات جديدة (تيك توك، إلخ).\n'
                          '• النشر التلقائي يعتمد على i_soc في العرض + socTxt الجاهز.',
                          style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall, height: 1.4),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBlack,
                          borderRadius: AppTheme.radiusMedium,
                          border: Border.all(color: AppTheme.infoBlue.withOpacity(0.35)),
                        ),
                        child: SwitchListTile(
                          value: _socialAutoPublish,
                          onChanged: (value) => setState(() => _socialAutoPublish = value),
                          activeColor: AppTheme.primaryGold,
                          secondary: const Icon(Icons.auto_awesome, color: AppTheme.infoBlue),
                          title: const Text('النشر التلقائي فور قبول العرض',
                              style: TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
                          subtitle: const Text(
                            'عند تعطيله يبقى العرض في قائمة «جاهز للنشر» ويُنشر من الزر اليدوي.',
                            style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
                          ),
                        ),
                      ),
                      TextFormField(
                        controller: _facebookCtrl,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رابط صفحة فيسبوك الرسمية',
                          hintText: 'https://facebook.com/sweeda.realestate',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon: Icon(Icons.facebook, color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightMedium,
                      TextFormField(
                        controller: _instagramCtrl,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رابط حساب إنستغرام الرسمي',
                          hintText: 'https://instagram.com/sweeda.realestate',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon: Icon(Icons.camera_alt, color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightMedium,
                      AppTheme.gapHeightMedium,
                      // 📸 أجر خدمة التصوير العقاري — يظهر للمستخدم بشاشة الخدمة
                      TextFormField(
                        controller: _photoPriceCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'أجر خدمة التصوير العقاري (ل.س)',
                          hintText: '1000 — اكتب 0 لجعل الخدمة مجانية',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon: Icon(Icons.payments_outlined,
                              color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightLarge,
                      const Text(
                        'صفحات تواصل إضافية — اختر الشبكة ثم الصق الرابط:',
                        style: TextStyle(
                            color: AppTheme.textGrey,
                            fontSize: AppTheme.fontSizeSmall),
                      ),
                      AppTheme.gapHeightXXS,
                      const Text(
                        'الأيقونة والاسم العربي يُضافان تلقائياً حسب الشبكة المختارة.',
                        style: TextStyle(
                            color: AppTheme.textGrey,
                            fontSize: AppTheme.fontSizeCaption),
                      ),
                      AppTheme.gapHeightSmall,
                      // 🌐 قائمة منسدلة بدل حقل نصي حر (2026-08-14):
                      // الحقل الحر كان ينتج مفاتيح مثل «tik tok» أو «TikTok»
                      // فتفشل مطابقة الأيقونة وتظهر كل الصفحات بأيقونة رابط
                      // رمادية واحدة، والاسم يظهر إنكليزياً وسط واجهة عربية.
                      ..._extraSocialCtrls.map((ctrls) {
                        final currentKey =
                            SocialLinks.normalizeKey(ctrls['label']!.text);
                        final isKnown = SocialLinks.byKey(currentKey) != null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child:
                                        DropdownButtonFormField<String>(
                                      value: isKnown ? currentKey : null,
                                      isExpanded: true,
                                      dropdownColor: AppTheme.surfaceBlack,
                                      style: const TextStyle(
                                          color: AppTheme.textWhite),
                                      decoration: const InputDecoration(
                                        labelText: 'الشبكة',
                                        filled: true,
                                        fillColor: AppTheme.surfaceBlack,
                                        isDense: true,
                                      ),
                                      items: SocialLinks.known
                                          .map((n) => DropdownMenuItem(
                                                value: n.key,
                                                child: Row(
                                                  children: [
                                                    Icon(n.icon,
                                                        size: 16,
                                                        color: AppTheme
                                                            .primaryGold),
                                                    AppTheme.gapWidthSmall,
                                                    Flexible(
                                                        child: Text(n.label,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis)),
                                                  ],
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() {
                                          ctrls['label']!.text = v;
                                        });
                                      },
                                    ),
                                  ),
                                  AppTheme.gapWidthSmall,
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: ctrls['url']!,
                                      style: const TextStyle(
                                          color: AppTheme.textWhite),
                                      textDirection: TextDirection.ltr,
                                      validator: SocialLinks.validateOptionalUrl,
                                      decoration: InputDecoration(
                                        hintText: SocialLinks.byKey(currentKey)
                                                ?.hint ??
                                            'https://…',
                                        filled: true,
                                        fillColor: AppTheme.surfaceBlack,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle,
                                        color: AppTheme.errorRed),
                                    onPressed: () {
                                      setState(() {
                                        _extraSocialCtrls.remove(ctrls);
                                        if (_extraSocialCtrls.isEmpty) {
                                          _extraSocialCtrls.add({
                                            'label': TextEditingController(),
                                            'url': TextEditingController()
                                          });
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _extraSocialCtrls.add({'label': TextEditingController(), 'url': TextEditingController()});
                          });
                        },
                        icon: const Icon(Icons.add, color: AppTheme.primaryGold),
                        label: const Text('إضافة صفحة تواصل جديدة', style: TextStyle(color: AppTheme.primaryGold)),
                      ),
                      AppTheme.gapHeightXL,

                      // ── ℹ️ نافذة «عن التطبيق» (أُضيف 2026-08-14) ──
                      // كل ما يظهر بالنافذة يُحرَّر من هنا. القاعدة: **الفارغ
                      // يُخفي البند كلياً** — لا قيمة افتراضية مطبوخة بالكود.
                      // سابقاً كانت فقرة «من نحن» ووصف التطبيق محبوسين في
                      // settings_screen.dart، فتعديل كلمة واحدة = إعادة بناء
                      // كاملة (ساعة على جهاز المالك).
                      _section('ℹ️ نافذة «عن التطبيق»'),
                      Container(
                        padding: AppTheme.paddingAllMedium,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBlack,
                          borderRadius: AppTheme.radiusMedium,
                          border: Border.all(
                              color: AppTheme.infoBlue.withOpacity(0.35)),
                        ),
                        child: const Text(
                          'أي حقل تتركه فارغاً يختفي من النافذة تماماً.\n'
                          'رقم الإصدار غير قابل للتعديل — يُقرأ من التطبيق نفسه.',
                          style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: AppTheme.fontSizeCaption,
                              height: 1.5),
                        ),
                      ),
                      TextFormField(
                        controller: _aboutUsCtrl,
                        maxLines: 5,
                        maxLength: 1500,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'فقرة «من نحن»',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                        ),
                      ),
                      AppTheme.gapHeightMedium,
                      TextFormField(
                        controller: _appDescCtrl,
                        maxLines: 2,
                        maxLength: 300,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'وصف التطبيق المختصر',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                        ),
                      ),
                      AppTheme.gapHeightMedium,

                      // 📞 أرقام التواصل — كانت تُسمّى «رقم المطور»
                      TextFormField(
                        controller: _contactPhone1Ctrl,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        validator: SocialLinks.validateOptionalPhone,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رقم التواصل الأول',
                          hintText: '0933123456 — اتركه فارغاً لإخفائه',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon:
                              Icon(Icons.phone, color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightMedium,
                      TextFormField(
                        controller: _contactPhone2Ctrl,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        validator: SocialLinks.validateOptionalPhone,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رقم التواصل الثاني',
                          hintText: '0938123456 — اتركه فارغاً لإخفائه',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon:
                              Icon(Icons.phone, color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightMedium,
                      TextFormField(
                        controller: _contactWhatsAppCtrl,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        validator: SocialLinks.validateOptionalPhone,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رقم واتساب التواصل',
                          hintText: '0958750199 — يظهر كزر «راسلنا على واتساب»',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon: Icon(Icons.chat_bubble_outline,
                              color: AppTheme.successGreen),
                        ),
                      ),
                      AppTheme.gapHeightMedium,

                      // ⚖️ روابط قانونية — سياسة الخصوصية شرط نشر في Google Play
                      TextFormField(
                        controller: _privacyUrlCtrl,
                        textDirection: TextDirection.ltr,
                        validator: SocialLinks.validateOptionalUrl,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رابط سياسة الخصوصية',
                          hintText: 'https://… (مطلوب لنشر التطبيق على المتجر)',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon: Icon(Icons.privacy_tip_outlined,
                              color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightMedium,
                      TextFormField(
                        controller: _termsUrlCtrl,
                        textDirection: TextDirection.ltr,
                        validator: SocialLinks.validateOptionalUrl,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'رابط شروط الاستخدام',
                          hintText: 'https://…',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon: Icon(Icons.description_outlined,
                              color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightMedium,
                      // 🔗 أساس رابط الإحالة — كان نطاقاً وهمياً مطبوخاً بالكود
                      // (`sweeda-realestate.com`) لا وجود له، فكل رابط دعوة
                      // يُشارَك ينتهي بخطأ 404. الفارغ الآن يعرض الكود وحده.
                      TextFormField(
                        controller: _referralBaseUrlCtrl,
                        textDirection: TextDirection.ltr,
                        validator: SocialLinks.validateOptionalUrl,
                        style: const TextStyle(color: AppTheme.textWhite),
                        decoration: const InputDecoration(
                          labelText: 'أساس رابط الإحالة',
                          hintText:
                              'https://example.com/invite — فارغ = يُعرض الكود وحده',
                          filled: true,
                          fillColor: AppTheme.surfaceBlack,
                          prefixIcon:
                              Icon(Icons.share_outlined, color: AppTheme.primaryGold),
                        ),
                      ),
                      AppTheme.gapHeightXL,

                      // ── ⚖️ أسعار الاستشارة القانونية (أُضيف 2026-08-14) ──
                      _section('⚖️ أسعار الاستشارة القانونية'),
                      Container(
                        padding: AppTheme.paddingAllMedium,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.infoBlue.withOpacity(0.08),
                          borderRadius: AppTheme.radiusSmall,
                          border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'تُطبَّق فوراً على كل الشاشات (الرئيسية • بطاقات الاستشارة • شاشة الدفع • المحادثة)\n'
                          'والسيرفر يرفض أي دفعة بسعر مخالف — فالتعديل هنا هو المصدر الوحيد للسعر.',
                          style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall, height: 1.45),
                        ),
                      ),
                      _numField('سعر الاستشارة الهاتفية (ل.س)', _legalPhoneCtrl),
                      _numField('سعر الجلسة الحضورية (ل.س)', _legalOnsiteCtrl),
                      _numField('سعر تجديد المحادثة (ل.س)', _legalRenewCtrl),
                      _numField('مدة المحادثة (دقيقة)', _legalDurationCtrl),
                      AppTheme.gapHeightXL,

                      _section('💳 قنوات الدفع'),
                      _navTile(
                        icon: Icons.payments,
                        title: 'إدارة قنوات الدفع',
                        subtitle: 'الهرم • شام كاش • تحويل رصيد • بنكي',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const PaymentChannelsEditorScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppTheme.deepBlack))
                              : const Icon(Icons.save),
                          label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات'),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _warning() => Container(
        padding: AppTheme.paddingAllMedium,
        decoration: BoxDecoration(
          color: AppTheme.warningOrange.withOpacity(0.12),
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: AppTheme.warningOrange.withOpacity(0.5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.warning_amber, color: AppTheme.warningOrange),
            AppTheme.gapWidthSmall,
            Expanded(
              child: Text(
                'هذه القيم تؤثّر على كل المستخدمين فوراً. عدّل بحذر.',
                style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSmall),
              ),
            ),
          ],
        ),
      );

  Widget _error(String? msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.paddingXXL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 48),
              AppTheme.gapHeightMedium,
              Text(msg ?? 'تعذّر تحميل الإعدادات',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textGrey)),
              AppTheme.gapHeightLarge,
              ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: const TextStyle(
                color: AppTheme.primaryGold,
                fontSize: AppTheme.fontSizeSubtitle,
                fontWeight: FontWeight.bold)),
      );

  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryGold),
        title: Text(title,
            style: const TextStyle(
                color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
        trailing: const Icon(Icons.arrow_forward_ios,
            color: AppTheme.primaryGold, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _numField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: AppTheme.textWhite),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppTheme.surfaceBlack,
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'مطلوب';
          if (num.tryParse(v.trim()) == null) return 'رقم غير صالح';
          return null;
        },
      ),
    );
  }

  /// حفظ قيمتي واتساب الفيديو عبر Edge Function `admin-config` (action: update_texts).
  /// invokeFunction يحقن staff_session_token وadmin_uid تلقائياً لدوال admin-*.
  Future<bool> _saveVideoTexts() async {
    try {
      final res = await SupabaseService().invokeFunction('admin-config', body: {
        'action': 'update_texts',
        'texts': {
          'videoRequestWhatsApp': _videoWaNumber.text.trim(),
          'videoRequestGroupLink': _videoGroupLink.text.trim(),
          'appDownloadLink': _appLinkCtrl.text.trim(),
        },
      });
      final d = res.data;
      return d is Map && d['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // ── حفظ رقم/رابط واتساب الفيديو عبر admin-config (service_role) ──
    // الكتابة المباشرة على app_config مرفوضة بسياسة RLS لجلسات الهاتف (لا يوجد auth.uid)،
    // لذا تُحفظ هاتان القيمتان عبر الدالة الجديدة كي يعمل تعديلهما من التطبيق
    // للمدير/النائب (دخول هاتف) — مؤكد حياً 2026-07-26 أن المسار القديم كان يفشل بصمت.
    final videoSaved = await _saveVideoTexts();
    if (!videoSaved) {
      if (mounted) {
        setState(() => _saving = false);
        AppTheme.showSnackBar(context, const SnackBar(
            content: Text('❌ فشل حفظ رقم/رابط واتساب الفيديو — تأكد أنك مدير/نائب وأن دالة admin-config منشورة')));
      }
      return;
    }

    final prov = context.read<ConfigProvider>();
    // ندمج التعديلات فوق نسخة من الـ config الحالي للحفاظ على باقي المفاتيح
    final current = Map<String, dynamic>.from(prov.config?.data ?? {});

    final pts = Map<String, dynamic>.from(current['pts'] ?? {});
    pts['sgn'] = int.tryParse(_signupPts.text.trim()) ?? pts['sgn'];
    pts['wkL'] = int.tryParse(_weeklyPts.text.trim()) ?? pts['wkL'];
    pts['addO'] = int.tryParse(_addOfferPts.text.trim()) ?? pts['addO'];
    pts['dlD'] = int.tryParse(_dealDonePts.text.trim()) ?? pts['dlD'];
    current['pts'] = pts;

    final com = Map<String, dynamic>.from(current['com'] ?? {});
    com['sl'] = num.tryParse(_sellCom.text.trim()) ?? com['sl'];
    current['com'] = com;

    final qta = Map<String, dynamic>.from(current['qta'] ?? {});
    final qtaU = Map<String, dynamic>.from(qta['u'] ?? {});
    qtaU['o'] = int.tryParse(_userOffersQuota.text.trim()) ?? qtaU['o'];
    qta['u'] = qtaU;
    final qtaB = Map<String, dynamic>.from(qta['b'] ?? {});
    qtaB['o'] = int.tryParse(_brokerOffersQuota.text.trim()) ?? qtaB['o'];
    qta['b'] = qtaB;
    current['qta'] = qta;

    // ── حفظ حقول طلبات الفيديو (مدير + نائب) ──
    final txts = Map<String, dynamic>.from(current['txts'] ?? {});
    txts['videoRequestWhatsApp'] = _videoWaNumber.text.trim();
    txts['videoRequestGroupLink'] = _videoGroupLink.text.trim();

    // ── حفظ صفحات التواصل الاجتماعي ──
    txts['facebook'] = _facebookCtrl.text.trim();
    txts['instagram'] = _instagramCtrl.text.trim();

    // 📞 أرقام التواصل ونصوص «عن التطبيق» — الفارغ مسموح ويعني «أخفِ البند».
    // المفتاحان القديمان developerPhone/developerPhone2 يُمسحان صراحةً حتى لا
    // يبقيا في app_config بعد الترحيل (السيرفر يدمج ولا يستبدل).
    txts['contactPhone1'] = _contactPhone1Ctrl.text.trim();
    txts['contactPhone2'] = _contactPhone2Ctrl.text.trim();
    txts['contactWhatsApp'] = _contactWhatsAppCtrl.text.trim();
    txts['aboutUs'] = _aboutUsCtrl.text.trim();
    txts['appDescription'] = _appDescCtrl.text.trim();
    txts['privacyPolicyUrl'] = _privacyUrlCtrl.text.trim();
    txts['termsUrl'] = _termsUrlCtrl.text.trim();
    txts['referralBaseUrl'] = _referralBaseUrlCtrl.text.trim();
    txts.remove('developerPhone');
    txts.remove('developerPhone2');

    // صفحات إضافية — المفتاح يُوحَّد عبر SocialLinks حتى تُشتقّ الأيقونة
    // والاسم العربي تلقائياً، فلا تظهر كلها بأيقونة رابط رمادية واحدة.
    final extraSocial = <String, dynamic>{};
    for (final map in _extraSocialCtrls) {
      final lbl = SocialLinks.normalizeKey(map['label']!.text);
      final url = map['url']!.text.trim();
      if (lbl.isNotEmpty && url.isNotEmpty) {
        extraSocial[lbl] = url;
      }
    }
    txts['socialPages'] = extraSocial;

    current['txts'] = txts;
    final socialPublishing = Map<String, dynamic>.from(
        current['socialPublishing'] ?? <String, dynamic>{});
    socialPublishing['autoPublish'] = _socialAutoPublish;
    current['socialPublishing'] = socialPublishing;

    // 📸 أجر خدمة التصوير العقاري (ل.س) — 0 يجعل الخدمة مجانية فيُخفى الأجر.
    final photoPrice = int.tryParse(_photoPriceCtrl.text.trim()) ?? 1000;
    current['photoPrice'] = photoPrice;

    // ⚖️ أسعار الاستشارة القانونية ومدة المحادثة (2026-08-14)
    final legalPrice = <String, dynamic>{
      'phone': int.tryParse(_legalPhoneCtrl.text.trim()) ?? 500,
      'onsite': int.tryParse(_legalOnsiteCtrl.text.trim()) ?? 2000,
      'renew': int.tryParse(_legalRenewCtrl.text.trim()) ?? 500,
      'durationMins': int.tryParse(_legalDurationCtrl.text.trim()) ?? 15,
    };
    current['legalPrice'] = legalPrice;

    // ⚠️ الحفظ يمر عبر الإيدج بمفتاح الخدمة إلزامياً:
    // الكتابة المباشرة على app_config يرفضها السيرفر (42501) لأن anon لا يملك
    // UPDATE — فكان زر الحفظ معطّلاً فعلياً رغم رسالة النجاح. (أُصلح 2026-07-29)
    // نرسل الأقسام المسموحة فقط، والسيرفر يدمجها مع الموجود بلا فقدان مفاتيح.
    bool ok = false;
    try {
      final res = await SupabaseService().invokeFunction('admin-config', body: {
        'action': 'update_sections',
        'admin_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'sections': {
          'pts': pts,
          'com': com,
          'qta': qta,
          'txts': txts,
          'socialPublishing': socialPublishing,
          'photoPrice': photoPrice,
          'legalPrice': legalPrice,
        },
      });
      ok = (res is Map && res['success'] == true);
      // تحديث الحالة محلياً من القيمة التي أعادها السيرفر (المصدر الموثوق)
      if (ok && res['value'] is Map) {
        prov.applyServerConfig(Map<String, dynamic>.from(res['value'] as Map));
      }
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      setState(() => _saving = false);
      AppTheme.showSnackBar(context,
        SnackBar(content: Text(ok ? 'تم حفظ الإعدادات ✅' : 'فشل الحفظ ❌')),
      );
    }
  }
}
