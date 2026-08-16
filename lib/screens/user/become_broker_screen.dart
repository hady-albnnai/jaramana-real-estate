import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../core/network/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_utils.dart';

/// شاشة التقدّم لتصبح وسيطاً
/// يرسل طلب للإدارة (sts=0) وتراجعه الإدارة لاحقاً
class BecomeBrokerScreen extends StatefulWidget {
  const BecomeBrokerScreen({super.key});

  @override
  State<BecomeBrokerScreen> createState() => _BecomeBrokerScreenState();
}

class _BecomeBrokerScreenState extends State<BecomeBrokerScreen> {
  final _businessNameCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  int _category = 0; // 0=عقارات, 1=سيارات, 2=كلاهما
  bool _agreeTerms = false;
  bool _submitting = false;

  static const Map<int, String> _categories = {
    0: 'عقارات فقط',
    1: 'سيارات فقط',
    2: 'عقارات + سيارات',
  };

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _experienceCtrl.dispose();
    _aboutCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) {
      _snack('يجب تسجيل الدخول أولاً');
      return;
    }

    if (_businessNameCtrl.text.trim().isEmpty) {
      _snack('يرجى إدخال الاسم التجاري');
      return;
    }
    // ✅ Fix for Bug #30: التحقق من التوثيق الرسمي بدلاً من sid/img فقط
    // إذا كان المستخدم موثق بالفعل (vrf=2)، لا داعي لطلب الهوية مرة أخرى
    if (!user.isVerifiedOfficial) {
      // إذا كان المستخدم رفع هويته لكنها قيد المراجعة
      if (user.sid.isNotEmpty && user.img.isNotEmpty) {
        _snack('هويتك قيد المراجعة من الإدارة. سيتم إشعارك عند الموافقة.');
        return;
      }
      // إذا كان المستخدم لم يرفع هويته بعد
      _snack('التوثيق إلزامي للوسطاء: يجب رفع صورة الهوية + الرقم الوطني أولاً');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) context.push('/setup-identity');
      });
      return;
    }
    if (!_agreeTerms) {
      _snack('يرجى الموافقة على الشروط والالتزامات');
      return;
    }

    setState(() => _submitting = true);

    try {
      // ✅ Secure via broker-actions Edge Function (submit_request)
      final res = await SupabaseService().invokeFunction(
        'broker-actions',
        body: {
          'action': 'submit_request',
          'user_uid': user.uid,
          'business_name': _businessNameCtrl.text.trim(),
          'category': _category,
          'experience': _experienceCtrl.text.trim(),
          'about': _aboutCtrl.text.trim(),
        },
      );

      // §13: كان الرد يُتجاهل تماماً ⇒ يظهر «تم الإرسال ✅» حتى عند فشل
      // السيرفر (مثلاً: قيد CHECK رفض الحالة، أو طلب مكرر) والمستخدم
      // ينتظر رداً لن يأتي لأن الطلب لم يُسجَّل أصلاً.
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
      if (data == null || data['success'] != true) {
        if (!mounted) return;
        setState(() => _submitting = false);
        _snack(ErrorUtils.arabicMessage(data?['error'] ?? 'UNKNOWN_ERROR'));
        return;
      }

      await auth.refreshUser();

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.successGreen, size: 28),
              AppTheme.gapWidthSmall,
              Text('تم إرسال الطلب',
                  style: TextStyle(color: AppTheme.textWhite)),
            ],
          ),
          content: const Text(
            'تم إرسال طلبك للإدارة بنجاح ✅\n\n'
            'ستراجع الإدارة طلب الوساطة + توثيق هويتك معاً، وسيصلك إشعار بالنتيجة. '
            'عادة خلال 48 ساعة.',
            style: TextStyle(color: AppTheme.textGrey),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/user/home');
              },
              child: const Text('حسناً',
                  style: TextStyle(color: AppTheme.primaryGold)),
            ),
          ],
        ),
      );
    } catch (e) {_snack('حدث خطأ، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String m) =>
      AppTheme.showSnackBar(context, SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().userModel;
    final isAlreadyBroker = user?.isBroker == true;
    // 🤝 BRK-001: كان الاستدلال على «طلب معلّق» بوجود `brkNm` — وهو غير
    // دقيق (الاسم يبقى محفوظاً بعد الرفض أيضاً). الآن الحالة صريحة من
    // السيرفر: brk=2 قيد المراجعة · brk=3 مرفوض.
    final hasPendingRequest = user?.isBrokerPending == true;
    final isNotVerified = user != null && !user.isVerifiedOfficial;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('انضم كوسيط'),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroCard(),
            AppTheme.gapHeightXL,
            if (isAlreadyBroker)
              _alreadyBrokerCard()
            else if (isNotVerified)
              _verificationRequiredCard()
            else if (hasPendingRequest)
              _pendingCard()
            else
              _form(),
          ],
        ),
      ),
    );
  }

  Widget _heroCard() {
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
      child: const Column(
        children: [
          Icon(Icons.handshake, color: Colors.black87, size: 48),
          AppTheme.gapHeightSmall,
          Text('كن جزءاً من شبكة وسطائنا',
              style: TextStyle(
                  color: Colors.black,
                  fontSize: AppTheme.fontSizeTitle,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text(
            'صلاحيات أوسع لإدراج العروض، أولوية بالظهور، ولوحة تحكم خاصة بإدارتك.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black87, fontSize: AppTheme.fontSizeBody),
          ),
        ],
      ),
    );
  }

  Widget _alreadyBrokerCard() {
    return Container(
      padding: AppTheme.paddingAllXL,
      decoration: BoxDecoration(
        color: AppTheme.successGreen.withOpacity(0.1),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.successGreen),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified, color: AppTheme.successGreen, size: 48),
          AppTheme.gapHeightSmall,
          const Text('أنت وسيط مفعّل ✅',
              style: TextStyle(
                  color: AppTheme.successGreen,
                  fontSize: AppTheme.fontSizeTitle,
                  fontWeight: FontWeight.bold)),
          AppTheme.gapHeightLarge,
          ElevatedButton.icon(
            onPressed: () => context.go('/broker/dashboard'),
            icon: const Icon(Icons.dashboard, color: Colors.black),
            label: const Text('فتح لوحة الوسيط'),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard() {
    return Container(
      padding: AppTheme.paddingAllXL,
      decoration: BoxDecoration(
        color: AppTheme.warningOrange.withOpacity(0.1),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.warningOrange),
      ),
      child: const Column(
        children: [
          Icon(Icons.hourglass_top, color: AppTheme.warningOrange, size: 48),
          AppTheme.gapHeightSmall,
          Text('طلبك قيد المراجعة ⏳',
              style: TextStyle(
                  color: AppTheme.warningOrange,
                  fontSize: AppTheme.fontSizeTitle,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text(
            'لقد أرسلت طلباً سابقاً. سنبلغك بمجرد المراجعة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textGrey),
          ),
        ],
      ),
    );
  }

  /// 🛡️ بطاقة التوثيق المطلوب — تظهر للمستخدم غير الموثق قبل النموذج
  Widget _verificationRequiredCard() {
    final user = context.read<AuthProvider>().userModel;
    final hasId = user != null && user.sid.isNotEmpty && user.img.isNotEmpty;
    return Container(
      padding: AppTheme.paddingAllXL,
      decoration: BoxDecoration(
        color: AppTheme.warningOrange.withOpacity(0.1),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.warningOrange),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_user_outlined,
              color: AppTheme.warningOrange, size: 48),
          AppTheme.gapHeightSmall,
          const Text('توثيق الهوية مطلوب أولاً',
              style: TextStyle(
                  color: AppTheme.warningOrange,
                  fontSize: AppTheme.fontSizeTitle,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            hasId
                ? 'تم رفع هويتك وهي بانتظار مراجعة الإدارة.\nبعد الموافقة يمكنك التقديم مباشرة كوسيط.'
                : 'للانضمام كوسيط يجب توثيق هويتك أولاً (صورة الهوية + الرقم الوطني).',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textGrey, height: 1.5),
          ),
          if (!hasId) ...[
            AppTheme.gapHeightLarge,
            ElevatedButton.icon(
              onPressed: () => context.push('/setup-identity'),
              icon: const Icon(Icons.badge_outlined, color: Colors.black),
              label: const Text('توثيق الهوية الآن'),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.warningOrange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // المزايا
        const Text('✨ مزايا الوسيط',
            style: TextStyle(
                color: AppTheme.primaryGold,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        AppTheme.gapHeightSmall,
        _benefit('💼', 'إدراج حتى 5 عروض و 5 طلبات (مقابل 1+3 للمستخدم العادي)'),
        _benefit('🎯', 'لوحة تحكم خاصة بالعروض والمواعيد والصفقات'),
        _benefit('📈', 'إحصائيات تفصيلية لأدائك'),
        _benefit('⭐', 'أولوية ظهور بنتائج البحث'),
        _benefit('🤝', 'شبكة عملاء أوسع عبر المكتب'),
        AppTheme.gapHeightXL,

        // النموذج
        const Text('📝 معلومات الطلب',
            style: TextStyle(
                color: AppTheme.primaryGold,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        AppTheme.gapHeightMedium,
        _label('الاسم التجاري *'),
        TextField(
          controller: _businessNameCtrl,
          style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(
            hintText: 'مثلاً: مكتب النور للعقارات',
            prefixIcon: Icon(Icons.business, color: AppTheme.primaryGold),
          ),
        ),
        AppTheme.gapHeightLarge,

        _label('فئة الوساطة *'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlack,
            borderRadius: AppTheme.radiusMedium,
          ),
          child: Column(
            children: _categories.entries
                .map((e) => RadioListTile<int>(
                      value: e.key,
                      groupValue: _category,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _category = value);
                      },
                      title: Text(
                        e.value,
                        style: const TextStyle(color: AppTheme.textWhite),
                      ),
                      activeColor: AppTheme.primaryGold,
                      dense: true,
                    ))
                .toList(),
          ),
        ),
        AppTheme.gapHeightLarge,

        _label('سنوات الخبرة (اختياري)'),
        TextField(
          controller: _experienceCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(
            hintText: 'مثلاً: 5',
            prefixIcon: Icon(Icons.work_history,
                color: AppTheme.primaryGold),
          ),
        ),
        AppTheme.gapHeightLarge,

        _label('نبذة عنك (اختياري)'),
        TextField(
          controller: _aboutCtrl,
          maxLines: 4,
          style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(
            hintText: 'تحدّث عن خبرتك ومناطق عملك...',
          ),
        ),
        AppTheme.gapHeightXL,

        // الشروط
        Container(
          padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlack,
            borderRadius: AppTheme.radiusMedium,
          ),
          child: Column(
            children: [
              const Text(
                '⚠️ شروط والتزامات الوسيط:\n• الالتزام بالأمانة والصدق في العروض\n• تسجيل العمولات للمكتب\n• الاستجابة لطلبات العملاء بسرعة\n• عدم تجاوز الصلاحيات المخوّلة',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
              ),
              AppTheme.gapHeightSmall,
              CheckboxListTile(
                value: _agreeTerms,
                onChanged: (v) =>
                    setState(() => _agreeTerms = v ?? false),
                title: const Text(
                  'أوافق على الشروط والالتزامات',
                  style: TextStyle(
                      color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
                ),
                activeColor: AppTheme.primaryGold,
                checkColor: Colors.black,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
        AppTheme.gapHeightXL,

        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.send, color: Colors.black),
            label: const Text('إرسال الطلب للإدارة',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _benefit(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: AppTheme.fontSizeTitle)),
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: AppTheme.primaryGold,
                fontWeight: FontWeight.bold,
                fontSize: AppTheme.fontSizeBody)),
      );
}
