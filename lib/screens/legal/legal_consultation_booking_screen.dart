import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../core/validation/input_validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../models/config_model.dart';
import '../../providers/legal_provider.dart';
import '../../providers/payment_provider.dart';
import '../../models/payment_model.dart';
import '../../services/storage_service.dart';
import '../../core/utils/error_utils.dart';

/// شاشة الاستشارة القانونية — تدفق بسيط ونظيف
///
/// الشاشة الرئيسية تعرض:
/// 1. إذا في دفعة معلقة → "بانتظار التأكيد"
/// 2. إذا في دفعة مقبولة بدون استشارة → "إرسال الطلب"
/// 3. إذا في استشارة نشطة → "فتح المحادثة"
/// 4. أزرار "استشارة جديدة" / "جلسة حضورية"
class LegalConsultationBookingScreen extends StatefulWidget {
  final String initialFlow;
  final String parentConsultationId;
  final String appointmentId;
  const LegalConsultationBookingScreen({
    super.key,
    this.initialFlow = '',
    this.parentConsultationId = '',
    this.appointmentId = '',
  });
  @override
  State<LegalConsultationBookingScreen> createState() => _State();
}

class _State extends State<LegalConsultationBookingScreen>
    with WidgetsBindingObserver {
  final _storage = StorageService();
  bool _loading = true;

  // البيانات
  Map<String, dynamic>? _pendingPayment;    // دفعة قيد المراجعة (أقدم نوع)
  Map<String, dynamic>? _pendingV2Intent;
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
  String? _selectedDayKey;      // 📅 UI-CAL-001: اليوم المختار في شريط التقويم
  Future<Map<String, dynamic>>? _slotsFuture; // يمنع إعادة الجلب مع كل setState
  String _slotLawyerAlias = ''; // لقب المحامي (بلا هويته)
  int _serviceType = 0;
  bool _isContinuing = false; // متابعة محادثة قديمة
  String? _continueChatId;
  String? _v2IntentId;
  String _v2Flow = '';
  bool _allowOtherLawyer = false;
  String? _v2IdempotencyKey;
  num? _v2QuotedAmount;
  String? _rescheduleAppointmentId;
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

  /// تحديث عند عودة التطبيق للمقدمة فقط، إضافةً إلى زر التحديث والسحب اليدوي.
  /// لا يوجد مؤقّت دوري: التحديث كل 10 ثوانٍ كان يعيد بناء الشاشة أمام
  /// المستخدم ويضاعف طلبات `user_payments` و`list_my_consultations` بلا داعٍ.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    await _loadAll();
    if (!mounted ||
        context.read<ConfigProvider>().config?.consultationFlowV2 != true ||
        widget.initialFlow.isEmpty) return;
    _v2Flow = widget.initialFlow;
    _continueChatId = widget.parentConsultationId.isEmpty
        ? null
        : widget.parentConsultationId;
    if (_v2Flow == 'phone_renew') {
      _isContinuing = true;
      _serviceType = 0;
      setState(() => _screen = 5);
    } else if (_v2Flow == 'onsite_convert' ||
        _v2Flow == 'onsite_reschedule') {
      _isContinuing = false;
      _serviceType = 1;
      _rescheduleAppointmentId = widget.appointmentId.isEmpty
          ? null
          : widget.appointmentId;
      setState(() {
        _slotsFuture = null;
        _screen = 7;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 🔄 SYNC-002: يشمل شاشة النجاح أيضاً — المستخدم يبدّل للواتساب
    // وينتظر رد المحامي ثم يعود، فيجب أن يرى الحالة الجديدة فوراً.
    if (state == AppLifecycleState.resumed &&
        mounted &&
        !_submitting &&
        (_screen == 0 || _screen == 6)) {
      _loadAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  String _newUuid() {
    final b = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

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
      // ═══════════════════════════════════════════════════════════════
      // 🔴 UX-003 (2026-08-15) — السبب الجذري الحقيقي لبلاغ المالك
      // ═══════════════════════════════════════════════════════════════
      // «ما طلعلي إنو في طلب دفع قيد المراجعة» رغم وجود الدفعة فعلاً.
      //
      // كان الجلب عبر REST مباشرةً: `.from(payments).eq('uid', uid)`.
      // لكن سياسة RLS على الجدول هي `auth.uid() = uid`، وتطبيقنا يسجّل
      // الدخول **بجلسة مخصّصة** (staff_session_token) لا بجلسة Supabase
      // ⇒ `auth.uid()` تساوي **NULL** ⇒ الاستعلام يُرجع **صفر صفوف دائماً**
      // بلا أي خطأ ظاهر (فشل صامت كامل — أخطر أنواع الأعطال، §13).
      //
      // النتيجة المتسلسلة: `_pendingByType` فارغة أبداً ⇒ لا بطاقة «دفعة
      // قيد المراجعة»، ولا يعمل حارس `_guardPending`، فيمرّ المستخدم
      // لشاشة دفع جديدة ويُفاجأ برفض السيرفر.
      //
      // الحل: نفس مسار بقية الشاشات — Edge Function بمفتاح الخدمة يتخطّى
      // RLS بعد التحقق من الجلسة (`user_payments` → get_user_payments_internal).
      final payRes = await SupabaseService().invokeFunction('user-account',
          body: {'action': 'user_payments', 'user_uid': uid});
      final payMap = payRes.data is Map
          ? Map<String, dynamic>.from(payRes.data as Map)
          : <String, dynamic>{};
      final allPays = (payMap['payments'] as List?) ?? const [];
      // نُبقي دفعات الاستشارة فقط (tp=2) بترتيب الأحدث أولاً — كان
      // الفلتر والترتيب في الاستعلام، وصارا هنا بعد تغيير المصدر.
      final pays = allPays
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((m) => (m['tp'] ?? 0) == 2)
          .toList()
        ..sort((a, b) =>
            (b['ts_crt'] ?? '').toString().compareTo((a['ts_crt'] ?? '').toString()));

      // 🔴 UX-003: الاستشارات تُجلب **قبل** حلقة الدفعات لأن الحلقة تحتاج
      // معرفة الدفعات المرتبطة باستشارة. (كانت تُجلب بعدها، فاضطر الكود
      // لاستعلام REST مكسور داخل الحلقة.)
      final consultRes = await SupabaseService().invokeFunction('legal-actions',
          body: {'action': 'list_my_consultations', 'user_uid': uid});
      final cData = consultRes.data as Map<String, dynamic>?;
      final all = cData != null && cData['success'] == true
          ? List<Map<String, dynamic>>.from((cData['consultations'] as List?) ?? [])
          : <Map<String, dynamic>>[];

      // معرّفات الدفعات التي لها استشارة مرتبطة فعلاً.
      final linkedPaymentIds = all
          .map((c) => c['payment_id']?.toString())
          .whereType<String>()
          .toSet();

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
          // 🔴 UX-003: كان هنا استعلام REST مباشر على legal_consultations
          // بسياسة `auth.uid() = user_uid` — و`auth.uid()` تساوي NULL مع
          // جلستنا المخصّصة ⇒ يُرجع فارغاً **دائماً** ⇒ كل دفعة مقبولة
          // تُحسب «بلا استشارة مربوطة» فتظهر بطاقة «أرسل طلبك» خطأً.
          // الآن نستخدم `payment_id` من قائمة الاستشارات المحمَّلة أعلاه
          // عبر الإيدج (بمفتاح الخدمة) — بلا نداء شبكي إضافي أصلاً.
          if (!linkedPaymentIds.contains(m['id']?.toString())) approved = m;
        } else if (m['sts'] == 2 && rejected == null) {
          rejected = m;
        }
      }

      // الاستشارات النشطة (حُمِّلت أعلاه قبل حلقة الدفعات — UX-003)
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

      Map<String, dynamic>? pendingV2Intent;
      final pendingIntentId = pending?['consultation_intent_id']?.toString() ?? '';
      if (pendingIntentId.isNotEmpty) {
        final intentRes = await SupabaseService().invokeFunction('legal-actions', body: {
          'action': 'get_consultation_intent_v2',
          'user_uid': uid,
          'intent_id': pendingIntentId,
        });
        final intentData = intentRes.data as Map<String, dynamic>?;
        if (intentData?['success'] == true && intentData?['intent'] is Map) {
          pendingV2Intent = Map<String, dynamic>.from(intentData!['intent'] as Map);
        }
      }

      // 🔄 SYNC-002: هل اعتُمدت دفعة كان المستخدم ينتظرها؟
      // كان عليه أن يعود يدوياً للرئيسية ثم يضغط «إرسال الطلب للمحامي».
      // الآن ننقله تلقائياً فور الاعتماد وهو على شاشة الانتظار.
      final wasWaitingPayment = _screen == 6 && _pendingPayment != null;
      final nowApproved = approved != null &&
          (_pendingByType[(approved['pkg'] ?? 0) as int] == null);

      if (mounted) setState(() {
        _credits = credits;
        _pendingPayment = pending;
        _pendingV2Intent = pendingV2Intent;
        _pendingByType = pendingByType;
        _rejectedPayment = rejected;
        _approvedPayment = approved;
        _activeConsultation = active;
        _rejectedConsultation = rejectedConsult;
        _needInfoConsultation = needInfo;
        _previousChats = previous;
        _loading = false;
      });

      // 🔄 SYNC-002: اعتُمدت دفعته وهو ينتظر ⇒ ننقله لشاشة كتابة الموضوع
      // مباشرةً بدل أن يبقى على «قيد المراجعة» ويكتشف بنفسه أن عليه
      // العودة والضغط على «إرسال الطلب للمحامي».
      if (mounted && wasWaitingPayment && nowApproved) {
        final pkg = (approved['pkg'] ?? 0) as int;
        setState(() {
          _serviceType = pkg;
          _viewingPending = false;
          _screen = 4; // نموذج موضوع الاستشارة
        });
        AppTheme.showSnackBar(context, const SnackBar(
          content: Text('✅ اعتُمدت دفعتك — اكتب موضوع استشارتك وأرسلها للمحامي'),
          backgroundColor: AppTheme.successGreen,
        ));
      }
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

  /// 💳 PAY-001: هل لديه دفعة **مقبولة** لهذا النوع لم تُربط باستشارة بعد؟
  ///
  /// `_load()` يملأ `_approvedPayment` بدفعة sts=1 غير موجودة في
  /// `linkedPaymentIds` — أي دُفعت واعتُمدت ولم يُرسَل طلبها بعد.
  /// وجودها يعني أن المستخدم **دفع فعلاً**، فمطالبته بالدفع ثانيةً خطأ.
  /// نقارن النوع (pkg) كي لا تُستهلك دفعة هاتفية في حجز حضوري أغلى.
  bool _hasApprovedPaymentFor(int serviceType) {
    final p = _approvedPayment;
    if (p == null) return false;
    return ((p['pkg'] ?? 0) as int) == serviceType;
  }

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
    _screen = 0; _serviceType = 0; _isContinuing = false; _continueChatId = null;
    _v2IntentId = null; _v2Flow = ''; _allowOtherLawyer = false;
    _v2IdempotencyKey = null;
    _v2QuotedAmount = null; _rescheduleAppointmentId = null;
    _viewingPending = false; _selectedSlot = null;
    // 📅 UI-CAL-001: تصفير حالة التقويم وكاش المواعيد — وإلا عُرضت مواعيد
    // قديمة (وربما محجوزة الآن) عند بدء حجز جديد.
    _selectedDayKey = null; _slotsFuture = null;
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

  Future<List<String>?> _uploadAttachments() async {
    if (_attachments.isEmpty) return [];
    final paths = <String>[];

    // التطبيق يستخدم staff_session لا Supabase Auth JWT، لذلك الرفع المباشر
    // إلى consultation_files كان يُرفض بـRLS وتُنشأ الاستشارة بلا الصورة.
    // الرفع الآن عبر legal-actions بعد التحقق من جلسة المستخدم، وأي فشل
    // يوقف إرسال الطلب بالكامل كي لا يصل للمحامي ناقصاً بصمت.
    for (final file in _attachments) {
      try {
        final bytes = kIsWeb
            ? await file.readAsBytes()
            : await (await _storage.compressImage(File(file.path)) ??
                    File(file.path))
                .readAsBytes();
        final ext = file.name.toLowerCase().split('.').last;
        final contentType = ext == 'png'
            ? 'image/png'
            : ext == 'webp'
                ? 'image/webp'
                : 'image/jpeg';
        final res = await SupabaseService().invokeFunction(
          'legal-actions',
          body: {
            'action': 'upload_consultation_attachment',
            'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
            'attachment_base64': base64Encode(bytes),
            'attachment_content_type': contentType,
          },
        );
        final data = res.data is Map
            ? Map<String, dynamic>.from(res.data as Map)
            : null;
        final path = data?['path']?.toString() ?? '';
        if (data?['success'] != true || path.isEmpty) {
          throw Exception('ATTACHMENT_UPLOAD_FAILED');
        }
        paths.add(path);
      } catch (_) {
        if (paths.isNotEmpty) {
          try {
            await SupabaseService().invokeFunction(
              'legal-actions',
              body: {
                'action': 'discard_consultation_attachments',
                'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
                'paths': paths,
              },
            );
          } catch (_) {
            // التنظيف ثانوي؛ رسالة الفشل الأساسية أهم للمستخدم.
          }
        }
        if (mounted) {
          _snack('تعذّر رفع المستندات — لم يتم إرسال الطلب، حاول مجدداً');
        }
        return null;
      }
    }
    return paths;
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

  Future<void> _payV2(String ref) async {
    setState(() => _submitting = true);
    final user = context.read<AuthProvider>().userModel!;
    final flow = _v2Flow.isNotEmpty
        ? _v2Flow
        : (_isContinuing
            ? 'phone_renew'
            : (_serviceType == 1 ? 'onsite_new' : 'phone_new'));
    final attachments = _v2IntentId == null &&
            (flow == 'phone_new' || flow == 'onsite_new')
        ? await _uploadAttachments()
        : <String>[];
    if (attachments == null) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    try {
      _v2IdempotencyKey ??= _newUuid();
      if (_v2IntentId == null) {
        final prep = await SupabaseService().invokeFunction('legal-actions', body: {
          'action': 'prepare_consultation_intent_v2',
          'user_uid': user.uid,
          'flow': flow,
          'parent_consultation_id': _continueChatId,
          'subject': _subjectCtrl.text.trim(),
          'attachments': attachments,
          if (_serviceType == 1) 'slot': _selectedSlot,
          'idempotency_key': _v2IdempotencyKey,
          if (_allowOtherLawyer) 'allow_other_lawyer': true,
        });
        final p = prep.data as Map<String, dynamic>?;
        if (p?['success'] != true) {
          _snack(ErrorUtils.arabicMessage(p?['error']));
          if (mounted) setState(() => _submitting = false);
          return;
        }
        _v2IntentId = p?['intent_id']?.toString();
        _v2QuotedAmount = p?['quoted_amount'] as num?;
      }
      final proof = await _uploadProof(user.uid);
      if (proof == null) {
        _snack('فشل رفع إثبات الدفع');
        if (mounted) setState(() => _submitting = false);
        return;
      }
      String sender = '';
      if (_needsSenderPhone) sender = _normPhone(_senderPhoneCtrl.text.trim());
      final quoted = _v2QuotedAmount ??
          (flow == 'phone_renew'
              ? _renewPrice
              : flow == 'onsite_convert'
                  ? (_onsitePrice - _phonePrice).clamp(0, _onsitePrice)
                  : _priceFor(_serviceType));
      final pay = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'create_consultation_payment_v2',
        'user_uid': user.uid,
        'intent_id': _v2IntentId,
        'payment': {
          'channel': _channel,
          'proof': proof,
          'ref': ref,
          'amt': quoted,
          if (sender.isNotEmpty) 'sender_phone': sender,
        },
      });
      final data = pay.data as Map<String, dynamic>?;
      if (data?['success'] == true) {
        await _loadAll();
        if (!mounted) return;
        _goTo(6);
        _snack('✅ تم إرسال الدفعة — بانتظار اعتماد الإدارة');
      } else {
        _snack(ErrorUtils.arabicMessage(data?['error']));
      }
    } catch (e) {
      _snack(ErrorUtils.arabicMessage(e));
    }
    if (mounted) setState(() => _submitting = false);
  }

  // الدفع
  Future<void> _pay() async {
    final noSubjectNeeded = _isContinuing || _v2Flow == 'onsite_convert';
    if (_subjectCtrl.text.trim().length < 10 && !noSubjectNeeded) { _snack('اكتب موضوع الاستشارة (10 أحرف على الأقل)'); return; }
    if (_channel.isEmpty) { _snack('اختر قناة الدفع'); return; }
    if (_proofImage == null) { _snack('ارفع إثبات الدفع'); return; }
    final ref = InputValidators.normalizeDigits(_refCtrl.text.trim());
    if (ref.isEmpty) { _snack('أدخل رقم العملية'); return; }
    if (context.read<ConfigProvider>().config?.consultationFlowV2 == true) {
      await _payV2(ref);
      return;
    }

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
      if (ok) {
        // 🔒 UX-002 (2026-08-15) — السبب الجذري لبلاغ المالك:
        // «بعد إرسال إثبات الدفع أستطيع حجز استشارة أخرى».
        // كان الكود ينتقل للشاشة 6 مباشرةً **بلا إعادة تحميل**، فتبقى
        // `_pendingByType` فارغة في الذاكرة ⇒ الحارس `_guardPending` يفحص
        // قائمة قديمة ولا يجد شيئاً فيسمح بالمرور، ولا تظهر بطاقة «دفعة
        // قيد المراجعة» عند العودة للرئيسية.
        // الآن نُحدّث من السيرفر فور نجاح الدفع ⇒ الحارس يرى الدفعة
        // والبطاقة تظهر. (الحارس الخادمي CONS-001 يبقى خط الدفاع الأخير.)
        await _loadAll();
        if (!mounted) return;
        _goTo(6);
        _snack('✅ تم إرسال الدفعة — بانتظار اعتماد الإدارة');
      } else {
        _snack('فشل تسجيل الدفعة');
      }
    } catch (e) { _snack(ErrorUtils.arabicMessage(e)); }
    if (mounted) setState(() => _submitting = false);
  }

  // إرسال الاستشارة
  /// 🗣️ UX-001 (2026-08-15) — ترجمة أخطاء الحجز إلى عربية مفهومة.
  ///
  /// قاعدة: المستخدم لا يرى رمزاً إنجليزياً أبداً. كل رسالة تجيب سؤالين:
  /// **لماذا فشل؟** و**ماذا أفعل الآن؟**
  String _arabicBookingError(String code) {
    switch (code) {
      // ── حارس «نفس النوع» (CONS-001) ──
      case 'PENDING_CONSULTATION_PAYMENT_EXISTS':
        return 'لديك دفعة قيد المراجعة لهذا النوع من الاستشارة. '
            'بانتظار اعتماد الإدارة (عادةً خلال 24 ساعة) — لا حاجة للدفع مرة أخرى.';
      case 'OPEN_CONSULTATION_EXISTS':
        return 'لديك استشارة قائمة من هذا النوع لم تنتهِ بعد. '
            'أكملها أو انتظر إغلاقها قبل حجز استشارة جديدة.';
      case 'INVALID_SERVICE_TYPE':
        return 'نوع الاستشارة غير صالح — أعد اختيار (هاتفية أو حضورية).';

      // ── المواعيد ──
      case 'SLOT_NO_LONGER_AVAILABLE':
        return 'اختار شخص آخر هذا الموعد — يرجى اختيار موعد بديل';
      case 'SLOT_REQUIRED_FOR_ONSITE':
        return 'يرجى اختيار موعد الجلسة أولاً';
      case 'NO_LAWYER_AVAILABLE':
        return 'لا يوجد محامٍ متاح حالياً — حاول لاحقاً أو راسل المكتب.';

      // ── السعر والدفع ──
      case 'INVALID_PRICE':
        return 'تغيّر سعر الخدمة — أعد فتح الصفحة لتحديث السعر.';
      case 'SUBJECT_REQUIRED':
        return 'يرجى كتابة موضوع الاستشارة.';

      // ── الحساب والجلسة ──
      case 'AUTH_UID_MISMATCH':
      case 'AUTH_REQUIRED':
      case 'AUTH_TOKEN_REQUIRED':
        return 'انتهت جلستك — سجّل الدخول من جديد.';
      case 'USER_NOT_ACTIVE_OR_NOT_FOUND':
        return 'حسابك غير نشط — راجع المكتب.';

      default:
        // §13: لا نبتلع المجهول ولا نعرضه خاماً — رسالة عربية مفهومة،
        // والرمز يبقى في السجلات للتشخيص لا أمام المستخدم.
        debugPrint('⚠️ [BOOKING] رمز خطأ غير مترجَم: $code');
        return 'تعذّر إتمام الطلب — حاول مرة أخرى أو راسل المكتب.';
    }
  }

  Future<void> _submitConsultation() async {
    setState(() => _submitting = true);
    final atts = await _uploadAttachments();
    if (atts == null) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
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
        // 🗣️ UX-001 (2026-08-15): كان السطر يعرض **رمز الخطأ الإنجليزي الخام**
        // لأي حالة غير معالَجة (بلاغ المالك: «الرسالة كلها إنجليزي، بدي
        // رسالة يفهم ليش ما قدر يدفع مرة ثانية»). الآن كل رمز له نصّ عربي
        // يشرح **السبب** و**ما العمل**، والرمز الخام لا يظهر إطلاقاً.
        _snack(_arabicBookingError(err));
        if (err == 'SLOT_NO_LONGER_AVAILABLE') {
          // 📅 UI-CAL-001: نُبطل الكاش ليُعاد الجلب — الموعد صار محجوزاً
          // فعرضه ثانيةً يُوقع المستخدم في نفس الخطأ.
          setState(() { _selectedSlot = null; _slotsFuture = null; });
          _goTo(7);
        }
        // عند وجود طلب/دفعة سابقة: نحدّث القوائم فوراً ليرى المستخدم
        // بطاقة طلبه القائم بدل أن يبقى في شاشة الدفع حائراً.
        // 🔙 NAV-001 (2026-08-15) — بلاغ المالك: «وقت أرجع لورا برجّعني
        // لشاشة استشارة جديدة، والمفروض يرجّعني للمحادثة مع المحامي إن
        // انقبل الطلب، أو لشاشة الانتظار إن لم يُقبل».
        // كان `_resetWizard()` يصفّر الحالة ويعود للشاشة 0 ⇒ المستخدم
        // يجد نفسه أمام «احجز استشارة جديدة» رغم أن لديه طلباً قائماً.
        // الآن: نُحدّث من السيرفر ثم نعرض **حالته الفعلية** (بطاقة
        // الاستشارة النشطة أو الدفعة المعلّقة) عبر `_returnToCurrentState`.
        if (err == 'PENDING_CONSULTATION_PAYMENT_EXISTS' ||
            err == 'OPEN_CONSULTATION_EXISTS') {
          await _returnToCurrentState();
        }
      }
    } catch (e) { _snack(ErrorUtils.arabicMessage(e)); }
    if (mounted) setState(() => _submitting = false);
  }

  void _openChat(String id) => context.push('/legal/chat/$id');

  /// 🔙 NAV-001: هل لديه طلب قائم فعلاً؟ (استشارة نشطة أو دفعة معلّقة)
  bool _hasOngoing() =>
      _activeConsultation != null ||
      _needInfoConsultation != null ||
      _pendingByType.isNotEmpty;

  /// 🔙 NAV-001: يعيد المستخدم إلى **حالته الفعلية** لا إلى معالج جديد.
  ///
  /// القاعدة (قرار المالك):
  ///   • استشارة مؤكَّدة ومحادثتها مفتوحة ⇒ ندخل المحادثة مباشرةً.
  ///   • استشارة قائمة بلا محادثة ⇒ الشاشة الرئيسية حيث بطاقة «بانتظار
  ///     المحامي» (الحضورية أيضاً: موعد بلا شات).
  ///   • دفعة معلّقة ⇒ الرئيسية حيث بطاقة «قيد المراجعة».
  /// في كل الحالات نُحدّث من السيرفر أولاً كي لا نعتمد ذاكرة قديمة.
  Future<void> _returnToCurrentState() async {
    await _loadAll();
    if (!mounted) return;

    final active = _activeConsultation;
    if (active != null) {
      final sType = (active['service_type'] ?? 0) as int;
      final chatOpen = active['chat_started_at'] != null;
      // الحضورية بلا محادثة إطلاقاً (قرار المالك) ⇒ تبقى على الرئيسية.
      if (sType == 0 && chatOpen) {
        setState(() { _screen = 0; _selectedSlot = null; _selectedDayKey = null; });
        _openChat(active['id'].toString());
        return;
      }
    }
    // لا محادثة مفتوحة ⇒ الرئيسية: تعرض بطاقة الانتظار/الدفعة المعلّقة.
    setState(() {
      _screen = 0;
      _viewingPending = false;
      _isContinuing = false;
      _continueChatId = null;
      _selectedSlot = null;
      _selectedDayKey = null;
      _slotsFuture = null;
      _subjectCtrl.clear();
      _attachments.clear();
      _channel = '';
      _proofImage = null;
      _refCtrl.clear();
      _senderPhoneCtrl.clear();
    });
  }

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
    final data = await legal.fetchFreeSlots(days: 30);
    if (!mounted) return;
    final slotError = (data['error'] ?? '').toString();
    if (slotError.isNotEmpty) {
      _snack(ErrorUtils.arabicMessage(slotError));
      return;
    }
    final slots = (data['slots'] as List?)?.cast<String>() ?? <String>[];
    if (slots.isEmpty) {
      _snack('لا توجد مواعيد متاحة خلال الثلاثين يوماً القادمة');
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
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold),
            // 🔙 NAV-001: إن كان لديه طلب قائم (استشارة أو دفعة معلّقة)
            // نعيده لحالته لا لخطوة سابقة في معالج لن يُكمله.
            onPressed: () => _hasOngoing()
                ? _returnToCurrentState()
                : _goTo(_serviceType == 0 ? 3 : 7))),
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
            // 💳 PAY-001 (2026-08-15) — بلاغ المالك: «بعد ما انقبلت الدفعة
            // وصلت للإرسال للمحامي رجع عطاني إنو لازم أدفع».
            // السبب: هذه الشاشة كانت تفحص الرصيد المجاني **فقط** وتتجاهل
            // `_approvedPayment` — وهي دفعة **مقبولة من الإدارة وغير مرتبطة
            // بأي استشارة بعد** (يحسبها `_load` عبر linkedPaymentIds).
            // فكان المستخدم يُدفع لشاشة الدفع مرة ثانية بعد أن دفع فعلاً.
            // الآن: الدفعة المقبولة لنفس النوع تُرسل الطلب مباشرةً.
            if (_hasApprovedPaymentFor(_serviceType)) { _submitConsultation(); return; }
            _goTo(5);
          },
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          label: Text(
              (_hasCredit(_serviceType) || _hasApprovedPaymentFor(_serviceType))
                  ? 'إرسال الطلب للمحامي'
                  : 'متابعة للدفع',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
        )),
      ])));
  }

  // ── الدفع ──
  Widget _buildPaymentForm() {
    final config = context.watch<ConfigProvider>().config;
    final channels = config?.enabledPayChannels ?? [];
    final price = _isContinuing
        ? _renewPrice
        : _v2Flow == 'onsite_convert'
            ? (_onsitePrice - _phonePrice).clamp(0, _onsitePrice)
            : _priceFor(_serviceType);
    return Scaffold(backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBackground, elevation: 0,
        title: const Text('الدفع', style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold),
            // 🔙 NAV-001: نفس القاعدة — لا نُرجعه لمعالج جديد وله طلب قائم.
            onPressed: () => _hasOngoing()
                ? _returnToCurrentState()
                : _goTo(_isContinuing ? 3 : 4))),
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
  /// 📅 UI-CAL-001 (2026-08-15) — نمط التقويم بدل القائمة الطويلة.
  ///
  /// بلاغ المالك: «بالأوقات في الاستشارة الحضورية بفضّل نمط التقويم لأن
  /// الشاشة فوضوية هيك».
  ///
  /// كانت الشاشة تسرد **كل** المواعيد دفعةً واحدة: 14 يوماً × 8 مواعيد
  /// = حتى **80 زراً** في تمرير واحد، فيضيع المستخدم ولا يرى بنية الأيام.
  ///
  /// التصميم الجديد — خطوتان واضحتان:
  ///   ① شريط أيام أفقي (اليوم/غداً/اسم اليوم + رقم) مع عدّاد المتاح لكل يوم.
  ///   ② أوقات اليوم المختار وحده في شبكة مرتّبة.
  /// الأيام بلا مواعيد لا تظهر إطلاقاً — لا نعرض ما لا يمكن اختياره.
  Widget _buildSlotPicker() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: const Text('اختر موعد الجلسة',
            style: TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.primaryGold),
          onPressed: () => _goTo(1),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _slotsFuture ??= context.read<LegalProvider>().fetchFreeSlots(
          days: 30,
          parentConsultationId:
              (_v2Flow == 'onsite_convert' ||
                      _v2Flow == 'onsite_reschedule') &&
                  !_allowOtherLawyer
                  ? (_continueChatId ?? '')
                  : '',
        ),
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGold));
          }
          final slotError = (snap.data?['error'] ?? '').toString();
          if (slotError.isNotEmpty) return _slotsLoadErrorView(slotError);
          final slots = (snap.data?['slots'] as List?)?.cast<String>() ?? <String>[];
          _slotLawyerAlias = (snap.data?['lawyer_alias'] ?? '').toString();

          if (slots.isEmpty) return _noSlotsView();

          // تجميع حسب اليوم مع الحفاظ على الترتيب الزمني
          final byDay = <String, List<DateTime>>{};
          for (final s in slots) {
            final dt = DateTime.tryParse(s)?.toLocal();
            if (dt == null) continue;
            final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
                '${dt.day.toString().padLeft(2, '0')}';
            byDay.putIfAbsent(key, () => []).add(dt);
          }
          final dayKeys = byDay.keys.toList()..sort();
          if (dayKeys.isEmpty) return _noSlotsView();

          // اليوم المختار: أول يوم متاح ما لم يكن المستخدم اختار غيره
          final activeDay = (_selectedDayKey != null && byDay.containsKey(_selectedDayKey))
              ? _selectedDayKey!
              : dayKeys.first;
          final dayTimes = byDay[activeDay] ?? const <DateTime>[];

          return Column(children: [
            // ── رأس: نوع الجلسة وسعرها والمحامي ──
            Padding(
              padding: AppTheme.paddingAllLarge,
              child: Container(
                padding: AppTheme.paddingAllMedium,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold.withOpacity(0.08),
                  borderRadius: AppTheme.radiusMedium,
                  border: Border.all(color: AppTheme.primaryGold.withOpacity(0.35)),
                ),
                child: Row(children: [
                  const Icon(Icons.business, color: AppTheme.primaryGold, size: 20),
                  AppTheme.gapWidthSmall,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('جلسة حضورية — ${_fmt(_onsitePrice)} ل.س',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.textWhite, fontWeight: FontWeight.bold, fontSize: 14)),
                      if (_slotLawyerAlias.isNotEmpty)
                        Text('⚖️ $_slotLawyerAlias',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.primaryGold, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
            ),

            // ── ① شريط الأيام ──
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: dayKeys.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final k = dayKeys[i];
                  final d = byDay[k]!.first;
                  final isActive = k == activeDay;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedDayKey = k;
                      _selectedSlot = null; // تغيير اليوم يُلغي اختيار الوقت
                    }),
                    child: Container(
                      width: 68,
                      decoration: BoxDecoration(
                        color: isActive ? AppTheme.primaryGold : AppTheme.surfaceBlack,
                        borderRadius: AppTheme.radiusMedium,
                        border: Border.all(
                            color: isActive ? AppTheme.primaryGold : Colors.white24),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(_dayLabel(d),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: isActive ? Colors.black : AppTheme.textGrey,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${d.day}/${d.month}',
                            style: TextStyle(
                                color: isActive ? Colors.black : AppTheme.textWhite,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.black.withOpacity(0.15)
                                : AppTheme.primaryGold.withOpacity(0.18),
                            borderRadius: AppTheme.radiusSmall,
                          ),
                          child: Text('${byDay[k]!.length} موعد',
                              style: TextStyle(
                                  color: isActive ? Colors.black : AppTheme.primaryGold,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),

            const Divider(color: Colors.white12, height: 20),

            // ── ② أوقات اليوم المختار ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Text('أوقات ${_fullDayLabel(dayTimes.first)}',
                      style: const TextStyle(
                          color: AppTheme.primaryGold, fontWeight: FontWeight.bold, fontSize: 13)),
                  AppTheme.gapHeightSmall,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: dayTimes.map((dt) {
                      final iso = dt.toUtc().toIso8601String();
                      final sel = _selectedSlot != null &&
                          DateTime.tryParse(_selectedSlot!)?.toUtc() == dt.toUtc();
                      return GestureDetector(
                        onTap: () => setState(() => _selectedSlot = iso),
                        child: Container(
                          width: 88,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: sel ? AppTheme.primaryGold : AppTheme.surfaceBlack,
                            borderRadius: AppTheme.radiusMedium,
                            border: Border.all(color: sel ? AppTheme.primaryGold : Colors.white24),
                          ),
                          child: Center(
                            child: Text(
                              '${dt.hour.toString().padLeft(2, '0')}:'
                              '${dt.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                  color: sel ? Colors.black : AppTheme.textWhite,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  AppTheme.gapHeightLarge,
                  const Center(
                    child: Text('💡 الجلسة الحضورية موعد في المكتب — لا محادثة فيها',
                        style: TextStyle(color: AppTheme.textGrey, fontSize: 11)),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

            // ── زر المتابعة مثبَّت أسفل الشاشة (لا يضيع بالتمرير) ──
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _selectedSlot == null
                        ? null
                        : _v2Flow == 'onsite_reschedule'
                            ? _rescheduleLegalAppointment
                            : (_v2IntentId != null &&
                                    _pendingV2Intent?['status'] == 'payment_needs_slot')
                                ? _replaceV2Reservation
                                : () => _goTo(_v2Flow == 'onsite_convert' ? 5 : 4),
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    label: Text(
                        _selectedSlot == null
                            ? 'اختر موعداً للمتابعة'
                            : 'متابعة — ${_selectedSlotLabel()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGold),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  /// تسمية مختصرة لبطاقة اليوم في الشريط.
  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = that.difference(today).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'غداً';
    const names = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    return names[d.weekday - 1];
  }

  /// تسمية كاملة لعنوان قسم الأوقات.
  String _fullDayLabel(DateTime d) {
    const names = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    return '${names[d.weekday - 1]} ${d.day}/${d.month}';
  }

  /// الوقت المختار مختصراً لعرضه على زر المتابعة.
  String _selectedSlotLabel() {
    final dt = DateTime.tryParse(_selectedSlot ?? '')?.toLocal();
    if (dt == null) return '';
    return '${_dayLabel(dt)} ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _rescheduleLegalAppointment() async {
    if (_rescheduleAppointmentId == null || _selectedSlot == null) return;
    setState(() => _submitting = true);
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'reschedule_legal_appointment_v2',
        'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'appointment_id': _rescheduleAppointmentId,
        'slot': _selectedSlot,
        'idempotency_key': _newUuid(),
      });
      final data = res.data as Map<String, dynamic>?;
      if (data?['success'] == true && mounted) {
        _snack('✅ تم تغيير موعد الجلسة بنفس الدفعة');
        context.go('/user/my-appointments');
      } else {
        _snack(ErrorUtils.arabicMessage(data?['error']));
      }
    } catch (e) {
      _snack(ErrorUtils.arabicMessage(e));
    }
    if (mounted) setState(() => _submitting = false);
  }

  void _startReplaceV2Reservation() {
    final intent = _pendingV2Intent;
    if (intent == null) return;
    setState(() {
      _v2IntentId = intent['id']?.toString();
      _v2Flow = intent['flow']?.toString() ?? 'onsite_new';
      _continueChatId = intent['parent_consultation_id']?.toString();
      _serviceType = 1;
      _allowOtherLawyer = false;
      _slotsFuture = null;
      _selectedSlot = null;
      _selectedDayKey = null;
      _screen = 7;
    });
  }

  Future<void> _replaceV2Reservation() async {
    if (_v2IntentId == null || _selectedSlot == null) return;
    setState(() => _submitting = true);
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'replace_consultation_reservation_v2',
        'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'intent_id': _v2IntentId,
        'slot': _selectedSlot,
        'allow_other_lawyer': _allowOtherLawyer,
        'idempotency_key': _newUuid(),
      });
      final data = res.data as Map<String, dynamic>?;
      if (data?['success'] == true) {
        await _loadAll();
        if (mounted) {
          _goTo(6);
          _snack('✅ تم تثبيت الموعد الجديد على دفعتك الحالية');
        }
      } else {
        _snack(ErrorUtils.arabicMessage(data?['error']));
      }
    } catch (e) {
      _snack(ErrorUtils.arabicMessage(e));
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _joinSameLawyerWaitlist() async {
    final parent = _continueChatId ?? '';
    if (parent.isEmpty) return;
    try {
      final res = await SupabaseService().invokeFunction('legal-actions', body: {
        'action': 'join_consultation_waitlist_v2',
        'user_uid': context.read<AuthProvider>().userModel?.uid ?? '',
        'parent_consultation_id': parent,
      });
      final data = res.data as Map<String, dynamic>?;
      _snack(data?['success'] == true
          ? '✅ سنشعرك عند توفر موعد مع محاميك'
          : ErrorUtils.arabicMessage(data?['error']));
    } catch (e) {
      _snack(ErrorUtils.arabicMessage(e));
    }
  }

  void _showAlternateLawyerSlots() {
    setState(() {
      _allowOtherLawyer = true;
      _slotsFuture = null;
      _selectedSlot = null;
      _selectedDayKey = null;
    });
  }

  Widget _slotsLoadErrorView(String code) {
    return Center(
      child: Padding(
        padding: AppTheme.paddingAllXL,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 56, color: AppTheme.errorRed),
          AppTheme.gapHeightLarge,
          Text(
            ErrorUtils.arabicMessage(code),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textWhite, fontSize: 14),
          ),
          AppTheme.gapHeightLarge,
          ElevatedButton.icon(
            onPressed: () => setState(() {
              _slotsFuture = null;
              _selectedSlot = null;
              _selectedDayKey = null;
            }),
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ]),
      ),
    );
  }

  /// حالة «لا مواعيد» — مفصولة لتُستدعى من موضعين بلا تكرار.
  Widget _noSlotsView() {
    return Center(
      child: Padding(
        padding: AppTheme.paddingAllXL,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.event_busy, size: 60, color: AppTheme.warningOrange),
          AppTheme.gapHeightLarge,
          const Text('لا توجد مواعيد خلال 30 يوماً',
              style: TextStyle(color: AppTheme.textWhite, fontSize: 17, fontWeight: FontWeight.bold)),
          AppTheme.gapHeightSmall,
          const Text('جميع مواعيد المحامي محجوزة أو خارج أوقات الدوام.\nجرّب لاحقاً أو اختر استشارة هاتفية.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textGrey, fontSize: 13, height: 1.6)),
          AppTheme.gapHeightXL,
          if (_v2Flow == 'onsite_convert' && !_allowOtherLawyer) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _joinSameLawyerWaitlist,
                icon: const Icon(Icons.notifications_active),
                label: const Text('أعلمني عند توفر موعد مع محاميّ'),
              ),
            ),
            AppTheme.gapHeightSmall,
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showAlternateLawyerSlots,
                icon: const Icon(Icons.swap_horiz, color: AppTheme.primaryGold),
                label: const Text('عرض مواعيد محامٍ آخر بموافقتي',
                    style: TextStyle(color: AppTheme.primaryGold)),
              ),
            ),
            AppTheme.gapHeightSmall,
          ],
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () { setState(() { _serviceType = 0; }); _goTo(3); },
              icon: const Icon(Icons.phone_in_talk, color: AppTheme.primaryGold),
              label: Text('استشارة هاتفية بدلاً منها (${_fmt(_phonePrice)} ل.س)',
                  style: const TextStyle(color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.primaryGold)),
            ),
          ),
        ]),
      ),
    );
  }


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
        // 🔙 NAV-001: كان `_resetWizard()` يصفّر كل شيء ويعود لمعالج جديد.
        // الآن يعود لحالته الفعلية (محادثة مفتوحة / بطاقة انتظار).
        _returnToCurrentState();
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
      if (_pendingV2Intent?['status'] == 'payment_needs_slot') ...[
        AppTheme.gapHeightMedium,
        Container(
          width: double.infinity,
          padding: AppTheme.paddingAllMedium,
          decoration: BoxDecoration(
            color: AppTheme.warningOrange.withOpacity(0.12),
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(color: AppTheme.warningOrange),
          ),
          child: const Text(
            'انتهت مهلة الموعد المؤقت. اختر موعداً جديداً وستبقى الدفعة نفسها دون دفع ثانٍ.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.warningOrange),
          ),
        ),
        AppTheme.gapHeightSmall,
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startReplaceV2Reservation,
            icon: const Icon(Icons.event_repeat),
            label: const Text('اختيار موعد جديد'),
          ),
        ),
      ],
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
