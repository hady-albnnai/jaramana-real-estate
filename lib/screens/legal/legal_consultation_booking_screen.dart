import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';
import '../../core/network/supabase_service.dart';
import '../../core/constants/db_constants.dart';
import '../../core/validation/input_validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../models/config_model.dart';
import '../../providers/legal_provider.dart';
import '../../providers/payment_provider.dart';
import '../../models/payment_model.dart';
import '../../services/storage_service.dart';

/// شاشة الاستشارة القانونية — تدفق بسيط ونظيف
///
/// الشاشة الرئيسية تعرض:
/// 1. إذا في دفعة معلقة → "بانتظار التأكيد"
/// 2. إذا في دفعة مقبولة بدون استشارة → "إرسال الطلب"
/// 3. إذا في استشارة نشطة → "فتح المحادثة"
/// 4. أزرار "استشارة جديدة" / "جلسة حضورية"
class LegalConsultationBookingScreen extends StatefulWidget {
  const LegalConsultationBookingScreen({super.key});
  @override
  State<LegalConsultationBookingScreen> createState() => _State();
}

class _State extends State<LegalConsultationBookingScreen> {
  final _storage = StorageService();
  bool _loading = true;

  // البيانات
  Map<String, dynamic>? _pendingPayment;    // دفعة قيد المراجعة (أقدم نوع)
  Map<int, Map<String, dynamic>> _pendingByType = {}; // دفعة معلّقة لكل نوع
  Map<String, dynamic>? _rejectedPayment;   // دفعة مرفوضة من الإدارة (sts=2)
  Map<String, dynamic>? _rejectedConsultation; // استشارة مرفوضة نهائياً (4)
  Map<String, dynamic>? _needInfoConsultation; // بانتظار استكمال بياناتك (5)
  List<Map<String, dynamic>> _credits = []; // 🎁 أرصدة استشارة ممنوحة من الإدارة
  Map<String, dynamic>? _approvedPayment;   // دفعة مقبولة بدون استشارة
  Map<String, dynamic>? _activeConsultation; // استشارة نشطة (الأحدث)
  List<Map<String, dynamic>> _previousChats = [];

  // الـ Wizard
  int _screen = 0; // 0=رئيسية 1=ارشادات 2=نوع 3=قديمة 4=موضوع 5=دفع 6=نجاح 7=اختيار موعد
  String? _selectedSlot;        // موعد الجلسة الحضورية المختار
  String _slotLawyerAlias = ''; // لقب المحامي (بلا هويته)
  int _serviceType = 0;
  bool _isContinuing = false; // متابعة محادثة قديمة
  String? _continueChatId;
  final _subjectCtrl = TextEditingController();
  final List<XFile> _attachments = [];
  String _channel = '';
  final _refCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  XFile? _proofImage;
  bool _submitting = false;

  /// true = شاشة النجاح معروضة لدفعة معلّقة سابقة (لا لدفعة أُرسلت للتو)
  bool _viewingPending = false;

  static const _topicChips = ['عقد إيجار', 'نزاع عقاري', 'إرث', 'مخالفة مرورية', 'سند ملكية', 'عقد عمل', 'أخرى'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _subjectCtrl.dispose(); _refCtrl.dispose(); _senderPhoneCtrl.dispose();
    super.dispose();
  }

  // ── ⚖️ الأسعار والمدة من الإعدادات (2026-08-14) ──
  // كانت 500/2000/15 مضمّنة نصاً في 11 موضعاً بهذه الشاشة ⇒ تعديل الإدارة
  // للسعر كان مستحيلاً، والسيرفر يرفض أي قيمة مخالفة بـ INVALID_PRICE.
  ConfigModel? get _cfg => context.read<ConfigProvider>().config;
  int _priceFor(int serviceType) =>
      _cfg?.legalPriceFor(serviceType) ?? (serviceType == 1 ? 2000 : 500);
  int get _phonePrice => _cfg?.legalPhonePrice ?? 500;
  int get _onsitePrice => _cfg?.legalOnsitePrice ?? 2000;
  int get _renewPrice => _cfg?.legalRenewPrice ?? 500;
  int get _durationMins => _cfg?.legalDurationMins ?? 15;

  /// تنسيق المبلغ بفواصل الآلاف (2,000 ل.س)
  static String _fmt(int v) => v.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  bool get _isLateNight => DateTime.now().hour >= 23 || DateTime.now().hour < 9;
  bool get _needsSenderPhone => _channel == 'balance' || _channel == 'syriatel_cash';

  String _normPhone(String p) {
    final d = p.replaceAll(RegExp(r'[^\d]'), '');
    if (d.startsWith('963') && d.length == 12) return '0${d.substring(3)}';
    if (d.startsWith('09') && d.length == 10) return d;
    if (d.startsWith('9') && d.length == 9) return '0$d';
    return d;
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    if (uid.isEmpty) { setState(() => _loading = false); return; }
    try {
      // الدفعات
      final pays = await SupabaseService().client.from(DbTables.payments)
          .select('id, sts, amt, pkg, channel, ref, ts_crt, meta')
          .eq('uid', uid).eq('tp', 2).order('ts_crt', ascending: false);
      
      // 2026-08-14: الدفعات تُصنَّف **حسب النوع** (pkg: 0 هاتفية · 1 حضورية)
      // تنفيذاً لقاعدة المالك: المنع لنفس النوع فقط. وتُلتقط المرفوضة أيضاً
      // (sts=2) — كانت الشاشة تتجاهلها تماماً فيبقى المستخدم بلا تفسير.
      Map<String, dynamic>? pending, approved, rejected;
      final pendingByType = <int, Map<String, dynamic>>{};
      for (final p in pays as List) {
        final m = Map<String, dynamic>.from(p as Map);
        final pk = (m['pkg'] ?? 0) as int;
        if (m['sts'] == 0) {
          pendingByType.putIfAbsent(pk, () => m);
          pending ??= m;
        } else if (m['sts'] == 1 && approved == null) {
          // تأكد ما في استشارة مربوطة
          final cRes = await SupabaseService().client.from('legal_consultations')
              .select('id').eq('payment_id', m['id']).limit(1);
          if ((cRes as List).isEmpty) approved = m;
        } else if (m['sts'] == 2 && rejected == null) {
          rejected = m;
        }
      }

      // الاستشارات النشطة
      final consultRes = await SupabaseService().invokeFunction('legal-actions',
          body: {'action': 'list_my_consultations', 'user_uid': uid});
      final cData = consultRes.data as Map<String, dynamic>?;
      final all = cData != null && cData['success'] == true
          ? List<Map<String, dynamic>>.from((cData['consultations'] as List?) ?? []) : <Map<String, dynamic>>[];
      
      Map<String, dynamic>? active;
      Map<String, dynamic>? rejectedConsult; // status=4 رفض نهائي
      Map<String, dynamic>? needInfo;        // status=5 بانتظار استكمال بيانات
      final previous = <Map<String, dynamic>>[];
      final now = DateTime.now();
      for (final c in all) {
        final status = c['status'] ?? 0;
        final chatStarted = c['chat_started_at'];
        
        // 🔴 إصلاح 2026-08-14: كانت 4 (مرفوضة نهائياً) تُعامل كـ«نشطة» وتُعرض
        // «المحامي يدرس مشكلتك» إلى الأبد — أخطر تشويش في المنطق كله.
        // الآن: 4 = مرفوضة · 5 = بانتظار استكمال بياناتك · 0 = بانتظار المحامي.
        if (status == 4) { rejectedConsult ??= c; continue; }
        if (status == 5) { needInfo ??= c; continue; }
        if (status == 0 && active == null) {
          active = c;
          continue;
        }
        
        // استشارة مفتوحة المحادثة = status 1 مع chat_started
        if (status == 1 && chatStarted != null) {
          final dt = DateTime.tryParse(chatStarted.toString());
          if (dt != null) {
            final durationMin = (c['chat_duration_minutes'] ?? 15) as int;
            final elapsed = now.difference(dt);
            final timeUp = elapsed.inMinutes >= durationMin;
            final within7Days = elapsed.inDays < 7;
            
            if (!timeUp && active == null) {
              // الوقت لسه ما خلص = استشارة نشطة
              active = c;
            } else if (within7Days) {
              // الوقت خلص بس ضمن 7 أيام = محادثة سابقة (للمتابعة)
              previous.add(c);
            }
          }
          continue;
        }
        
        // استشارة مقبولة بدون محادثة = نشطة
        if (status == 1 && chatStarted == null && active == null) {
          active = c;
        }
      }

      // 🎁 رصيد ممنوح من الإدارة (بديل الاسترداد) — يسمح بطلب بلا دفع
      final credits = await context.read<LegalProvider>().fetchMyCredits(uid);

      if (mounted) setState(() {
        _credits = credits;
        _pendingPayment = pending;
        _pendingByType = pendingByType;
        _rejectedPayment = rejected;
        _approvedPayment = approved;
        _activeConsultation = active;
        _rejectedConsultation = rejectedConsult;
        _needInfoConsultation = needInfo;
        _previousChats = previous;
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
    context.read<LegalProvider>().fetchActiveLawyers();
  }

  void _goTo(int s) => setState(() => _screen = s);

  /// حارس الدفعة المعلّقة (أُضيف 2026-08-14).
  ///
  /// أي محاولة لبدء مسار جديد (هاتفية أو حضورية أو متابعة محادثة) بينما توجد
  /// دفعة `tp=2` بحالة `sts=0` تُعترض وتُحوَّل لشاشة «الدفعة قيد الانتظار» —
  /// وهي نفس شاشة ما بعد إرسال الدفع (فيها زر «العودة للرئيسية»).
  /// يمنع ذلك إرسال دفعتين متتاليتين لنفس الخدمة قبل بتّ الإدارة بالأولى.
  /// 🎁 هل لدى المستخدم رصيد مجاني لهذا النوع؟ (يتخطّى شاشة الدفع)
  bool _hasCredit(int serviceType) =>
      _credits.any((c) => (c['service_type'] ?? 0) == serviceType);

  /// يمنع البدء **لنفس النوع فقط** (قاعدة المالك 2026-08-14):
  /// هاتفية معلّقة لا تمنع الحضورية والعكس. والدفعة المقبولة لا تمنع شيئاً.
  bool _guardPending(int serviceType) {
    final p = _pendingByType[serviceType];
    if (p == null) return false;
    setState(() {
      _viewingPending = true;
      _pendingPayment = p; // نعرض دفعة النوع المقصود بالضبط
      _screen = 6;
    });
    return true;
  }
  void _resetWizard() {
    _screen = 0; _serviceType = 0; _isContinuing = false; _continueChatId = null; _viewingPending = false; _selectedSlot = null;
    _subjectCtrl.clear(); _attachments.clear(); _channel = ''; _proofImage = null; _refCtrl.clear(); _senderPhoneCtrl.clear();
  }

  // إرفاق
  void _pickAttachments() async {
    final rem = 5 - _attachments.length;
    if (rem <= 0) { _snack('الحد الأقصى 5 صور'); return; }
    final files = await ImagePicker().pickMultiImage(imageQuality: 60, maxWidth: 1280);
    if (files.isNotEmpty) setState(() => _attachments.addAll(files.take(rem)));
  }
  void _pickProof() async { final f = await _storage.pickImage(fromCamera: false); if (f != null) setState(() => _proofImage = f); }

  Future<List<String>> _uploadAttachments() async {
    if (_attachments.isEmpty) return [];
    final urls = <String>[];
    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    for (final f in _attachments) {
      try {
        final comp = await _storage.compressImage(File(f.path));
        final bytes = await (comp ?? File(f.path)).readAsBytes();
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.${f.path.split('.').last}';
        await SupabaseService().storage.from('consultation_files').uploadBinary(path, bytes, fileOptions: FileOptions(cacheControl: '3600', upsert: false));
        urls.add(path);
      } catch (_) {}
    }
    return urls;
  }

  Future<String?> _uploadProof(String uid) async {
    if (_proofImage == null) return null;
    try {
      final path = '$uid/proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = kIsWeb ? await _proofImage!.readAsBytes()
          : await (await _storage.compressImage(File(_proofImage!.path)) ?? File(_proofImage!.path)).readAsBytes();
      await SupabaseService().storage.from(StorageService.paymentProofsBucket).uploadBinary(path, bytes, fileOptions: FileOptions(cacheControl: '3600', upsert: false));
      return path;
    } catch (_) { return null; }
  }

  // الدفع
  Future<void> _pay() async {
    if (_subjectCtrl.text.trim().length < 10 && !_isContinuing) { _snack('اكتب موضوع الاستشارة (10 أحرف على الأقل)'); return; }
    if (_channel.isEmpty) { _snack('اختر قناة الدفع'); return; }
    if (_proofImage == null) { _snack('ارفع إثبات الدفع'); return; }
    final ref = InputValidators.normalizeDigits(_refCtrl.text.trim());
    if (ref.isEmpty) { _snack('أدخل رقم العملية'); return; }

    setState(() => _submitting = true);
    final user = context.read<AuthProvider>().userModel!;
    String sender = '';
    if (_needsSenderPhone) { sender = _normPhone(_senderPhoneCtrl.text.trim()); }

    final proof = await _uploadProof(user.uid);
    if (proof == null) { _snack('فشل رفع الإثبات'); setState(() => _submitting = false); return; }

    // السعر من الإعدادات؛ ودفعة التجديد تأخذ سعر التجديد لا سعر الاستشارة
    final price =
        (_isContinuing ? _renewPrice : _priceFor(_serviceType)).toDouble();
    final payment = PaymentModel(
      id: '', uid: user.uid, tp: 2, pkg: _serviceType, amt: price, cur: 1, mtd: 0,
      channel: _channel, proof: proof, ref: ref, sts: 0, tsCrt: DateTime.now(),
      meta: {'service': 'legal_consultation', if (sender.isNotEmpty) 'sender_phone': sender, if (_isContinuing && _continueChatId != null) 'continue_chat': _continueChatId},
    );
    try {
      final ok = await context.read<PaymentProvider>().makePayment(payment);
      if (ok) { _goTo(6); _snack('✅ تم إرسال الدفعة'); } else { _snack('فشل تسجيل الدفعة'); }
    } catch (e) { _snack('خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  // إرسال الاستشارة
  Future<void> _submitConsultation() async {
    setState(() => _submitting = true);
    final atts = await _uploadAttachments();
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'book_consultation', 'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'service_type': _serviceType, 'subject': _subjectCtrl.text.trim(),
        'price': _priceFor(_serviceType), 'attachments': atts,
        // 🏢 الحضورية = موعد + دفع (بلا محادثة) — الموعد إلزامي خادمياً
        if (_serviceType == 1 && _selectedSlot != null) 'slot': _selectedSlot,
      });
      if (res.data is Map && (res.data as Map)['success'] == true) {
        _snack(_serviceType == 1
            ? '✅ تم حجز موعدك — بانتظار تأكيد المحامي'
            : '✅ تم إرسال الطلب — المحامي يدرس مشكلتك');
        _resetWizard(); _loadAll();
      } else {
        final err = (res.data as Map?)?['error']?.toString() ?? 'فشل';
        _snack(err == 'SLOT_NO_LONGER_AVAILABLE'
            ? 'اختار شخص آخر هذا الموعد — يرجى اختيار موعد بديل'
            : err == 'SLOT_REQUIRED_FOR_ONSITE' ? 'يرجى اختيار موعد الجلسة أولاً' : err);
        if (err == 'SLOT_NO_LONGER_AVAILABLE') { setState(() => _selectedSlot = null); _goTo(7); }
      }
    } catch (e) { _snack('خطأ: $e'); }
    if (mounted) setState(() => _submitting = false);
  }

  void _openChat(String id) => context.push('/legal/chat/$id');

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    switch (_screen) {
      case 0: return _buildHome();
      case 1: return _buildExplanation();
      case 2: return _buildChooseType();
      case 3: return _buildPreviousChats();
      case 4: return _buildSubjectForm();
      case 5: return _buildPaymentForm();
      case 6: return _buildSuccess();
      case 7: return _buildSlotPicker();
      default: return _buildHome();
    }
  }

  // ── الشاشة الرئيسية ──
  Widget _buildHome() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('الاستشارة القانونية', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => Navigator.pop(context)),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: AppTheme.primaryGold), onPressed: _loadAll)]),
      body: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : RefreshIndicator(color: AppTheme.primaryGold, onRefresh: _loadAll, child: _buildHomeContent()),
    );
  }

  /// الشاشة الرئيسية — تُبنى تراكمياً (2026-08-14).
  ///
  /// المبدأ: **لا حالة مخفية ولا تكهن**. كل ما يخص المستخدم يظهر معاً:
  /// طلب ناقص البيانات · دفعة مرفوضة · دفعات معلّقة (لكل نوع) · دفعة مقبولة
  /// · استشارة نشطة · اعتذار نهائي. والأزرار تبقى ظاهرة دائماً لأن المنع
  /// صار **حسب النوع** لا شاملاً.
  Widget _buildHomeContent() {
    final cards = <Widget>[];

    // ⓪ رصيد مجاني ممنوح من الإدارة (بديل الاسترداد النقدي)
    if (_credits.isNotEmpty) cards.add(_creditCard());

    // ① بانتظار استكمال بياناتك (الأولوية القصوى — الكرة بملعب المستخدم)
    if (_needInfoConsultation != null) cards.add(_needInfoCard(_needInfoConsultation!));

    // ② دفعة رفضتها الإدارة — كانت الشاشة تتجاهلها فيبقى بلا تفسير
    if (_rejectedPayment != null) cards.add(_rejectedPaymentCard(_rejectedPayment!));

    // ③ اعتذار نهائي من المحامي (كان يُعرض «المحامي يدرس مشكلتك» للأبد)
    if (_rejectedConsultation != null) cards.add(_rejectedConsultCard(_rejectedConsultation!));

    // ④ الدفعات المعلّقة — بطاقة لكل نوع
    for (final e in _pendingByType.entries) {
      cards.add(_pendingBannerFor(e.key, e.value));
    }

    // ⑤ دفعة مقبولة بانتظار إرسال الطلب
    if (_approvedPayment != null) cards.add(_approvedCard(_approvedPayment!));

    // ⑥ استشارة نشطة
    if (_activeConsultation != null) cards.add(_activeCard(_activeConsultation!));

    if (cards.isEmpty) {
      return ListView(padding: AppTheme.paddingAllLarge, children: [
        AppTheme.gapHeightXXL,
        const Center(child: Icon(Icons.gavel, color: AppTheme.primaryGold, size: 56)),
        AppTheme.gapHeightLarge,
        const Center(child: Text('الاستشارة القانونية', style: TextStyle(color: AppTheme.textWhite, fontSize: 20, fontWeight: FontWeight.bold))),
        AppTheme.gapHeightSmall,
        const Center(child: Text('احصل على استشارة قانونية من محامي المكتب', style: TextStyle(color: AppTheme.textGrey, fontSize: 13))),
        AppTheme.gapHeightXXL,
        _buildNewButtons(),
      ]);
    }

    return ListView(padding: AppTheme.paddingAllLarge, children: [
      AppTheme.gapHeightMedium,
      ...cards.expand((w) => [w, AppTheme.gapHeightMedium]),
      const Divider(color: Colors.white12),
      AppTheme.gapHeightMedium,
      const Text('ابدأ طلباً جديداً:',
          style: TextStyle(color: AppTheme.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
      AppTheme.gapHeightSmall,
      _buildNewButtons(),
      AppTheme.gapHeightLarge,
    ]);
  }

  // ═══════════════════════════════════════════════════════════════
  // بطاقات الحالة (2026-08-14) — كل واحدة تجيب: أين طلبي؟ وما التالي؟
  // ═══════════════════════════════════════════════════════════════

  /// 🧭 خط زمني مرئي — يلغي التكهن بموضع الطلب في الرحلة
  Widget _timeline(int step, {bool phone = true}) {
    final steps = phone
        ? ['الدفع', 'اعتماد الإدارة', 'المحامي', 'المحادثة']
        : ['الدفع', 'اعتماد الإدارة', 'المحامي', 'الجلسة'];
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final done = (i ~/ 2) < step;
          return Expanded(
            child: Container(
              height: 2,
              color: done ? AppTheme.successGreen : Colors.white24,
            ),
          );
        }
        final idx = i ~/ 2;
        final done = idx < step;
        final current = idx == step;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? AppTheme.successGreen
                  : current ? AppTheme.primaryGold : Colors.transparent,
              border: Border.all(
                  color: done || current ? Colors.transparent : Colors.white24, width: 1.5),
            ),
            child: done
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : current
                    ? const Icon(Icons.more_horiz, size: 12, color: Colors.black)
                    : null,
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 58,
            child: Text(steps[idx], textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 9,
                    color: done || current ? AppTheme.textWhite : AppTheme.textGrey,
                    fontWeight: current ? FontWeight.bold : FontWeight.normal)),
          ),
        ]);
      }),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required Color color,
    required String title,
    required List<Widget> children,
  }) =>
      Container(
        width: double.infinity,
        padding: AppTheme.paddingAllMedium,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: color.withOpacity(0.55)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 24),
            AppTheme.gapWidthSmall,
            Expanded(child: Text(title,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15))),
          ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  String _typeName(int pkg) => pkg == 1 ? 'جلسة حضورية' : 'استشارة هاتفية';

  /// 🎁 رصيد استشارة ممنوح من الإدارة — يطلب بلا دفع
  Widget _creditCard() {
    final phone = _credits.where((c) => (c['service_type'] ?? 0) == 0).length;
    final onsite = _credits.where((c) => (c['service_type'] ?? 0) == 1).length;
    final reason = (_credits.first['reason'] ?? '').toString();
    return _statusCard(
      icon: Icons.card_giftcard,
      color: AppTheme.successGreen,
      title: 'لديك رصيد استشارة مجاني',
      children: [
        Text(
          [
            if (phone > 0) '$phone استشارة هاتفية',
            if (onsite > 0) '$onsite جلسة حضورية',
          ].join('  ·  '),
          style: const TextStyle(
              color: AppTheme.textWhite, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(reason,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 11, height: 1.4)),
        ],
        const SizedBox(height: 6),
        const Text('اطلب استشارتك من الأزرار أدناه — لن يُطلب منك أي دفع.',
            style: TextStyle(
                color: AppTheme.successGreen, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// 📄 المحامي يطلب استكمال بيانات (الحالة 5) — بلا دفع جديد
  Widget _needInfoCard(Map<String, dynamic> c) {
    final note = (c['reject_note'] ?? '').toString();
    final sType = (c['service_type'] ?? 0) as int;
    return _statusCard(
      icon: Icons.edit_note, color: AppTheme.infoBlue,
      title: 'المحامي يحتاج تفاصيل إضافية',
      children: [
        Text('المطلوب: $note',
            style: const TextStyle(color: AppTheme.textWhite, fontSize: 13, height: 1.5)),
        const SizedBox(height: 6),
        const Text('دفعتك محفوظة — لا حاجة لدفع جديد.',
            style: TextStyle(color: AppTheme.successGreen, fontSize: 11, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightMedium,
        _timeline(2, phone: sType == 0),
        AppTheme.gapHeightMedium,
        SizedBox(width: double.infinity, height: 44, child: ElevatedButton.icon(
          onPressed: () => _showResubmitDialog(c),
          icon: const Icon(Icons.send, color: Colors.black, size: 18),
          label: const Text('استكمال البيانات وإعادة الإرسال',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ],
    );
  }

  /// ❌ الإدارة رفضت الدفعة — كانت الشاشة تتجاهل sts=2 تماماً
  Widget _rejectedPaymentCard(Map<String, dynamic> p) {
    final reason = ((p['meta'] as Map?)?['reject_reason'] ?? '').toString();
    final pkg = (p['pkg'] ?? 0) as int;
    return _statusCard(
      icon: Icons.money_off, color: AppTheme.errorRed,
      title: 'لم تُقبل دفعتك',
      children: [
        Text('${_fmt((p['amt'] as num?)?.toInt() ?? 0)} ل.س — ${_typeName(pkg)}',
            style: const TextStyle(color: AppTheme.textWhite, fontSize: 13)),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('السبب: $reason',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 12, height: 1.5)),
        ],
        const SizedBox(height: 6),
        const Text('راجع بيانات التحويل وأعد الإرسال.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
        AppTheme.gapHeightMedium,
        SizedBox(width: double.infinity, height: 42, child: ElevatedButton.icon(
          onPressed: () { setState(() { _rejectedPayment = null; _serviceType = pkg; }); _goTo(4); },
          icon: const Icon(Icons.refresh, color: Colors.black, size: 18),
          label: const Text('إعادة المحاولة',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ],
    );
  }

  /// 🚫 اعتذار نهائي من المحامي (status=4)
  Widget _rejectedConsultCard(Map<String, dynamic> c) {
    final note = (c['reject_note'] ?? '').toString();
    return _statusCard(
      icon: Icons.gavel, color: AppTheme.errorRed,
      title: 'تعذّر قبول طلبك',
      children: [
        Text((c['subject'] ?? '').toString(),
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('السبب: $note',
              style: const TextStyle(color: AppTheme.textWhite, fontSize: 13, height: 1.5)),
        ],
        const SizedBox(height: 8),
        const Text('الإدارة أُخطرت وستتواصل معك بخصوص المبلغ المدفوع.',
            style: TextStyle(color: AppTheme.warningOrange, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// ⏳ دفعة قيد المراجعة — لكل نوع بطاقته
  Widget _pendingBannerFor(int pkg, Map<String, dynamic> p) {
    final dt = DateTime.tryParse(p['ts_crt']?.toString() ?? '');
    final when = dt == null ? '' :
        '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}'
        ' — ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () => setState(() { _viewingPending = true; _pendingPayment = p; _screen = 6; }),
      child: _statusCard(
        icon: Icons.hourglass_top, color: AppTheme.warningOrange,
        title: 'دفعة قيد المراجعة — ${_typeName(pkg)}',
        children: [
          Text('${_fmt((p['amt'] as num?)?.toInt() ?? 0)} ل.س'
               '${when.isEmpty ? '' : '  •  $when'}',
              style: const TextStyle(color: AppTheme.textWhite, fontSize: 13)),
          const SizedBox(height: 6),
          const Text('الإدارة تراجعها عادة خلال ساعة — سيصلك إشعار.',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
          AppTheme.gapHeightMedium,
          _timeline(1, phone: pkg == 0),
          AppTheme.gapHeightSmall,
          const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('اضغط للتفاصيل',
                style: TextStyle(color: AppTheme.primaryGold, fontSize: 11, fontWeight: FontWeight.bold)),
            Icon(Icons.arrow_forward_ios, color: AppTheme.primaryGold, size: 11),
          ]),
        ],
      ),
    );
  }

  /// ✅ دفعة معتمدة — أرسل طلبك للمحامي
  Widget _approvedCard(Map<String, dynamic> p) {
    final pkg = (p['pkg'] ?? 0) as int;
    return _statusCard(
      icon: Icons.check_circle, color: AppTheme.successGreen,
      title: 'تم تأكيد دفعتك',
      children: [
        Text('${_fmt((p['amt'] as num?)?.toInt() ?? 0)} ل.س — ${_typeName(pkg)}',
            style: const TextStyle(color: AppTheme.textWhite, fontSize: 13)),
        AppTheme.gapHeightMedium,
        _timeline(2, phone: pkg == 0),
        AppTheme.gapHeightMedium,
        SizedBox(width: double.infinity, height: 46, child: ElevatedButton.icon(
          onPressed: () { _serviceType = pkg; _goTo(4); },
          icon: const Icon(Icons.send, color: Colors.black, size: 18),
          label: const Text('إرسال الطلب للمحامي',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ],
    );
  }

  /// ⚖️ استشارة نشطة (بانتظار المحامي أو محادثة جارية)
  Widget _activeCard(Map<String, dynamic> c) {
    final status = (c['status'] ?? 0) as int;
    final chatStarted = c['chat_started_at'] != null;
    final id = c['id'].toString();
    final alias = (c['lawyer_alias'] ?? '').toString();
    final sType = (c['service_type'] ?? 0) as int;
    final reassigned = ((c['reassign_count'] ?? 0) as int) > 0;
    final noLawyer = alias.isEmpty;

    final step = chatStarted ? 3 : (status == 1 ? 3 : 2);
    return _statusCard(
      icon: sType == 0 ? Icons.phone_in_talk : Icons.business,
      color: AppTheme.primaryGold,
      title: _typeName(sType == 1 ? 1 : 0),
      children: [
        Text((c['subject'] ?? '').toString(),
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
        if (alias.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('⚖️ $alias', style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12)),
        ],
        // 🏢 موعد الجلسة الحضورية — كانت تبقى بلا موعد إطلاقاً قبل 2026-08-14
        if (sType == 1) ...[
          const SizedBox(height: 6),
          Builder(builder: (_) {
            final raw = (c['requested_slot'] ?? '').toString();
            final dt = DateTime.tryParse(raw)?.toLocal();
            if (dt == null) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withOpacity(0.10),
                borderRadius: AppTheme.radiusSmall,
                border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.event, color: AppTheme.primaryGold, size: 15),
                const SizedBox(width: 5),
                Text(
                  'موعدك: ${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
                  '${dt.day.toString().padLeft(2, '0')} — '
                  '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ]),
            );
          }),
        ],
        if (reassigned) ...[
          const SizedBox(height: 4),
          const Text('🔄 حُوّل طلبك لمحامٍ آخر متاح — بلا رسوم إضافية',
              style: TextStyle(color: AppTheme.infoBlue, fontSize: 11)),
        ],
        AppTheme.gapHeightMedium,
        _timeline(step, phone: sType == 0),
        AppTheme.gapHeightMedium,
        if (noLawyer)
          const Row(children: [
            Icon(Icons.search, color: AppTheme.warningOrange, size: 18),
            SizedBox(width: 6),
            Expanded(child: Text('نبحث لك عن محامٍ متاح — الإدارة تتابع طلبك',
                style: TextStyle(color: AppTheme.warningOrange, fontSize: 12, fontWeight: FontWeight.bold))),
          ])
        else if (status == 0)
          const Row(children: [
            Icon(Icons.hourglass_empty, color: AppTheme.warningOrange, size: 18),
            SizedBox(width: 6),
            Text('بانتظار قبول المحامي',
                style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold, fontSize: 12)),
          ])
        else if (status == 1 && !chatStarted)
          const Row(children: [
            Icon(Icons.menu_book, color: AppTheme.infoBlue, size: 18),
            SizedBox(width: 6),
            Text('المحامي يدرس مشكلتك',
                style: TextStyle(color: AppTheme.infoBlue, fontWeight: FontWeight.bold, fontSize: 12)),
          ])
        else if (chatStarted)
          SizedBox(width: double.infinity, height: 46, child: ElevatedButton.icon(
            onPressed: () => _openChat(id),
            icon: const Icon(Icons.chat, color: Colors.black, size: 18),
            label: const Text('فتح المحادثة',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
          )),
        if (status == 0) ...[
          AppTheme.gapHeightSmall,
          // 🔔 تنبيه المحامي المتأخر — الفعل كان بالسيرفر بلا واجهة إطلاقاً
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _nudgeLawyer(id),
                icon: const Icon(Icons.notifications_active_outlined,
                    color: AppTheme.primaryGold, size: 15),
                label: const Text('تنبيه المحامي',
                    style: TextStyle(color: AppTheme.primaryGold, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryGold)),
              ),
            ),
            if (sType == 0) ...[
              AppTheme.gapWidthSmall,
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _convertToOnsite(id),
                  icon: const Icon(Icons.business, color: AppTheme.infoBlue, size: 15),
                  label: const Text('تحويل لحضورية',
                      style: TextStyle(color: AppTheme.infoBlue, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.infoBlue)),
                ),
              ),
            ],
          ]),
          TextButton.icon(
            onPressed: () => _cancelConsultation(id),
            icon: const Icon(Icons.cancel_outlined, color: AppTheme.errorRed, size: 16),
            label: const Text('إلغاء الطلب',
                style: TextStyle(color: AppTheme.errorRed, fontSize: 12)),
          ),
        ],
      ],
    );
  }

  /// 🔁 نافذة استكمال البيانات الناقصة
  Future<void> _showResubmitDialog(Map<String, dynamic> c) async {
    final ctrl = TextEditingController(text: (c['subject'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('استكمال البيانات',
            style: TextStyle(color: AppTheme.primaryGold, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('المطلوب: ${(c['reject_note'] ?? '').toString()}',
                style: const TextStyle(color: AppTheme.infoBlue, fontSize: 12, height: 1.5)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl, maxLines: 5, maxLength: 500,
              style: const TextStyle(color: AppTheme.textWhite, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'اكتب التفاصيل كاملة',
                filled: true, fillColor: AppTheme.scaffoldBackground,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لاحقاً', style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
              child: const Text('إرسال', style: TextStyle(color: Colors.black))),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    if (text.length < 10) { _snack('اكتب تفاصيل أوضح (10 أحرف على الأقل)'); return; }

    setState(() => _submitting = true);
    final done = await context.read<LegalProvider>().resubmitConsultation(
      id: c['id'].toString(),
      userUid: context.read<AuthProvider>().userModel?.uid ?? '',
      subject: text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    _snack(done ? '✅ أُرسلت البيانات للمحامي' : (context.read<LegalProvider>().error ?? 'فشل الإرسال'));
    if (done) _loadAll();
  }

  /// 🔔 تنبيه المحامي المتأخر (الحارس الخادمي: ساعة على الأقل)
  Future<void> _nudgeLawyer(String id) async {
    final legal = context.read<LegalProvider>();
    final res = await legal.reactivateConsultation(
        consultationId: id,
        userUid: context.read<AuthProvider>().userModel?.uid ?? '');
    if (!mounted) return;
    if (res != null) {
      _snack('🔔 تم تنبيه المحامي');
      _loadAll();
    } else {
      final e = legal.error ?? '';
      _snack(e.contains('TOO_EARLY')
          ? 'يمكنك التنبيه بعد ساعة من إرسال الطلب'
          : (e.isEmpty ? 'فشل التنبيه' : e));
    }
  }

  /// 🔀 تحويل الهاتفية إلى جلسة حضورية باختيار موعد ودفع الفرق
  Future<void> _convertToOnsite(String id) async {
    final legal = context.read<LegalProvider>();
    final data = await legal.fetchFreeSlots(days: 14);
    if (!mounted) return;
    final slots = (data['slots'] as List?)?.cast<String>() ?? <String>[];
    if (slots.isEmpty) {
      _snack('لا توجد مواعيد متاحة حالياً للتحويل');
      return;
    }
    final diff = _onsitePrice - _phonePrice;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تحويل إلى جلسة حضورية',
            style: TextStyle(
                color: AppTheme.primaryGold, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'يُحتسب ما دفعته (${_fmt(_phonePrice)} ل.س) من قيمة الجلسة، '
              'والفرق المستحق ${_fmt(diff < 0 ? 0 : diff)} ل.س يُدفع في المكتب.',
              style: const TextStyle(
                  color: AppTheme.textWhite, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 10),
            const Text('اختر الموعد:',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
            const SizedBox(height: 6),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final sIso in slots.take(12))
                  Builder(builder: (_) {
                    final dt = DateTime.tryParse(sIso)?.toLocal();
                    if (dt == null) return const SizedBox.shrink();
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.event,
                          color: AppTheme.primaryGold, size: 18),
                      title: Text(
                        '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
                        '${dt.day.toString().padLeft(2, '0')}  —  '
                        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            color: AppTheme.textWhite, fontSize: 13),
                      ),
                      onTap: () => Navigator.pop(ctx, sIso),
                    );
                  }),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تراجع', style: TextStyle(color: AppTheme.textGrey)),
          ),
        ],
      ),
    );
    if (picked == null) return;

    final res = await legal.convertToOnsite(
      consultationId: id,
      userUid: context.read<AuthProvider>().userModel?.uid ?? '',
      slot: picked,
    );
    if (!mounted) return;
    if (res != null) {
      _snack('🔀 حُوّلت لجلسة حضورية — بانتظار تأكيد المحامي للموعد');
      _loadAll();
    } else {
      final e = legal.error ?? '';
      _snack(e.contains('SLOT_NO_LONGER_AVAILABLE')
          ? 'حُجز هذا الموعد للتو — اختر موعداً آخر'
          : (e.isEmpty ? 'فشل التحويل' : e));
    }
  }

  /// 🚫 إلغاء الطلب (الإيدج يسمح 0→3 ولم يكن له زر إطلاقاً)
  Future<void> _cancelConsultation(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('إلغاء الطلب', style: TextStyle(color: AppTheme.errorRed, fontSize: 16)),
        content: const Text(
            'سيُلغى طلب الاستشارة. المبلغ المدفوع يبقى مسجّلاً لدى الإدارة للتسوية.',
            style: TextStyle(color: AppTheme.textWhite, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع', style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
              child: const Text('تأكيد الإلغاء', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (ok != true) return;
    final done = await context.read<LegalProvider>()
        .updateConsultationStatus(
          id: id, status: 3,
          actorUid: context.read<AuthProvider>().userModel?.uid ?? '');
    if (!mounted) return;
    _snack(done ? '🚫 أُلغي الطلب' : 'فشل الإلغاء');
    if (done) _loadAll();
  }

  Widget _buildNewButtons() {
    return Row(children: [
      Expanded(child: GestureDetector(
        onTap: () { if (_guardPending(0)) return; _serviceType = 0; _goTo(1); },
        child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.08), borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            const Icon(Icons.phone_in_talk, color: AppTheme.primaryGold, size: 32),
            const SizedBox(height: 8),
            const Text('استشارة هاتفية', style: TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text('${_fmt(_phonePrice)} ل.س', style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: AppTheme.radiusXL),
              child: const Text('الأكثر طلباً', style: TextStyle(color: AppTheme.deepBlack, fontSize: 9, fontWeight: FontWeight.bold))),
          ])))),
      AppTheme.gapWidthMedium,
      Expanded(child: GestureDetector(
        onTap: () { if (_guardPending(1)) return; _serviceType = 1; _goTo(1); },
        child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.08), borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            const Icon(Icons.business, color: AppTheme.primaryGold, size: 32),
            const SizedBox(height: 8),
            const Text('جلسة حضورية', style: TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text('${_fmt(_onsitePrice)} ل.س', style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
          ])))),
    ]);
  }

  // ── الإرشادات ──
  Widget _buildExplanation() {
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Text(_serviceType == 0 ? '⚖️ استشارة هاتفية' : '🏢 جلسة حضورية', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(0))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(child: Icon(Icons.gavel, color: AppTheme.primaryGold, size: 48)),
        AppTheme.gapHeightLarge,
        _infoCard(Icons.phone_in_talk, 'استشارة هاتفية', '${_fmt(_phonePrice)} ل.س', '$_durationMins دقيقة', ['محادثة مع محامي المكتب', 'للأسئلة القانونية البسيطة', 'تجديد بـ ${_fmt(_renewPrice)} ل.س كل $_durationMins دقيقة', 'المحادثة تبقى 7 أيام']),
        AppTheme.gapHeightMedium,
        _infoCard(Icons.business, 'جلسة حضورية', '${_fmt(_onsitePrice)} ل.س', 'ساعة', ['اجتماع في مكتب المحامي', 'للمشاكل المعقدة', 'حجز موعد مسبق']),
        AppTheme.gapHeightXL,
        Container(width: double.infinity, padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('⚠️ الخطوات:', style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(height: 6),
            Text('1️⃣ اكتب موضوع الاستشارة وأرفق المستندات', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('2️⃣ ادفع المبلغ — الإدارة تؤكد (عادة خلال ساعة)', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
            Text('3️⃣ أرسل الطلب للمحامي — يدرس ويفتح المحادثة', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
          ])),
        AppTheme.gapHeightLarge,
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          // هاتفية → فحص قديمة / حضورية → موضوع مباشرة (مع حارس الدفعة المعلّقة)
          onPressed: () { if (_guardPending(_serviceType)) return; _goTo(_serviceType == 0 ? 3 : 7); },
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: const Text('متابعة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])));
  }

  Widget _infoCard(IconData icon, String title, String price, String dur, List<String> pts) {
    return Container(padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: AppTheme.primaryGold, size: 20), AppTheme.gapWidthSmall, Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 14)), const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.primaryGold, borderRadius: AppTheme.radiusXL), child: Text(price, style: const TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold, fontSize: 11)))]),
        Text('⏱️ $dur', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
        const SizedBox(height: 8),
        ...pts.map((p) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• $p', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)))),
      ]));
  }

  // ── اختيار النوع ──
  Widget _buildChooseType() {
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('اختر النوع', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(1))),
      body: Padding(padding: AppTheme.paddingAllLarge, child: Column(children: [AppTheme.gapHeightXL,
        _typeCard(Icons.phone_in_talk, 'استشارة هاتفية', '${_fmt(_phonePrice)} ل.س — $_durationMins دقيقة', 0),
        AppTheme.gapHeightLarge,
        _typeCard(Icons.business, 'جلسة حضورية', '${_fmt(_onsitePrice)} ل.س — ساعة', 1),
      ])));
  }

  Widget _typeCard(IconData icon, String title, String sub, int sType) {
    return GestureDetector(onTap: () { if (_guardPending(sType)) return; _serviceType = sType; _goTo(sType == 0 ? 3 : 7); },
      child: Container(width: double.infinity, padding: AppTheme.paddingAllLarge,
        decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusLarge, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundColor: AppTheme.primaryGold.withOpacity(0.2), child: Icon(icon, color: AppTheme.primaryGold, size: 28)),
          AppTheme.gapWidthMedium,
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(sub, style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12, fontWeight: FontWeight.bold)),
          ])),
          const Icon(Icons.arrow_forward_ios, color: AppTheme.primaryGold, size: 16),
        ])));
  }

  // ── فحص المحادثات السابقة (هاتفية فقط) ──
  Widget _buildPreviousChats() {
    final chats = _previousChats;
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('استشارة هاتفية', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(1))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (chats.isNotEmpty) ...[
          Text(chats.length == 1 ? 'لديك محادثة سابقة' : 'لديك ${chats.length} محادثات سابقة', style: const TextStyle(color: AppTheme.primaryGold, fontSize: 16, fontWeight: FontWeight.bold)),
          AppTheme.gapHeightSmall,
          Text('هل تريد متابعة إحداها؟ (نفس المحامي — تجديد ${_fmt(_renewPrice)} ل.س)', style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
          AppTheme.gapHeightMedium,
          ...chats.map((c) {
            final id = c['id'].toString();
            final sel = _continueChatId == id;
            final subject = (c['subject'] ?? '').toString();
            final alias = (c['lawyer_alias'] ?? 'محامي المكتب').toString();
            final dt = DateTime.tryParse(c['chat_started_at']?.toString() ?? '');
            final daysLeft = dt != null ? 7 - DateTime.now().difference(dt).inDays : 0;
            return GestureDetector(onTap: () => setState(() => _continueChatId = sel ? null : id),
              child: Container(margin: const EdgeInsets.only(bottom: 8), padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(color: sel ? AppTheme.primaryGold.withOpacity(0.12) : AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: sel ? AppTheme.primaryGold : Colors.white12)),
                child: Row(children: [
                  Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? AppTheme.primaryGold : AppTheme.textGrey),
                  AppTheme.gapWidthSmall,
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('⚖️ $alias  •  📅 $daysLeft أيام متبقية', style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
                  ])),
                ])));
          }),
          AppTheme.gapHeightLarge,
          if (_continueChatId != null) SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
            onPressed: () { if (_guardPending(0)) return; _isContinuing = true; _goTo(5); }, // مباشر للدفع
            icon: const Icon(Icons.payment, color: Colors.black),
            label: Text('متابعة — دفع ${_fmt(_renewPrice)} ل.س', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
          )),
          AppTheme.gapHeightMedium,
        ],
        SizedBox(width: double.infinity, height: 48, child: OutlinedButton.icon(
          onPressed: () { if (_guardPending(0)) return; _isContinuing = false; _continueChatId = null; _goTo(4); },
          icon: const Icon(Icons.add, color: AppTheme.primaryGold),
          label: Text(chats.isNotEmpty ? 'لا — أريد استشارة جديدة' : 'بدء استشارة جديدة', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold)),
        )),
      ])));
  }

  // ── موضوع الاستشارة ──
  Widget _buildSubjectForm() {
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: Text(_serviceType == 0 ? 'استشارة هاتفية' : 'جلسة حضورية', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(_serviceType == 0 ? 3 : 7))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('موضوع الاستشارة:', style: TextStyle(color: AppTheme.primaryGold, fontSize: 15, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        Wrap(spacing: 6, runSpacing: 6, children: _topicChips.map((c) => GestureDetector(onTap: () {
          final cur = _subjectCtrl.text;
          setState(() => _subjectCtrl.text = cur.isEmpty ? c : '$cur — $c');
        }, child: Chip(label: Text(c, style: const TextStyle(fontSize: 11)), backgroundColor: AppTheme.primaryGold.withOpacity(0.1), side: BorderSide(color: AppTheme.primaryGold.withOpacity(0.3))))).toList()),
        AppTheme.gapHeightSmall,
        TextField(controller: _subjectCtrl, maxLines: 4, maxLength: 500, style: const TextStyle(color: AppTheme.textWhite),
          decoration: const InputDecoration(hintText: 'اشرح مشكلتك القانونية...', filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
        AppTheme.gapHeightLarge,
        const Text('المستندات (اختياري — حتى 5 صور):', style: TextStyle(color: AppTheme.primaryGold, fontSize: 14, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        GestureDetector(onTap: _pickAttachments, child: Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusMedium, border: Border.all(color: Colors.white12)),
          child: Row(children: [const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.primaryGold), AppTheme.gapWidthSmall, Text('إضافة صور (${_attachments.length}/5)', style: const TextStyle(color: AppTheme.textGrey))]))),
        if (_attachments.isNotEmpty) ...[AppTheme.gapHeightSmall,
          Wrap(spacing: 8, runSpacing: 8, children: _attachments.asMap().entries.map((e) => Stack(children: [
            ClipRRect(borderRadius: AppTheme.radiusSmall, child: kIsWeb ? Image.network(e.value.path, width: 60, height: 60, fit: BoxFit.cover) : Image.file(File(e.value.path), width: 60, height: 60, fit: BoxFit.cover)),
            Positioned(top: -5, right: -5, child: GestureDetector(onTap: () => setState(() => _attachments.removeAt(e.key)), child: const CircleAvatar(radius: 10, backgroundColor: AppTheme.errorRed, child: Icon(Icons.close, size: 12, color: Colors.white)))),
          ])).toList())],
        if (_isLateNight) ...[AppTheme.gapHeightMedium,
          Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.warningOrange.withOpacity(0.1), borderRadius: AppTheme.radiusSmall, border: Border.all(color: AppTheme.warningOrange.withOpacity(0.4))),
            child: const Row(children: [Icon(Icons.nightlight_round, color: AppTheme.warningOrange, size: 18), AppTheme.gapWidthSmall, Expanded(child: Text('الوقت متأخر — قد يتأخر الرد', style: TextStyle(color: AppTheme.warningOrange, fontSize: 12)))]))],
        AppTheme.gapHeightLarge,
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: () {
            if (_subjectCtrl.text.trim().length < 10) { _snack('اكتب وصف أطول (10 أحرف)'); return; }
            // 🎁 رصيد ممنوح ⇒ لا شاشة دفع، يُرسل الطلب مباشرة
            if (_hasCredit(_serviceType)) { _submitConsultation(); return; }
            _goTo(5);
          },
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: Text(_hasCredit(_serviceType) ? 'إرسال الطلب (مجاناً 🎁)' : 'متابعة للدفع',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])));
  }

  // ── الدفع ──
  Widget _buildPaymentForm() {
    final config = context.watch<ConfigProvider>().config;
    final channels = config?.enabledPayChannels ?? [];
    final price = _isContinuing ? _renewPrice : _priceFor(_serviceType);
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('الدفع', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold), onPressed: () => _goTo(_isContinuing ? 3 : 4))),
      body: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.primaryGold.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.primaryGold.withOpacity(0.3))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_isContinuing ? '🔄 تجديد محادثة' : (_serviceType == 0 ? '📞 استشارة هاتفية' : '🏢 جلسة حضورية'), style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
              Text('$price ل.س', style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 18))]),
            if (!_isContinuing && _subjectCtrl.text.isNotEmpty) ...[const SizedBox(height: 4), Text(_subjectCtrl.text.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11))],
          ])),
        AppTheme.gapHeightLarge,
        const Text('قناة الدفع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        ...channels.map((e) {
          final sel = _channel == e.key; final name = (e.value['name'] ?? e.key).toString(); final icon = (e.value['icon'] ?? '💳').toString();
          return GestureDetector(onTap: () => setState(() => _channel = e.key), child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: sel ? AppTheme.primaryGold.withOpacity(0.15) : AppTheme.surfaceBlack, borderRadius: AppTheme.radiusSmall, border: Border.all(color: sel ? AppTheme.primaryGold : Colors.white12)),
            child: Row(children: [Text(icon, style: const TextStyle(fontSize: 16)), AppTheme.gapWidthSmall, Expanded(child: Text(name, style: TextStyle(color: sel ? AppTheme.primaryGold : AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 13))),
              Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked, color: sel ? AppTheme.primaryGold : AppTheme.textGrey, size: 18)])));
        }),
        // 2026-08-14: بطاقة بيانات القناة المختارة — كانت مفقودة كلياً من هذه
        // الشاشة (المستخدم يختار «تحويل رصيد» ولا يرى أي رقم يحوّل إليه).
        if (_channel.isNotEmpty) ...[
          AppTheme.gapHeightMedium,
          _channelDetailsCard(channels),
        ],
        AppTheme.gapHeightMedium,
        if (_needsSenderPhone) ...[
          const Text('رقم الهاتف المحوَّل منه (اختياري):', style: TextStyle(color: AppTheme.textWhite, fontSize: 13)),
          AppTheme.gapHeightSmall,
          TextField(controller: _senderPhoneCtrl, keyboardType: TextInputType.phone, style: const TextStyle(color: AppTheme.textWhite), decoration: const InputDecoration(hintText: '09xxxxxxxx', prefixIcon: Icon(Icons.phone, color: AppTheme.primaryGold), filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
          AppTheme.gapHeightMedium],
        const Text('رقم العملية:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        TextField(controller: _refCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppTheme.textWhite), decoration: const InputDecoration(hintText: 'رقم الإيصال', prefixIcon: Icon(Icons.tag, color: AppTheme.primaryGold), filled: true, fillColor: AppTheme.surfaceBlack, border: OutlineInputBorder())),
        AppTheme.gapHeightMedium,
        const Text('إثبات الدفع:', style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
        AppTheme.gapHeightSmall,
        GestureDetector(onTap: _pickProof, child: Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.surfaceBlack, borderRadius: AppTheme.radiusSmall, border: Border.all(color: _proofImage != null ? AppTheme.successGreen : Colors.white12)),
          child: Row(children: [Icon(_proofImage == null ? Icons.upload_file : Icons.check_circle, color: _proofImage == null ? AppTheme.textGrey : AppTheme.successGreen), AppTheme.gapWidthSmall, Text(_proofImage == null ? 'اختر صورة إثبات الدفع' : 'تم ✓', style: const TextStyle(color: AppTheme.textGrey, fontSize: 13))]))),
        AppTheme.gapHeightLarge,
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
          onPressed: _submitting ? null : _pay,
          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.payment, color: Colors.black),
          label: Text(_submitting ? 'جارٍ...' : 'ادفع $price ل.س', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])));
  }

  /// بطاقة بيانات قناة الدفع المختارة (رقم التحويل + التعليمات).
  /// أُضيفت 2026-08-14: قناة «تحويل رصيد» صارت تعتمد رقم المكتب الموحّد
  /// (payChannels.balance.number) مع توافق عكسي للحقلين القديمين.
  Widget _channelDetailsCard(List<MapEntry<String, Map<String, dynamic>>> channels) {
    Map<String, dynamic>? data;
    for (final e in channels) {
      if (e.key == _channel) { data = e.value; break; }
    }
    if (data == null) return const SizedBox.shrink();

    final rows = <(String, String)>[];
    void add(String label, dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) rows.add((label, s));
    }

    switch (_channel) {
      case 'balance':
        if ((data['number'] ?? '').toString().trim().isNotEmpty) {
          add('رقم المكتب', data['number']);
        } else {
          add('سيرياتل', data['syriatel_number']);
          add('MTN', data['mtn_number']);
        }
        break;
      case 'syriatel_cash':
        add('رقم التحويل', data['number']);
        break;
      case 'sham_cash':
        add('رقم الحساب', data['account_number']);
        break;
      case 'haram':
        add('اسم المستقبل', data['recipient_name']);
        add('رقم المستقبل', data['recipient_phone']);
        break;
      case 'bank':
        add('البنك', data['bank_name']);
        add('صاحب الحساب', data['account_holder']);
        add('رقم الحساب', data['account_number']);
        add('IBAN', data['iban']);
        add('الفرع', data['branch']);
        break;
    }

    final instructions = (data['instructions'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text((data['icon'] ?? '💳').toString(), style: const TextStyle(fontSize: 18)),
          AppTheme.gapWidthSmall,
          Text((data['name'] ?? _channel).toString(),
              style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const Divider(color: Colors.white12, height: 16),
        if (rows.isEmpty)
          const Text('⚠️ لم يتم إعداد بيانات هذه القناة بعد. يرجى التواصل مع الإدارة.',
              style: TextStyle(color: AppTheme.warningOrange, fontSize: 12))
        else
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Text('${r.$1}: ', style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
                  Expanded(child: SelectableText(r.$2,
                      style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 14))),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AppTheme.primaryGold, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'نسخ',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: r.$2));
                      _snack('📋 تم نسخ ${r.$1}');
                    },
                  ),
                ]),
              )),
        if (instructions.isNotEmpty) ...[
          AppTheme.gapHeightSmall,
          Text(instructions, style: const TextStyle(color: AppTheme.textGrey, fontSize: 11, height: 1.5)),
        ],
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🗓️ اختيار موعد الجلسة الحضورية (2026-08-14)
  // العميل يرى **فقط** الأوقات التي فتحها المحامي وغير المحجوزة —
  // فلا تفاوض ولا انتظار موافقة، ولا جلسة بلا موعد كما كان سابقاً.
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSlotPicker() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('اختر موعد الجلسة',
            style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold),
          onPressed: () => _goTo(1),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: context.read<LegalProvider>().fetchFreeSlots(days: 14),
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold));
          }
          final slots = (snap.data?['slots'] as List?)?.cast<String>() ?? <String>[];
          _slotLawyerAlias = (snap.data?['lawyer_alias'] ?? '').toString();

          if (slots.isEmpty) {
            return Center(
              child: Padding(
                padding: AppTheme.paddingAllXL,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.event_busy, size: 60, color: AppTheme.warningOrange),
                  AppTheme.gapHeightLarge,
                  const Text('لا توجد مواعيد متاحة حالياً',
                      style: TextStyle(color: AppTheme.textWhite, fontSize: 17, fontWeight: FontWeight.bold)),
                  AppTheme.gapHeightSmall,
                  const Text('جميع المواعيد محجوزة أو خارج أوقات الدوام.\nجرّب لاحقاً أو اختر استشارة هاتفية.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textGrey, fontSize: 13, height: 1.6)),
                  AppTheme.gapHeightXL,
                  SizedBox(width: double.infinity, height: 46, child: OutlinedButton.icon(
                    onPressed: () { setState(() { _serviceType = 0; }); _goTo(3); },
                    icon: const Icon(Icons.phone_in_talk, color: AppTheme.primaryGold),
                    label: Text('استشارة هاتفية بدلاً منها (${_fmt(_phonePrice)} ل.س)',
                        style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold)),
                  )),
                ]),
              ),
            );
          }

          // تجميع السلوتات حسب اليوم
          final byDay = <String, List<DateTime>>{};
          for (final s in slots) {
            final dt = DateTime.tryParse(s)?.toLocal();
            if (dt == null) continue;
            final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
            byDay.putIfAbsent(key, () => []).add(dt);
          }
          const dayNames = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

          return ListView(padding: AppTheme.paddingAllLarge, children: [
            Container(
              padding: AppTheme.paddingAllMedium,
              decoration: BoxDecoration(
                color: AppTheme.primaryGold.withOpacity(0.08),
                borderRadius: AppTheme.radiusMedium,
                border: Border.all(color: AppTheme.primaryGold.withOpacity(0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.business, color: AppTheme.primaryGold, size: 20),
                AppTheme.gapWidthSmall,
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('جلسة حضورية — ${_fmt(_onsitePrice)} ل.س',
                      style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 14)),
                  if (_slotLawyerAlias.isNotEmpty)
                    Text('⚖️ $_slotLawyerAlias',
                        style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12)),
                ])),
              ]),
            ),
            AppTheme.gapHeightMedium,
            const Text('اختر الوقت المناسب لك:',
                style: TextStyle(color: AppTheme.textWhite, fontSize: 13, fontWeight: FontWeight.bold)),
            AppTheme.gapHeightSmall,
            ...byDay.entries.map((e) {
              final first = e.value.first;
              final dayLabel = '${dayNames[first.weekday - 1]}  ${first.day}/${first.month}';
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AppTheme.gapHeightSmall,
                Text(dayLabel,
                    style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: e.value.map((dt) {
                  final iso = dt.toUtc().toIso8601String();
                  final sel = _selectedSlot != null &&
                      DateTime.tryParse(_selectedSlot!)?.toUtc() == dt.toUtc();
                  return GestureDetector(
                    onTap: () => setState(() => _selectedSlot = iso),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? AppTheme.primaryGold : AppTheme.surfaceBlack,
                        borderRadius: AppTheme.radiusMedium,
                        border: Border.all(color: sel ? AppTheme.primaryGold : Colors.white24),
                      ),
                      child: Text(
                        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            color: sel ? Colors.black : AppTheme.textWhite,
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  );
                }).toList()),
              ]);
            }),
            AppTheme.gapHeightXL,
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
              onPressed: _selectedSlot == null ? null : () => _goTo(4),
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              label: Text(_selectedSlot == null ? 'اختر موعداً للمتابعة' : 'متابعة',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
            )),
            AppTheme.gapHeightSmall,
            const Center(
              child: Text('💡 الجلسة الحضورية موعد في المكتب — لا محادثة فيها',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
            ),
            const SizedBox(height: 20),
          ]);
        },
      ),
    );
  }

  // ── النجاح ──
  Widget _buildSuccess() {
    // _viewingPending = وصلنا لهذه الشاشة من بانر «دفعة قيد الانتظار» أو من
    // حارس الاعتراض، لا من إرسال دفعة جديدة للتو. المحتوى واحد والعنوان يختلف.
    final pending = _viewingPending ? _pendingPayment : null;
    // عند عرض دفعة معلّقة نستنتج نوعها من meta.continue_chat لا من حالة الـ wizard
    final isCont = _viewingPending
        ? ((pending?['meta'] as Map?)?['continue_chat'] ?? '').toString().isNotEmpty
        : _isContinuing;

    final String? pendingLine = pending == null
        ? null
        : '${(pending['amt'] as num?)?.toStringAsFixed(0) ?? '—'} ل.س'
            ' — ${(pending['pkg'] ?? 0) == 0 ? 'استشارة هاتفية' : 'جلسة حضورية'}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // زر الرجوع يعيد للرئيسية بدل الخروج من الشاشة بحالة وسيطة
        _resetWizard();
        _loadAll();
      },
      child: Scaffold(backgroundColor: AppTheme.scaffoldBackground, body: Center(child: SingleChildScrollView(padding: AppTheme.paddingAllLarge, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(pending != null ? Icons.hourglass_top : Icons.check_circle,
          color: pending != null ? AppTheme.warningOrange : AppTheme.successGreen, size: 64),
      AppTheme.gapHeightLarge,
      Text(pending != null ? '⏳ دفعتك قيد المراجعة' : '✅ تم إرسال الدفعة',
          style: const TextStyle(color: AppTheme.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
      if (pendingLine != null) ...[
        AppTheme.gapHeightSmall,
        Text(pendingLine, style: const TextStyle(color: AppTheme.textGrey, fontSize: 14)),
      ],
      AppTheme.gapHeightMedium,
      Container(width: double.infinity, padding: AppTheme.paddingAllMedium, decoration: BoxDecoration(color: AppTheme.infoBlue.withOpacity(0.1), borderRadius: AppTheme.radiusMedium, border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isCont ? '🔄 تجديد محادثة سابقة' : '📋 الخطوات التالية:', style: const TextStyle(color: AppTheme.infoBlue, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          const Text('1️⃣ الإدارة تراجع الدفعة (عادة خلال ساعة)', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
          Text(isCont ? '2️⃣ بعد التأكيد → تُفتح المحادثة تلقائياً' : '2️⃣ بعد التأكيد → ترسل الطلب للمحامي', style: const TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
          if (!isCont) const Text('3️⃣ المحامي يدرس ويفتح المحادثة', style: TextStyle(color: AppTheme.textWhite, fontSize: 12, height: 1.8)),
        ])),
      AppTheme.gapHeightXL,
      SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
        onPressed: () { _resetWizard(); _loadAll(); },
        icon: const Icon(Icons.home, color: Colors.black),
        label: const Text('العودة للرئيسية', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
      )),
      if (pending != null) ...[
        AppTheme.gapHeightSmall,
        SizedBox(width: double.infinity, height: 44, child: OutlinedButton.icon(
          onPressed: () { _resetWizard(); _loadAll(); },
          icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
          label: const Text('تحديث الحالة', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold)),
        )),
      ],
      AppTheme.gapHeightMedium,
      const Text('ستصلك إشعار عند كل خطوة 👆', style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
    ])))),
    );
  }

  void _snack(String m) { if (!mounted) return; AppTheme.showSnackBar(context, SnackBar(content: Text(m))); }
}
