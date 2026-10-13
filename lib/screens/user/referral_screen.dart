import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';

/// شاشة الإحالة (Referral)
/// كل مستخدم له كود فريد (أول 8 أحرف من uid).
/// عند تسجيل حساب جديد بهذا الكود → الطرفان يحصلان على pts.ref نقاط.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  int _referralCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _codeCtrl.dispose(); // 🎁 REF-001: منع تسريب الذاكرة
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) return;
    try {
      // 🔴 REF-002 (2026-08-15): كان يقرأ `users` عبر REST مباشرةً، وسياسة
      // القراءة `auth.uid() = id` — وجلستنا مخصّصة ⇒ auth.uid()=NULL ⇒
      // النتيجة **null دائماً** فيظهر عدّاد الإحالات صفراً أبداً.
      // الآن عبر الإيدج (مفتاح خدمة) — نفس نمط بقية الشاشات.
      final res = await SupabaseService().invokeFunction('user-account',
          body: {'action': 'get_full_profile', 'user_uid': user.uid});
      final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      final prof = m?['profile'] is Map
          ? Map<String, dynamic>.from(m!['profile'] as Map)
          : null;
      if (!mounted) return;
      setState(() {
        _referralCount = (prof?['ref_cnt'] as int?) ?? 0;
        _alreadyReferred = (prof?['ref_by'] != null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // 🎁 REF-001: حالة إدخال كود المُحيل
  final _codeCtrl = TextEditingController();
  bool _applying = false;
  bool _alreadyReferred = false;

  /// تطبيق كود المُحيل — يمرّ عبر Edge `user-rewards` (مفتاح خدمة) الذي
  /// يستدعي `apply_referral` بعد التحقق من الجلسة.
  Future<void> _applyCode() async {
    final raw = _codeCtrl.text.trim().replaceAll('-', '').toUpperCase();
    if (raw.length < 6) {
      _snack('أدخل كود دعوة صحيح (6 أحرف على الأقل)');
      return;
    }
    final user = context.read<AuthProvider>().userModel;
    if (user == null) return;
    if (raw == _refCode(user.uid)) {
      _snack('لا يمكنك استخدام كودك أنت 🙂');
      return;
    }

    setState(() => _applying = true);
    try {
      final res = await SupabaseService().invokeFunction('user-rewards', body: {
        'action': 'referral',
        'user_uid': user.uid,
        'payload': {'referrer_code': raw},
      });
      final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      // الدالة تُرجع bool: false تعني كوداً غير صالح أو إحالة مستهلَكة.
      final applied = m?['success'] == true && m?['data'] == true;
      if (!mounted) return;
      setState(() => _applying = false);
      if (applied) {
        _codeCtrl.clear();
        await context.read<AuthProvider>().refreshUser();
        if (!mounted) return;
        _snack('🎉 تم تفعيل الكود — أُضيفت النقاط لك وللمُحيل');
        _load();
      } else {
        // §13: نُترجم سبب الرفض بدل رسالة عامة.
        final err = (m?['error'] ?? '').toString();
        _snack(_referralError(err));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      _snack(_referralError(e.toString()));
    }
  }

  String _referralError(String raw) {
    if (raw.contains('Same device')) {
      return 'لا يمكن استخدام كود من نفس الجهاز';
    }
    if (raw.contains('Same IP')) {
      return 'لا يمكن استخدام كود من نفس الشبكة';
    }
    if (raw.contains('RATE_LIMIT')) {
      return 'صاحب الكود بلغ حد الدعوات لهذه الساعة — جرّب لاحقاً';
    }
    return 'الكود غير صالح أو سبق أن استخدمت كود دعوة';
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  String _refCode(String uid) {
    return uid.replaceAll('-', '').substring(0, 8).toUpperCase();
  }

  /// 🔗 رابط الدعوة — يُبنى من `txts.referralBaseUrl` في app_config.
  ///
  /// كان النطاق `https://jaramana-realestate.example/invite?code=` **مطبوخاً بالكود
  /// وهو غير موجود أصلاً** ⇒ كل رابط دعوة يشاركه مستخدم ينتهي بخطأ 404 عند
  /// الطرف الآخر. الآن: إن كان الأساس فارغاً يُرجَع نص فارغ، وتُشارَك رسالة
  /// تحمل **الكود وحده** بلا رابط مكسور. (قرار المالك: صفر قيم افتراضية)
  String _refLink(BuildContext context, String code) {
    final base =
        (context.read<ConfigProvider>().config?.referralBaseUrl ?? '').trim();
    if (base.isEmpty) return '';
    final sep = base.contains('?') ? '&' : '?';
    return '$base${sep}code=$code';
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('✅ تم نسخ الكود'),
            duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _share(String code) async {
    final link = _refLink(context, code);
    // سطر الرابط يُحذف كلياً حين لا يكون هناك أساس رابط مضبوط من الإدارة،
    // فلا تُشارَك رسالة تحمل رابطاً معطوباً.
    final linkLine = link.isEmpty ? '' : '\nأو اضغط الرابط: $link';
    await SharePlus.instance.share(
      ShareParams(
        text:
            'انضم للمكتب العقاري الالكتروني واحصل على نقاط ترحيب! 🎁\n\nاستخدم كود الدعوة: $code$linkLine',
        subject: 'دعوة إلى المكتب العقاري الالكتروني',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final config = context.watch<ConfigProvider>().config;
    final user = auth.userModel;
    final refPts = config?.data['pts']?['ref'] ?? 1500;

    if (user == null) {
      return const Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        body: Center(
            child: Text('سجّل دخولك أولاً',
                style: TextStyle(color: AppTheme.textGrey))),
      );
    }

    final code = _refCode(user.uid);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('دعوة الأصدقاء'),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroCard(refPts),
            AppTheme.gapHeightXL,
            _codeCard(code),
            AppTheme.gapHeightXL,
            // 🎁 REF-001: حقل إدخال كود المُحيل — كان **غائباً كلياً**،
            // فالميزة معلنة (1500 نقطة) ولم تعمل ولا مرة (صفر إحالة بالإنتاج).
            _enterCodeCard(refPts),
            AppTheme.gapHeightXL,
            _statsCard(refPts),
            AppTheme.gapHeightXL,
            _howItWorksCard(refPts),
          ],
        ),
      ),
    );
  }

  /// 🎁 REF-001 — بطاقة إدخال كود المُحيل.
  ///
  /// كانت الميزة معلنة للمستخدم («اربح 1500 نقطة») بلا أي مكان لإدخال
  /// الكود ⇒ صفر إحالة في تاريخ التطبيق كله (مؤكَّد حياً).
  /// تختفي البطاقة بعد استخدام كود — الإحالة تُستهلك مرة واحدة فقط.
  Widget _enterCodeCard(int refPts) {
    if (_alreadyReferred) {
      return Container(
        padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(
          color: AppTheme.successGreen.withOpacity(0.08),
          borderRadius: AppTheme.radiusLarge,
          border: Border.all(color: AppTheme.successGreen.withOpacity(0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.verified, color: AppTheme.successGreen),
          AppTheme.gapWidthSmall,
          const Expanded(
            child: Text('سبق أن استخدمت كود دعوة ✅',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppTheme.textWhite, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }

    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.redeem, color: AppTheme.primaryGold, size: 20),
          AppTheme.gapWidthSmall,
          Expanded(
            child: Text('لديك كود دعوة؟ أدخله واربح $refPts نقطة',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTheme.fontSizeBody)),
          ),
        ]),
        AppTheme.gapHeightSmall,
        const Text('يُستخدم مرة واحدة فقط، وتُضاف النقاط لك ولصاحب الكود.',
            style: TextStyle(
                color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
        AppTheme.gapHeightMedium,
        Row(children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              enabled: !_applying,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              style: const TextStyle(
                  color: AppTheme.textWhite, letterSpacing: 2, fontSize: 16),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'مثال: A1B2C3D4',
                hintStyle: const TextStyle(color: AppTheme.textGrey),
                filled: true,
                fillColor: AppTheme.scaffoldBackground,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: AppTheme.radiusMedium,
                    borderSide: BorderSide(
                        color: AppTheme.primaryGold.withOpacity(0.3))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: AppTheme.radiusMedium,
                    borderSide: BorderSide(
                        color: AppTheme.primaryGold.withOpacity(0.3))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: AppTheme.radiusMedium,
                    borderSide: const BorderSide(color: AppTheme.primaryGold)),
              ),
            ),
          ),
          AppTheme.gapWidthSmall,
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _applying ? null : _applyCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                foregroundColor: AppTheme.deepBlack,
              ),
              child: _applying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.deepBlack))
                  : const Text('تفعيل',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _heroCard(int refPts) {
    return Container(
      padding: AppTheme.paddingAllXL,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryGold, Color(0xFFFFD700)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppTheme.radiusLarge,
      ),
      child: Column(
        children: [
          const Icon(Icons.card_giftcard,
              color: Colors.black87, size: 48),
          AppTheme.gapHeightSmall,
          const Text('ادعُ صديقاً واربحوا معاً!',
              style: TextStyle(
                  color: Colors.black,
                  fontSize: AppTheme.fontSizeHeadline,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            '$refPts نقطة لك + $refPts لصديقك عند تسجيل حسابه',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black87, fontSize: AppTheme.fontSizeBody),
          ),
        ],
      ),
    );
  }

  Widget _codeCard(String code) {
    return Container(
      padding: AppTheme.paddingAllXL,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          const Text('كود الدعوة الخاص بك',
              style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
          AppTheme.gapHeightSmall,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.deepBlack,
              borderRadius: AppTheme.radiusMedium,
              border: Border.all(color: AppTheme.primaryGold),
            ),
            child: Text(
              code,
              style: const TextStyle(
                color: AppTheme.primaryGold,
                fontSize: AppTheme.fontSizeXL,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                fontFamily: 'monospace',
              ),
            ),
          ),
          AppTheme.gapHeightLarge,
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyCode(code),
                  icon: const Icon(Icons.copy,
                      color: AppTheme.primaryGold),
                  label: const Text('نسخ',
                      style: TextStyle(color: AppTheme.primaryGold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryGold),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              AppTheme.gapWidthSmall,
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _share(code),
                  icon: const Icon(Icons.share, color: Colors.black),
                  label: const Text('مشاركة',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsCard(int refPts) {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.people, color: AppTheme.primaryGold, size: 28),
                const SizedBox(height: 6),
                _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryGold))
                    : Text('$_referralCount',
                        style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontSize: AppTheme.fontSizeLarge,
                            fontWeight: FontWeight.bold)),
                const Text('أصدقاء انضمّوا',
                    style: TextStyle(
                        color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
              ],
            ),
          ),
          Container(width: 1, height: 50, color: AppTheme.textGrey),
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.stars,
                    color: AppTheme.primaryGold, size: 28),
                const SizedBox(height: 6),
                Text('${_referralCount * refPts}',
                    style: const TextStyle(
                        color: AppTheme.textWhite,
                        fontSize: AppTheme.fontSizeLarge,
                        fontWeight: FontWeight.bold)),
                const Text('نقطة مكتسبة',
                    style: TextStyle(
                        color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _howItWorksCard(int refPts) {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🎯 كيف يعمل؟',
              style: TextStyle(
                  color: AppTheme.primaryGold,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTheme.fontSizeMedium)),
          AppTheme.gapHeightSmall,
          _step('1', 'شارك كودك مع أصدقائك'),
          _step('2', 'يسجّل صديقك حساب جديد ويدخل الكود'),
          _step('3', 'تحصلان كلاكما على $refPts نقطة فوراً'),
          _step('4', 'النقاط تُضاف لرصيدك تلقائياً'),
        ],
      ),
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppTheme.primaryGold,
            child: Text(num,
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTheme.fontSizeSmall)),
          ),
          AppTheme.gapWidthSmall,
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody)),
          ),
        ],
      ),
    );
  }
}
